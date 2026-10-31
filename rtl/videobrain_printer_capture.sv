`timescale 1ns/1ps
module videobrain_printer_capture #(
    parameter CLOCK_HZ = 14318180,
    parameter FLUSH_TICKS = CLOCK_HZ * 5,
    parameter STALL_TICKS = CLOCK_HZ * 10
)(
    input wire clk,
    input wire reset,
    input wire serial_in,
    input wire baud110,
    input wire start,
    input wire stop,
    input wire img_mounted,
    input wire img_readonly,
    input wire [63:0] img_size,
    output wire busy,
    output wire active,
    output wire stalled,
    output reg mounted = 0,
    output reg [3:0] error = 0,
    output reg [3:0] status_code,
    output reg [31:0] sd_lba = 0,
    output reg sd_rd = 0,
    output reg sd_wr = 0,
    input wire sd_ack,
    input wire [8:0] sd_buff_addr,
    input wire [7:0] sd_buff_dout,
    output reg [7:0] sd_buff_din,
    input wire sd_buff_wr
);
localparam [3:0] IDLE=0, SCAN_REQ=1, WAIT_IO=2, SCAN_CHECK=3, BUILD=4,
           CRC=5, CRC_STORE=6, WRITE_REQ=7, VERIFY_REQ=8, VERIFY_CHECK=9,
           ARM=10, RUN=11, FAULT=12;
localparam [2:0] START=1, DATA=2, STOP=3;
reg [3:0] state = IDLE, after_io = IDLE;
reg readonly = 1, scanning = 0, accepting = 0;
reg session_open = 0, stopping = 0, rate = 0, drop_tail = 0;
reg start_d = 0, stop_d = 0, reset_d = 0;
reg [31:0] sectors = 0, scan_lba = 0, append_lba = 1;
reg zero_seen = 0, scan_open = 0, scan_rate = 0;
reg [31:0] record_seq = 1, session = 0;
reg [63:0] length = 0;
reg [2:0] kind = 0;
reg [15:0] payload_count = 0;
reg [2:0] reason = 0;
reg [31:0] framing_count = 0, rejected_count = 0, lost_count = 0, stall_count = 0;
reg [31:0] flush_timer = 0, stall_timer = 0;
reg stall_latched = 0;
reg [1:0] io_phase = 0;
reg io_verify = 0, mismatch = 0, all_zero = 1, padding_ok = 1;
reg [255:0] header = 0;
reg [31:0] read_crc = 32'hffffffff, build_crc = 32'hffffffff;
reg [9:0] build_index = 0;
reg [1:0] crc_index = 0;
reg [7:0] staging[512];
reg [7:0] fifo[4096];
reg [11:0] write_ptr = 0, read_ptr = 0;
reg [12:0] fifo_count = 0;
reg [7:0] fifo_q;
wire [7:0] stage_crc_q = sd_buff_din;
wire stage_write = state == BUILD || state == CRC_STORE;
wire [8:0] stage_write_addr = state == CRC_STORE ? 9'd28 + {7'd0,crc_index} : build_index[8:0];
wire [7:0] stage_write_data = state == CRC_STORE ? ~build_crc[crc_index*8 +: 8] :
                              pop ? fifo_q : header_byte(build_index[8:0], reason);
wire [8:0] stage_read_addr = state == CRC ? build_index[8:0] : sd_buff_addr;
reg mount_pending = 0;
reg [63:0] pending_size = 0;
reg pending_readonly = 1;

wire [7:0] rx_data;
wire rx_valid, rx_framing, rx_rejected, rx_busy, rx_idle;
wire rx_abort = reset || img_mounted || !session_open || drop_tail;
wire push = rx_valid && session_open && !rx_abort;
wire pop = state == BUILD && kind == DATA && build_index >= 32 &&
           {6'd0,build_index} < 16'd32 + payload_count;
wire enqueue = push && (fifo_count != 4096 || pop);
assign active = accepting;
assign busy = scanning || session_open || state != IDLE && state != FAULT || mount_pending;
assign stalled = state == WAIT_IO && stall_latched;

videobrain_printer_rx #(.CLOCK_HZ(CLOCK_HZ)) receiver (
    .clk(clk), .abort_frame(rx_abort), .enable(accepting && !stop && !reset),
    .baud110(rate), .serial_in(serial_in), .data(rx_data), .valid(rx_valid),
    .framing(rx_framing), .rejected(rx_rejected), .busy(rx_busy), .idle_ready(rx_idle)
);

function automatic [31:0] crc_byte(input [31:0] c, input [7:0] b);
    reg [31:0] n;
    begin
        n = c ^ {24'd0,b};
        for (integer i=0; i<8; i=i+1) n = n[0] ? (n >> 1) ^ 32'hedb88320 : n >> 1;
        crc_byte = n;
    end
endfunction

function automatic [7:0] header_byte(input [8:0] addr, input [2:0] stop_reason);
    reg [255:0] h;
    begin
        h = 0;
        h[31:0] = 32'h31525056; // vpr1
        h[63:32] = record_seq;
        h[95:64] = session;
        h[103:96] = {5'd0,kind};
        h[111:104] = {7'd0,rate};
        h[127:112] = payload_count;
        h[191:128] = length;
        h[223:192] = kind == STOP ? {29'd0,stop_reason} : 32'd0;
        header_byte = addr < 32 ? h[addr[4:0]*8 +: 8] : 8'd0;
        if (kind == STOP && addr >= 32 && addr < 48) begin
            case (addr[3:2])
                0: header_byte = framing_count[addr[1:0]*8 +: 8];
                1: header_byte = rejected_count[addr[1:0]*8 +: 8];
                2: header_byte = lost_count[addr[1:0]*8 +: 8];
                3: header_byte = stall_count[addr[1:0]*8 +: 8];
            endcase
        end
    end
endfunction

always_comb begin
    if (stalled) status_code = 6;
    else if (scanning) status_code = 1;
    else if (session_open && stopping) status_code = 5;
    else if (accepting) status_code = 4;
    else if (session_open) status_code = 3;
    else if (error == 8) status_code = 7;
    else if (error != 0 || state == FAULT) status_code = 8;
    else if (mounted) status_code = 2;
    else status_code = 0;
end

// read-before-write ram, indices one cycle ahead
always @(posedge clk) begin
    sd_buff_din <= staging[stage_read_addr];
    fifo_q <= fifo[read_ptr + 12'(pop)];
    if (enqueue) fifo[write_ptr] <= rx_data;
    if (stage_write) staging[stage_write_addr] <= stage_write_data;
end

task automatic request_io(input bit writing, input bit verify, input [31:0] lba,
                           input [3:0] next_state);
    begin
        sd_lba <= lba;
        sd_rd <= !writing;
        sd_wr <= writing;
        io_phase <= 1;
        io_verify <= verify;
        after_io <= next_state;
        mismatch <= 0;
        header <= 0;
        all_zero <= 1;
        padding_ok <= 1;
        read_crc <= 32'hffffffff;
        stall_timer <= 0;
        stall_latched <= 0;
        state <= WAIT_IO;
    end
endtask

task automatic build_record(input [2:0] record_kind, input [15:0] count);
    begin
        kind <= record_kind;
        payload_count <= count;
        build_index <= 0;
        state <= BUILD;
    end
endtask

always @(posedge clk) begin
    start_d <= start;
    stop_d <= stop;
    reset_d <= reset;
    if (enqueue) write_ptr <= write_ptr + 1'b1;
    if (pop) read_ptr <= read_ptr + 1'b1;
    case ({enqueue,pop})
        2'b10: fifo_count <= fifo_count + 1'b1;
        2'b01: fifo_count <= fifo_count - 1'b1;
        default: ;
    endcase
    if (fifo_count == 0) flush_timer <= 0;
    else if (flush_timer < FLUSH_TICKS) flush_timer <= flush_timer + 1'b1;

    if (sd_buff_wr && sd_ack && state == WAIT_IO && sd_rd == 0 && io_phase != 0) begin
        if (io_verify) begin
            if (sd_buff_dout != sd_buff_din) mismatch <= 1;
        end else begin
            if (sd_buff_addr < 32) header[sd_buff_addr[4:0]*8 +: 8] <= sd_buff_dout;
            if (sd_buff_dout != 0) all_zero <= 0;
            if (scan_lba == 0) begin
                if (sd_buff_addr >= 20 && sd_buff_addr < 28 || sd_buff_addr >= 32)
                    if (sd_buff_dout != 0) padding_ok <= 0;
            end else if ({7'd0,sd_buff_addr} >= 16'd32 + header[127:112] && sd_buff_dout != 0)
                padding_ok <= 0;
        end
        read_crc <= crc_byte(read_crc,
            sd_buff_addr >= 28 && sd_buff_addr < 32 ? 8'd0 : sd_buff_dout);
    end

    case (state)
        IDLE: begin
            if (start && !start_d && !reset && !img_mounted) begin
                if (!mounted) error <= 1;
                else if (readonly) error <= 2;
                else if (append_lba + 2 >= sectors) error <= 8;
                else begin
                    error <= 0;
                    session <= session + 1'b1;
                    session_open <= 1;
                    stopping <= 0;
                    drop_tail <= 0;
                    reason <= 0;
                    rate <= baud110;
                    framing_count <= 0;
                    rejected_count <= 0;
                    lost_count <= 0;
                    stall_count <= 0;
                    build_record(START,0);
                end
            end
        end
        SCAN_REQ: request_io(0,0,scan_lba,SCAN_CHECK);
        WAIT_IO: begin
            if (stall_timer < STALL_TICKS) stall_timer <= stall_timer + 1'b1;
            else if (!stall_latched) begin
                stall_latched <= 1;
                if (session_open) stall_count <= stall_count + 1'b1;
            end
            if (io_phase == 1 && sd_ack) begin
                sd_rd <= 0;
                sd_wr <= 0;
                io_phase <= 2;
            end
            if (io_phase == 2 && !sd_ack) begin
                io_phase <= 0;
                stall_latched <= 0;
                state <= after_io;
            end
        end
        SCAN_CHECK: begin
            if (scan_lba == 0) begin
                if (header[31:0] != 32'h31504256 || header[63:32] != 1 ||
                    header[95:64] != 512 || header[127:96] != 32 ||
                    header[159:128] != sectors || !padding_ok ||
                    header[255:224] != ~read_crc) begin error <= 3; state <= FAULT; scanning <= 0; end
                else begin scan_lba <= 1; state <= SCAN_REQ; end
            end else if (all_zero) begin
                zero_seen <= 1;
                if (!zero_seen) append_lba <= scan_lba;
                if (scan_lba + 1 == sectors) begin
                    scanning <= 0;
                    if (scan_open) begin error <= 4; state <= FAULT; end
                    else state <= IDLE;
                end else begin scan_lba <= scan_lba + 1'b1; state <= SCAN_REQ; end
            end else if (zero_seen || header[31:0] != 32'h31525056 ||
                header[63:32] != record_seq || header[191:128] != length ||
                header[111:104] > 1 || header[127:112] > 480 ||
                header[255:224] != ~read_crc || !padding_ok) begin
                error <= 3; state <= FAULT; scanning <= 0;
            end else begin
                state <= SCAN_REQ;
                scan_lba <= scan_lba + 1'b1;
                append_lba <= scan_lba + 1'b1;
                record_seq <= record_seq + 1'b1;
                case (header[103:96])
                    START: begin
                        if (scan_open || header[95:64] != session + 1 ||
                            header[127:112] != 0 || header[223:192] != 0) begin error <= 3; state <= FAULT; scanning <= 0; end
                        session <= header[95:64];
                        scan_rate <= header[104];
                        scan_open <= 1;
                    end
                    DATA, STOP: begin
                        if (!scan_open || header[95:64] != session || header[104] != scan_rate ||
                            (header[103:96] == DATA && (header[127:112] == 0 || header[223:192] != 0)) ||
                            (header[103:96] == STOP && (header[127:112] != 16 || header[223:192] > 4))) begin
                            error <= 3; state <= FAULT; scanning <= 0;
                        end
                        if (header[103:96] == DATA) length <= length + {48'd0,header[127:112]};
                        else begin
                            scan_open <= 0;
                            if (header[223:192] != 0) begin error <= 4; state <= FAULT; scanning <= 0; end
                        end
                    end
                    default: begin error <= 3; state <= FAULT; scanning <= 0; end
                endcase
                if (scan_lba + 1 == sectors) begin error <= 8; state <= FAULT; scanning <= 0; end
            end
        end
        BUILD: begin
            build_index <= build_index + 1'b1;
            if (build_index == 511) begin
                build_index <= 0;
                build_crc <= 32'hffffffff;
                state <= CRC;
            end
        end
        CRC: begin
            if (build_index != 0) build_crc <= crc_byte(build_crc,stage_crc_q);
            build_index <= build_index + 1'b1;
            if (build_index == 512) begin state <= CRC_STORE; crc_index <= 0; end
        end
        CRC_STORE: begin
            crc_index <= crc_index + 1'b1;
            if (crc_index == 3) state <= WRITE_REQ;
        end
        WRITE_REQ: request_io(1,0,append_lba,VERIFY_REQ);
        VERIFY_REQ: request_io(0,1,append_lba,VERIFY_CHECK);
        VERIFY_CHECK: begin
            if (mismatch) begin error <= 5; accepting <= 0; session_open <= 0; state <= FAULT; end
            else begin
                append_lba <= append_lba + 1'b1;
                record_seq <= record_seq + 1'b1;
                case (kind)
                    START: state <= ARM;
                    DATA: begin length <= length + {48'd0,payload_count}; state <= RUN; end
                    STOP: begin session_open <= 0; stopping <= 0; state <= error == 0 ? IDLE : FAULT; end
                    default: state <= FAULT;
                endcase
            end
        end
        ARM: begin
            if (stopping) state <= RUN;
            else if (rx_idle) begin accepting <= 1; state <= RUN; end
        end
        RUN: begin
            if (append_lba + 1 >= sectors && fifo_count != 0) begin
                drop_tail <= 1;
                accepting <= 0; stopping <= 1; reason <= 4; error <= 8;
                lost_count <= lost_count + {19'd0,fifo_count};
                fifo_count <= 0; read_ptr <= write_ptr;
            end else if (fifo_count != 0 && (fifo_count >= 480 || flush_timer >= FLUSH_TICKS || stopping && !rx_busy)) begin
                build_record(DATA, fifo_count >= 480 ? 16'd480 : {3'd0,fifo_count});
                flush_timer <= 0;
            end else if (stopping && !rx_busy && !rx_valid && fifo_count == 0) build_record(STOP,16);
        end
        default: ;
    endcase

    if (session_open && rx_rejected) rejected_count <= rejected_count + 1'b1;
    if (session_open && stop && !stop_d) begin accepting <= 0; stopping <= 1; end
    if (session_open && reset && !reset_d) begin
        drop_tail <= 1;
        accepting <= 0; stopping <= 1; reason <= 1; error <= 10;
    end
    if (session_open && rx_framing) begin
        drop_tail <= 1;
        accepting <= 0; stopping <= 1; reason <= 2; error <= 6;
        framing_count <= framing_count + 1'b1;
    end
    if (push && !enqueue) begin
        drop_tail <= 1;
        accepting <= 0; stopping <= 1; reason <= 3; error <= 7;
        lost_count <= lost_count + 1'b1;
    end

    // finish outstanding exchange before handling media change
    if (img_mounted) begin
        mount_pending <= 1;
        pending_size <= img_size;
        pending_readonly <= img_readonly;
        accepting <= 0;
        if (session_open) error <= 9;
        session_open <= 0;
        scanning <= 0;
        if (state != WAIT_IO) state <= IDLE;
    end
    if (mount_pending && state != WAIT_IO && !img_mounted) begin
        mount_pending <= 0;
        sd_rd <= 0; sd_wr <= 0; io_phase <= 0;
        mounted <= pending_size != 0;
        readonly <= pending_readonly;
        record_seq <= 1; session <= 0; length <= 0;
        append_lba <= 1; scan_lba <= 0; zero_seen <= 0; scan_open <= 0;
        fifo_count <= 0; read_ptr <= 0; write_ptr <= 0; stopping <= 0;
        if (pending_size == 0) begin error <= 0; state <= IDLE; end
        else if (pending_size < 2048 || pending_size > 16777216 || pending_size[8:0] != 0) begin
            error <= 3; state <= FAULT;
        end else begin
            sectors <= 32'(pending_size >> 9);
            error <= 0; scanning <= 1; state <= SCAN_REQ;
        end
    end
end
endmodule

