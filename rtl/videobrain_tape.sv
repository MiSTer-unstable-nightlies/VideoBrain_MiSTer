`timescale 1ns/1ps
module videobrain_tape #(
    parameter CLOCK_HZ = 14318180,
    parameter RECORDING = 1,
    parameter PLAYBACK = 1
)(
    input wire clk,
    input wire reset,
    input wire img_mounted,
    input wire img_readonly,
    input wire [63:0] img_size,
    input wire rewind,
    input wire record_data,
    input wire record_enable,
    input wire playback_enable,
    output reg playback_data = 1,
    output wire busy,
    output wire writable,
    output reg error = 0,
    output reg rewound = 0,
    output reg ended = 0,
    output reg [31:0] sd_lba = 0,
    output reg sd_rd = 0,
    output reg sd_wr = 0,
    input wire sd_ack,
    input wire [8:0] sd_buff_addr,
    input wire [7:0] sd_buff_dout,
    output wire [7:0] sd_buff_din,
    input wire sd_buff_wr
);

localparam IDLE = 0, RECORD = 1, FLUSH = 2, PLAY = 3;
localparam [2:0] HEADER = 0, INVALIDATE = 1, WRITE_DATA = 2, COMMIT = 3, READ_DATA = 4;
localparam [31:0] MAGIC = 32'h31544256; // vbt1
reg [1:0] mode = IDLE, io_state = 0;
reg [2:0] operation = HEADER;
reg mounted = 0, readonly = 1, recognized = 0, valid = 0;
reg mount_pending = 0;
reg [31:0] capacity = 0, length = 0;
reg [31:0] header_magic = 0, header_clock = 0, header_length = 0;
reg [31:0] produced = 0, transferred = 0, consumed = 0;
reg [9:0] io_base = 0;
reg [30:0] elapsed = 1, remaining = 0;
reg level = 1, playing = 0, playback_started = 0;
reg record_d = 0, playback_d = 0, record_session = 0;
reg record_started = 0;
reg record_level = 1;
reg rewind_d = 0, rewind_pending = 0;

wire rewind_request = rewind && !rewind_d && mounted && valid &&
                      !mount_pending && !reset && !img_mounted &&
                      (mode == IDLE || mode == PLAY) &&
                      (io_state == 0 || operation == READ_DATA);

// apl/s enables both remotes at startup, then selects one for a transfer
wire record_remote = record_enable && !playback_enable;
wire playback_remote = playback_enable && !record_enable;
// a remote-only setup can switch to playback without recording data
wire record_cancel = mode == RECORD && !record_started && playback_remote;

// 4 kib buffers sd latency without changing tape timing
wire [31:0] buffer_sample;
reg [1:0] sd_byte;
reg [7:0] header_byte;
wire [9:0] buffer_index = io_base + {3'd0, sd_buff_addr[8:2]};
wire [31:0] capture_position = record_started || record_session ? produced : 0;
wire [31:0] capture_base = record_started ? transferred :
                           record_session ? produced & 32'hffffff80 : 0;
wire capture = mode == RECORD && !record_cancel && !reset && !img_mounted && !error &&
               (!record_remote || record_data != record_level || &elapsed);
wire capture_room = capture_position < capacity && capture_position - capture_base < 1024;
wire capture_allowed = mounted && recognized && !readonly;
wire [31:0] capture_sample = {record_level, elapsed};
wire capture_write = capture && capture_room && capture_allowed;
wire sd_write = sd_buff_wr && operation == READ_DATA && io_state != 0;
wire [9:0] write_index = capture_write ? capture_position[9:0] : buffer_index;
wire [9:0] read_index = mode == PLAY ? consumed[9:0] : buffer_index;
wire [31:0] write_length = operation == COMMIT ? produced : 32'hffffffff;
assign busy = mode != IDLE || io_state != 0 || mount_pending || rewind_pending;
assign writable = mounted && recognized && !readonly && !busy;
assign sd_buff_din = operation == WRITE_DATA ? buffer_sample[sd_byte*8 +: 8] : header_byte;

// record/playback share one write port and one synchronous read port
genvar b;
generate
    for (b = 0; b < 4; b = b + 1) begin : buffer_bank
        reg [7:0] samples[1024];
        reg [7:0] read_q;
        wire write_enable = capture_write || (sd_write && sd_buff_addr[1:0] == b);
        wire [7:0] write_data = capture_write ? capture_sample[b*8 +: 8] : sd_buff_dout;
        assign buffer_sample[b*8 +: 8] = read_q;

        always @(posedge clk) begin
            read_q <= samples[read_index];
            if (write_enable) samples[write_index] <= write_data;
        end
    end
endgenerate

always @(posedge clk) begin
    sd_byte <= sd_buff_addr[1:0];
    case (sd_buff_addr[8:2])
        0: header_byte <= MAGIC[sd_buff_addr[1:0]*8 +: 8];
        1: header_byte <= 8'(CLOCK_HZ >> (sd_buff_addr[1:0] * 8));
        2: header_byte <= write_length[sd_buff_addr[1:0]*8 +: 8];
        default: header_byte <= 0;
    endcase
end

task request(input [2:0] op, input [31:0] lba, input [9:0] base);
begin
    operation <= op;
    sd_lba <= lba;
    io_base <= base;
    sd_rd <= op == HEADER || op == READ_DATA;
    sd_wr <= op != HEADER && op != READ_DATA;
    io_state <= 1;
end
endtask

always @(posedge clk) begin
    record_d <= record_remote;
    playback_d <= playback_remote;
    rewind_d <= rewind;
    rewound <= 0;
    ended <= 0;

    if (sd_buff_wr && operation == HEADER && io_state != 0) begin
        case (sd_buff_addr[8:2])
            0: header_magic[sd_buff_addr[1:0]*8 +: 8] <= sd_buff_dout;
            1: header_clock[sd_buff_addr[1:0]*8 +: 8] <= sd_buff_dout;
            2: header_length[sd_buff_addr[1:0]*8 +: 8] <= sd_buff_dout;
            default: ;
        endcase
    end

    // hold request until ack rises, buffers until ack falls
    if (io_state == 1 && sd_ack) begin
        sd_rd <= 0;
        sd_wr <= 0;
        io_state <= 2;
    end
    if (io_state == 2 && !sd_ack) begin
        io_state <= 0;
        case (operation)
            HEADER: if (!mount_pending && mounted) begin
                recognized <= header_magic == MAGIC && header_clock == CLOCK_HZ;
                valid <= header_magic == MAGIC && header_clock == CLOCK_HZ &&
                         header_length <= capacity;
                length <= header_length;
                error <= header_magic != MAGIC || header_clock != CLOCK_HZ ||
                         header_length > capacity;
            end
            WRITE_DATA, READ_DATA: transferred <= transferred + 128;
            COMMIT: if (mode == FLUSH && !reset && !error) begin
                length <= produced;
                valid <= 1;
                mode <= IDLE;
            end
            default: ;
        endcase
    end

    if (io_state == 0 && !rewind_pending && !rewind_request && !reset && !img_mounted) begin
        if (mount_pending) begin
            mount_pending <= 0;
            header_magic <= 0;
            header_clock <= 0;
            header_length <= 0;
            request(HEADER, 0, 0);
        end else if ((mode == RECORD && record_started) || mode == FLUSH) begin
            if (!error && produced > transferred &&
                (produced - transferred >= 128 || mode == FLUSH))
                request(WRITE_DATA, 1 + (transferred >> 7), transferred[9:0]);
            else if (mode == FLUSH && !error && transferred >= produced)
                request(COMMIT, 0, 0);
        end else if (mode == PLAY && transferred < length &&
                     transferred - consumed <= 896)
            request(READ_DATA, 1 + (transferred >> 7), transferred[9:0]);
    end

    if (RECORDING && record_remote && !record_d && !rewind_pending && !rewind_request && !reset && !img_mounted) begin
        if (writable || (!PLAYBACK && !busy)) begin
            mode <= RECORD;
            record_started <= 0;
            elapsed <= 1;
            record_level <= record_data;
            error <= 0;
        end else begin
            record_session <= 0;
            error <= 1;
        end
    end
    if (mode == RECORD) begin
        if (record_cancel) begin
            mode <= IDLE;
            record_session <= 0;
        end else if (capture) begin
            if (!capture_allowed) begin
                mode <= IDLE;
                record_session <= 0;
                // setup needs no recording image
                if (record_data != record_level) error <= 1;
            end else if (capture_room) begin
                if (!record_started) begin
                    record_started <= 1;
                    record_session <= 1;
                    transferred <= capture_base;
                    playback_started <= 0;
                    valid <= 0;
                    request(INVALIDATE, 0, 0);
                end
                produced <= capture_position + 1'b1;
                elapsed <= 1;
                record_level <= record_data;
                if (!record_remote) mode <= FLUSH;
            end else begin
                record_session <= 0;
                error <= 1;
                mode <= IDLE;
            end
        end else elapsed <= elapsed + 1'b1;
    end

    if (PLAYBACK && playback_remote && !playback_d && !rewind_pending && !rewind_request && !reset && !img_mounted) begin
        record_session <= 0;
        if ((!busy || record_cancel) && valid && length != 0) begin
            mode <= PLAY;
            if (!playback_started) begin
                transferred <= 0;
                consumed <= 0;
                remaining <= 0;
            end
            playback_started <= 1;
            playing <= 0;
            error <= 0;
        end else if (!busy && valid && length == 0) begin
            ended <= 1;
            error <= 0;
        end else if (!RECORDING && !mounted) begin
            // playback motor may run during record-only setup
            error <= 0;
        end else error <= 1;
    end
    if (mode == PLAY) begin
        if (!playback_remote) begin
            mode <= IDLE;
            playing <= 0;
            playback_data <= 1;
        end else if (!playing) begin
            if ((consumed == 0 && transferred >= 1024) ||
                (consumed != 0 && transferred - consumed >= 128) ||
                transferred >= length) playing <= 1;
        end else if (remaining != 0) begin
            playback_data <= level;
            remaining <= remaining - 1'b1;
        end
        else if (consumed < length) begin
            if (consumed < transferred && buffer_sample[30:0] >= 2) begin
                level <= buffer_sample[31];
                playback_data <= buffer_sample[31];
                remaining <= buffer_sample[30:0] - 1'b1;
                consumed <= consumed + 1'b1;
            end else begin
                error <= 1;
                mode <= IDLE;
                playback_data <= 1;
            end
        end else begin
            // release after full final interval even if motor remote stays enabled
            mode <= IDLE;
            playing <= 0;
            playback_data <= 1;
            ended <= 1;
        end
    end

    // rewind after outstanding sd read
    if (rewind_request) begin
        ended <= 0;
        rewind_pending <= 1;
        mode <= IDLE;
        playing <= 0;
        playback_data <= 1;
    end

    if (rewind_pending && io_state == 0) begin
        rewound <= 1;
        rewind_pending <= 0;
        transferred <= 0;
        consumed <= 0;
        remaining <= 0;
        playback_started <= 0;
        record_session <= 0;
        record_started <= 0;
        playing <= 0;
        playback_data <= 1;
        level <= 1;
        mode <= IDLE;
        error <= 0;
    end

    // finish sd handshake after reset or media change
    if (reset || img_mounted) begin
        ended <= 0;
        rewound <= 0;
        rewind_pending <= 0;
        mode <= IDLE;
        record_session <= 0;
        record_started <= 0;
        playback_started <= 0;
        playing <= 0;
        playback_data <= 1;
    end
    if (img_mounted) begin
        mounted <= img_size >= 1024 && img_size[63:32] == 0;
        readonly <= img_readonly;
        recognized <= 0;
        valid <= 0;
        capacity <= (({9'd0, img_size[31:9]} - 1'b1) << 7);
        mount_pending <= img_size >= 1024 && img_size[63:32] == 0;
        error <= img_size != 0 && (img_size < 1024 || img_size[63:32] != 0);
    end
end
endmodule
