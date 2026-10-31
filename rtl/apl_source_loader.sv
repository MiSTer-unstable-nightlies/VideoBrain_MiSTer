`timescale 1ns/1ps
module apl_source_loader #(
    parameter [7:0] LINE_FRAMES = 64,
    parameter integer RTC_CLOCK_HZ = 14318181
)(
    input wire clk,
    input wire reset,
    input wire frame_tick,
    input wire download,
    input wire wr,
    input wire [24:0] addr,
    input wire [7:0] data,
    input wire available,
    input wire music_available,
    input wire symbols,
    input wire input_ready,
    input wire key_accepted,
    input wire music_playback,
    input wire auto_repeat,
    input wire enabled,
    input wire cancel,
    input wire [64:0] rtc,
    output wire [55:0] rtc_time,
    output wire rtc_time_valid,
    output wire busy,
    output reg started = 0,
    output reg complete = 0,
    output reg aborted = 0,
    output reg error = 0,
    output reg [35:0] keys = 0
);

localparam IDLE = 0, RECEIVE = 1, WAIT_START = 2, READ_KEY = 3,
           SELECT_KEY = 4, HOLD_KEY = 5, RELEASE_KEY = 6,
           BANK_READY = 7, READ_HOLD = 8, SELECT_HOLD = 9, READ_GAP = 10,
           SELECT_GAP = 11, BANK_HOLD = 12, BANK_RELEASE = 13, SHIFT_WAIT = 14,
           RTC_DIGIT = 15;
localparam [7:0] RTC_INSERT = 8'hf7;
localparam [7:0] MODE_LETTERS = 8'hf8, MODE_SYMBOLS = 8'hf9;
localparam [7:0] MUSIC_LOW = 8'hfa, MUSIC_MIDDLE = 8'hfb, MUSIC_HIGH = 8'hfc;
localparam [7:0] MUSIC_REPLAY = 8'hfd, MUSIC_RECORD = 8'hfe;
reg [3:0] state = IDLE;
reg download_d = 0;
reg bad = 0;
reg [12:0] received = 0;
reg [15:0] length = 0, expected_crc = 0, crc = 16'hffff;
reg [11:0] position = 0;
reg [7:0] memory [0:4095];
reg [7:0] token;
reg [7:0] frames = 0;
reg [8:0] bank_gap = 0;
reg shifting = 0, shifted = 0;
reg timed = 0, rtc_script = 0, rtc_requested = 0;
reg rtc_active = 0;
reg [3:0] rtc_index = 0;
reg [7:0] rtc_hold, rtc_gap;
reg [55:0] rtc_snapshot = 0;
reg rtc_toggle = 0, rtc_valid = 0;
reg [55:0] rtc_clock = 0;
reg [23:0] rtc_divider = 0;
reg playback = 0;
reg recording = 0;
reg [6:0] music_notes = 0;
reg [1:0] payload_phase = 0;
reg [7:0] event_key, hold_frames, gap_frames;

function automatic [15:0] crc_byte(input [15:0] old_crc, input [7:0] byte_value);
    reg [15:0] value;
    integer i;
    begin
        value = old_crc ^ {byte_value, 8'd0};
        for (i = 0; i < 8; i = i + 1)
            value = value[15] ? (value << 1) ^ 16'h1021 : value << 1;
        crc_byte = value;
    end
endfunction

function automatic valid_key(input [7:0] value);
    begin
        if (value[7]) valid_key = value == 8'h93 || value == 8'h9b;
        else valid_key = value[5:0] < 35 && value[5:0] != 11 &&
                         value[5:0] != 15 && value[5:0] != 19 &&
                         value[5:0] != 23 && value[5:0] != 27 && value[5:0] != 31;
    end
endfunction

function automatic music_note(input [7:0] value);
    begin
        case (value)
            1, 7, 11, 12, 19, 22, 24, 28, 33: music_note = 0;
            default: music_note = value < 36;
        endcase
    end
endfunction

function automatic [7:0] bcd_next(input [7:0] value);
    bcd_next = value[3:0] == 9 ? {value[7:4] + 4'd1, 4'd0} :
                                      {value[7:4], value[3:0] + 4'd1};
endfunction

function automatic [7:0] month_days(input [7:0] month, input [7:0] year);
    reg [6:0] yy;
    begin
        yy = year[7:4] * 7'd10 + year[3:0];
        case (month)
            8'h02: month_days = yy % 4 == 0 ? 8'h29 : 8'h28;
            8'h04, 8'h06, 8'h09, 8'h11: month_days = 8'h30;
            default: month_days = 8'h31;
        endcase
    end
endfunction

function automatic [55:0] rtc_step(input [55:0] old);
    reg [55:0] next_time;
    begin
        next_time = old;
        if (old[7:0] != 8'h59) next_time[7:0] = bcd_next(old[7:0]);
        else begin
            next_time[7:0] = 0;
            if (old[15:8] != 8'h59) next_time[15:8] = bcd_next(old[15:8]);
            else begin
                next_time[15:8] = 0;
                if (old[23:16] != 8'h23) next_time[23:16] = bcd_next(old[23:16]);
                else begin
                    next_time[23:16] = 0;
                    next_time[55:48] = old[55:48] == 6 ? 0 : old[55:48] + 8'd1;
                    if (old[31:24] != month_days(old[39:32], old[47:40]))
                        next_time[31:24] = bcd_next(old[31:24]);
                    else begin
                        next_time[31:24] = 8'h01;
                        if (old[39:32] != 8'h12) next_time[39:32] = bcd_next(old[39:32]);
                        else begin
                            next_time[39:32] = 8'h01;
                            next_time[47:40] = old[47:40] == 8'h99 ? 0 : bcd_next(old[47:40]);
                        end
                    end
                end
            end
        end
        rtc_step = next_time;
    end
endfunction

function automatic [55:0] rtc_plus4(input [55:0] old);
    reg [55:0] next_time;
    begin
        next_time = old;
        if (old[7:0] > 8'h55) begin
            next_time = rtc_step({old[55:8], 8'h59});
            next_time[7:0] = {4'd0, old[3:0] - 4'd6};
        end else if (old[3:0] >= 6)
            next_time[7:0] = {old[7:4] + 4'd1, old[3:0] - 4'd6};
        else next_time[7:0] = {old[7:4], old[3:0] + 4'd4};
        rtc_plus4 = next_time;
    end
endfunction

function automatic [3:0] rtc_digit(input [55:0] time_bcd, input [3:0] index);
    begin
        case (index)
            0: rtc_digit = 2;
            1: rtc_digit = 0;
            2: rtc_digit = time_bcd[47:44];
            3: rtc_digit = time_bcd[43:40];
            4: rtc_digit = time_bcd[39:36];
            5: rtc_digit = time_bcd[35:32];
            6: rtc_digit = time_bcd[31:28];
            7: rtc_digit = time_bcd[27:24];
            8: rtc_digit = 0;
            9: rtc_digit = time_bcd[55:48] == 0 ? 7 : time_bcd[51:48];
            10: rtc_digit = time_bcd[23:20];
            11: rtc_digit = time_bcd[19:16];
            12: rtc_digit = time_bcd[15:12];
            13: rtc_digit = time_bcd[11:8];
            14: rtc_digit = time_bcd[7:4];
            default: rtc_digit = time_bcd[3:0];
        endcase
    end
endfunction

function automatic [5:0] digit_key(input [3:0] digit);
    begin
        case (digit)
            0: digit_key = 34;
            1: digit_key = 33;
            2: digit_key = 30;
            3: digit_key = 26;
            4: digit_key = 29;
            5: digit_key = 25;
            6: digit_key = 21;
            7: digit_key = 24;
            8: digit_key = 20;
            default: digit_key = 16;
        endcase
    end
endfunction

wire rtc_valid_input = rtc[63:56] == 8'h40 && rtc[55:48] <= 6 &&
    rtc[47:44] <= 9 && rtc[43:40] <= 9 &&
    rtc[39:32] >= 8'h01 && rtc[39:32] <= 8'h12 &&
    rtc[31:24] >= 8'h01 && rtc[31:24] <= month_days(rtc[39:32], rtc[47:40]) &&
    rtc[23:16] <= 8'h23 && rtc[15:8] <= 8'h59 && rtc[7:0] <= 8'h59 &&
    rtc[39:36] <= 9 && rtc[35:32] <= 9 &&
    rtc[31:28] <= 9 && rtc[27:24] <= 9 &&
    rtc[23:20] <= 9 && rtc[19:16] <= 9 &&
    rtc[15:12] <= 9 && rtc[11:8] <= 9 &&
    rtc[7:4] <= 9 && rtc[3:0] <= 9;

// MiSTer sends a local-time RTC snapshot when the core starts.
always @(posedge clk) begin
    rtc_toggle <= rtc[64];
    if (rtc[64] != rtc_toggle) begin
        rtc_clock <= rtc[55:0];
        rtc_divider <= 0;
        rtc_valid <= rtc_valid_input;
    end else if (rtc_valid) begin
        if (rtc_divider == RTC_CLOCK_HZ - 1) begin
            rtc_divider <= 0;
            rtc_clock <= rtc_step(rtc_clock);
        end else rtc_divider <= rtc_divider + 1'b1;
    end
end

assign busy = state != IDLE;
assign rtc_time = rtc_clock;
assign rtc_time_valid = rtc_valid;

// read_key covers synchronous ram latency
always @(posedge clk) begin
    if (download && wr && addr >= 8 && addr < 4104)
        memory[addr[11:0] - 12'd8] <= data;
    token <= memory[position];
end

always @(posedge clk) begin
    download_d <= download;
    if (reset) begin
        state <= IDLE;
        error <= 0;
        keys <= 0;
        started <= 0;
        complete <= 0;
        aborted <= 0;
        rtc_active <= 0;
    end else if (download && !download_d) begin
        state <= RECEIVE;
        bad <= wr && (addr != 0 || data != "V");
        received <= wr ? 13'd1 : 13'd0;
        length <= 0;
        expected_crc <= 0;
        crc <= 16'hffff;
        error <= 0;
        keys <= 0;
        started <= 0;
        complete <= 0;
        aborted <= 0;
        timed <= 0;
        payload_phase <= 0;
        rtc_script <= 0;
        rtc_requested <= 0;
        rtc_active <= 0;
        playback <= music_playback;
        recording <= 0;
        music_notes <= 0;
    end else if (busy && ((!timed && state != RECEIVE && !available) ||
                         cancel || (started && !enabled))) begin
        state <= IDLE;
        keys <= 0;
        error <= !timed && !available;
        aborted <= timed || available;
        rtc_active <= 0;
    end else begin
        case (state)
            RECEIVE: begin
                if (!download) begin
                    if (bad || length == 0 || length > 4096 ||
                        {3'd0, received} != length + 16'd8 || crc != expected_crc ||
                        (timed ? payload_phase != 0 : !available) ||
                        (rtc_requested && !rtc_valid)) begin
                        error <= 1;
                        state <= IDLE;
                    end else begin
                        position <= 0;
                        frames <= LINE_FRAMES;
                        state <= WAIT_START;
                    end
                end else if (wr) begin
                    if (addr != {12'd0, received} || received >= 4104) bad <= 1;
                    else begin
                        received <= received + 1'b1;
                        case (received)
                            0: if (data != "V") bad <= 1;
                            1: if (data != "B") bad <= 1;
                            2: if (data != "K") bad <= 1;
                            3: begin
                                timed <= data == "2" || data == "3";
                                rtc_script <= data == "3";
                                if (data != "1" && data != "2" && data != "3") bad <= 1;
                            end
                            4: length[7:0] <= data;
                            5: length[15:8] <= data;
                            6: expected_crc[7:0] <= data;
                            7: expected_crc[15:8] <= data;
                            default: begin
                                crc <= crc_byte(crc, data);
                                if (timed) begin
                                    if (payload_phase == 0 && rtc_script && data == RTC_INSERT)
                                        rtc_requested <= 1;
                                    if ((payload_phase == 0 && data > 35 && data < MODE_LETTERS &&
                                         !(rtc_script && data == RTC_INSERT)) ||
                                        (payload_phase == 1 && data == 0)) bad <= 1;
                                    payload_phase <= payload_phase == 2 ? 2'd0 : payload_phase + 1'b1;
                                end else if (!valid_key(data)) bad <= 1;
                            end
                        endcase
                    end
                end
            end
            WAIT_START: if (enabled && (timed ? frame_tick : input_ready)) begin
                if (timed && frames > 1) frames <= frames - 1'b1;
                else begin
                    started <= 1;
                    shifted <= 0;
                    state <= READ_KEY;
                end
            end
            READ_KEY: state <= SELECT_KEY;
            SELECT_KEY: begin
                if (timed) begin
                    event_key <= token;
                    position <= position + 1'b1;
                    state <= READ_HOLD;
                end else if (input_ready && !token[7] && token[6] != symbols) begin
                    if (shifted) begin
                        error <= 1;
                        state <= IDLE;
                    end else begin
                        keys <= 36'd1 << 11;
                        shifting <= 1;
                        shifted <= 1;
                        state <= HOLD_KEY;
                    end
                end else if (input_ready) begin
                    keys <= 36'd1 << token[5:0];
                    shifting <= 0;
                    state <= HOLD_KEY;
                end
            end
            READ_HOLD: state <= SELECT_HOLD;
            SELECT_HOLD: begin
                hold_frames <= token;
                position <= position + 1'b1;
                state <= READ_GAP;
            end
            READ_GAP: state <= SELECT_GAP;
            SELECT_GAP: begin
                gap_frames <= token;
                shifting <= 0;
                if (recording && music_notes == 79 && event_key != 11 && event_key != MODE_SYMBOLS) begin
                    // skip to closing shift/no-record
                    keys <= 0;
                    frames <= 0;
                    state <= RELEASE_KEY;
                end else if (event_key == RTC_INSERT && rtc_script) begin
                    if (!rtc_valid) begin
                        keys <= 0;
                        error <= 1;
                        state <= IDLE;
                    end else begin
                        // 16 digits at 8/8 fields take about 4.3 seconds.
                        rtc_snapshot <= rtc_plus4(rtc_clock);
                        rtc_index <= 0;
                        rtc_hold <= hold_frames;
                        rtc_gap <= token;
                        rtc_active <= 1;
                        state <= RTC_DIGIT;
                    end
                end else if ((event_key >= MUSIC_LOW && event_key <= MUSIC_HIGH) ||
                             (music_available && !symbols &&
                              (event_key == 33 || event_key == 19 || event_key == 22))) begin
                    // Physical bank keys retain their full encoded score interval.
                    bank_gap <= event_key <= MUSIC_HIGH && event_key >= MUSIC_LOW ?
                                {1'b0, token} : {1'b0, hold_frames} + {1'b0, token};
                    frames <= 255;
                    state <= BANK_READY;
                end else begin
                    case (event_key)
                        MODE_LETTERS, MODE_SYMBOLS: begin
                            keys <= symbols == event_key[0] ? 36'd0 : 36'd1 << 11;
                            shifting <= symbols != event_key[0];
                        end
                        MUSIC_REPLAY: keys <= playback ? 36'd0 : 36'd1 << 12;
                        MUSIC_RECORD: begin
                            keys <= 36'd1 << (playback ? 6'd7 : 6'd33);
                            recording <= !playback;
                            music_notes <= 0;
                        end
                        8'hff: keys <= 0;
                        default: keys <= 36'd1 << event_key[5:0];
                    endcase
                    if (recording && music_note(event_key)) music_notes <= music_notes + 1'b1;
                    if ((event_key == 11 || event_key == MODE_SYMBOLS) && music_notes != 0) recording <= 0;
                    frames <= hold_frames;
                    state <= HOLD_KEY;
                end
            end
            RTC_DIGIT: begin
                keys <= 36'd1 << digit_key(rtc_digit(rtc_snapshot, rtc_index));
                frames <= rtc_hold;
                gap_frames <= rtc_gap;
                shifting <= 0;
                state <= HOLD_KEY;
            end
            BANK_READY, BANK_HOLD, BANK_RELEASE: begin
                if (frame_tick && bank_gap != 0) bank_gap <= bank_gap - 1'b1;
                if (state == BANK_READY && input_ready) begin
                    case (event_key)
                        MUSIC_LOW, 33: keys <= 36'd1 << 33;
                        MUSIC_MIDDLE, 19: keys <= 36'd1 << 19;
                        MUSIC_HIGH, 22: keys <= 36'd1 << 22;
                        default: keys <= 0;
                    endcase
                    frames <= 255;
                    state <= BANK_HOLD;
                end else if (state == BANK_HOLD && key_accepted) begin
                    keys <= 0;
                    frames <= 255;
                    state <= BANK_RELEASE;
                end else if (state == BANK_RELEASE && input_ready) begin
                    if (bank_gap == 0 || (frame_tick && bank_gap == 1)) begin
                        frames <= 0;
                        state <= RELEASE_KEY;
                    end else frames <= 255;
                end else if (frame_tick) begin
                    if (frames > 1) frames <= frames - 1'b1;
                    else begin
                        keys <= 0;
                        error <= 1;
                        state <= IDLE;
                    end
                end
            end
            HOLD_KEY: if (!timed && key_accepted) begin
                keys <= 0;
                if (shifting) state <= SELECT_KEY;
                else if ({4'd0, position} + 16'd1 == length) begin
                    if (auto_repeat && !rtc_script) begin
                        position <= 0;
                        shifted <= 0;
                        state <= READ_KEY;
                    end else begin
                        complete <= 1;
                        state <= IDLE;
                    end
                end else begin
                    position <= position + 1'b1;
                    shifted <= 0;
                    state <= READ_KEY;
                end
            end else if (timed && frame_tick) begin
                if (frames > 1) frames <= frames - 1'b1;
                else if (shifting && symbols != event_key[0]) begin
                    frames <= 255;
                    state <= SHIFT_WAIT;
                end else begin
                    keys <= 0;
                    frames <= gap_frames;
                    state <= RELEASE_KEY;
                end
            end
            SHIFT_WAIT: begin
                if (symbols == event_key[0]) begin
                    keys <= 0;
                    frames <= gap_frames;
                    state <= RELEASE_KEY;
                end else if (frame_tick) begin
                    if (frames > 1) frames <= frames - 1'b1;
                    else begin
                        keys <= 0;
                        error <= 1;
                        state <= IDLE;
                    end
                end
            end
            RELEASE_KEY: if (frame_tick || (timed && frames == 0)) begin
                if (frames > 1) frames <= frames - 1'b1;
                else if (rtc_active && rtc_index != 15) begin
                    rtc_index <= rtc_index + 1'b1;
                    state <= RTC_DIGIT;
                end else if ({4'd0, position} + 16'd1 == length) begin
                    if (auto_repeat && !rtc_script) begin
                        position <= 0;
                        shifted <= 0;
                        state <= READ_KEY;
                    end else begin
                        complete <= 1;
                        state <= IDLE;
                    end
                end
                else begin
                    rtc_active <= 0;
                    position <= position + 1'b1;
                    shifted <= 0;
                    state <= READ_KEY;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
