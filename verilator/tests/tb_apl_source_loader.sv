`timescale 1ns/1ps
module tb_apl_source_loader;
reg clk = 0;
always #5 clk = ~clk;
reg reset = 1, frame_tick = 0, download = 0, wr = 0;
reg [24:0] addr = 0;
reg [7:0] data = 0;
reg available = 1, symbols = 0, enabled = 0, cancel = 0;
reg input_ready = 0, key_accepted = 0;
reg emulate_input = 1;
integer input_cycles = 0;
reg music_playback = 0, auto_repeat = 0;
reg music_available = 0;
reg [64:0] rtc = 0;
wire [55:0] rtc_time;
wire rtc_time_valid;
wire busy, error, complete, started, aborted;
wire [35:0] keys;
apl_source_loader #(.LINE_FRAMES(3)) dut (.*);
reg [7:0] packet [0:4103];
reg [35:0] previous = 0;
reg emulate_shift = 1;
integer presses = 0;
reg [5:0] observed [0:8191];
integer held_cycles [0:8191];
integer field_count = 0;
integer press_field [0:8191];
integer release_field [0:8191];

always @(negedge clk) begin
    if (emulate_input) key_accepted = 0;
    if (emulate_input && !dut.timed) begin
        if (keys != 0 && input_ready) begin
            input_cycles = input_cycles + 1;
            if (input_cycles == 5) begin
                input_ready = 0;
                key_accepted = 1;
                input_cycles = 0;
            end
        end else if (keys == 0 && !input_ready) begin
            input_cycles = input_cycles + 1;
            if (input_cycles == 7) begin
                input_ready = 1;
                input_cycles = 0;
            end
        end
    end
    if (frame_tick) field_count = field_count + 1;
    if (keys != 0 && previous == 0) begin
        if ((keys & (keys - 1)) != 0) $fatal(1, "Multiple playback keys");
        for (integer i = 0; i < 36; i = i + 1)
            if (keys[i]) observed[presses] = 6'(i);
        presses = presses + 1;
        held_cycles[presses - 1] = 0;
        press_field[presses - 1] = field_count;
        if (keys[11] && emulate_shift) symbols = !symbols;
    end
    if (keys == 0 && previous != 0) release_field[presses - 1] = field_count;
    if (keys != 0) held_cycles[presses - 1] = held_cycles[presses - 1] + 1;
    previous = keys;
end

task tick;
    @(posedge clk); #1;
endtask

task init_packet(input integer count);
    reg [15:0] checksum;
    checksum = 16'hffff;
    packet[0] = "V"; packet[1] = "B"; packet[2] = "K"; packet[3] = "1";
    packet[4] = 8'(count); packet[5] = 8'(count >> 8);
    for (integer n = 0; n < count; n = n + 1) begin
        checksum = checksum ^ {packet[n + 8], 8'd0};
        for (integer j = 0; j < 8; j = j + 1)
            checksum = checksum[15] ? (checksum << 1) ^ 16'h1021 : checksum << 1;
    end
    packet[6] = checksum[7:0]; packet[7] = checksum[15:8];
endtask

task send_packet(input integer count, input integer wrong_addr);
    download = 1;
    for (integer n = 0; n < count; n = n + 1) begin
        wr = 1; addr = n == wrong_addr ? 25'(n + 1) : 25'(n); data = packet[n];
        tick;
        if (keys != 0 || started) $fatal(1, "Started before validation");
    end
    download = 0; wr = 0; tick; tick;
    if (aborted) $fatal(1, "Download retained aborted status");
endtask

task finish_entry;
    for (integer i = 0; i < 100000 && busy; i = i + 1) tick;
    if (busy || keys != 0) $fatal(1, "Playback failed to release");
endtask

task check_handshake;
    emulate_input = 0; input_ready = 0; symbols = 0; presses = 0;
    emulate_shift = 0;
    frame_tick = 1;
    packet[8] = 0; packet[9] = 0; packet[10] = 8'h9b; packet[11] = 8'h61;
    init_packet(4); send_packet(12, -1);
    repeat (200) tick;
    if (keys != 0 || !busy || started) $fatal(1, "Started before input ready");
    input_ready = 1;
    repeat (6) tick;
    if (keys != 1 || presses != 1 || !started) $fatal(1, "Ready did not start entry");
    repeat (200) tick;
    if (keys != 1 || presses != 1) $fatal(1, "Released before acceptance");
    for (integer n = 0; n < 5; n = n + 1) begin
        input_ready = 0; key_accepted = 1; tick; key_accepted = 0;
        if (keys != 0) $fatal(1, "Accepted key not released");
        if (n == 4) begin
            if (!complete || busy) $fatal(1, "Final key not acknowledged");
        end else begin
            // includes an arbitrarily long post-next pause before shift
            repeat (300) tick;
            if (keys != 0 || presses != n + 1 || !busy)
                $fatal(1, "Typed while APL was busy");
            if (n == 3) symbols = 1;
            input_ready = 1;
            frame_tick = 0;
            repeat (6) tick;
            if (presses != n + 2 || keys == 0)
                $fatal(1, "Did not resume on readiness");
            frame_tick = 1;
        end
    end
    if (observed[0] != 0 || observed[1] != 0 || observed[2] != 27 ||
        observed[3] != 11 || observed[4] != 33 || error)
        $fatal(1, "Handshake key order mismatch");
    emulate_input = 1; emulate_shift = 1; input_ready = 0; input_cycles = 0;
endtask

task check_arccosine;
    integer file_handle, count, expected, mode;
    file_handle = $fopen("../examples/apl-s-manual-chapter-6/11-arccosine.vbk", "rb");
    if (!file_handle) $fatal(1, "Cannot open Arccosine VBK");
    count = $fread(packet, file_handle);
    $fclose(file_handle);
    if (count != 296 || {packet[5], packet[4]} != 288)
        $fatal(1, "Unexpected Arccosine VBK size");
    symbols = 0; presses = 0;
    send_packet(count, -1); finish_entry;
    if (error || !complete) $fatal(1, "Arccosine entry stopped at payload byte %0d", dut.position);
    expected = 0; mode = 0;
    for (integer n = 8; n < count; n = n + 1) begin
        if (!packet[n][7] && packet[n][6] != mode) begin
            if (expected >= presses || observed[expected] != 11)
                $fatal(1, "Arccosine lost SHIFT at payload byte %0d", n - 8);
            expected = expected + 1;
            mode = packet[n][6];
        end
        if (expected >= presses || observed[expected] != packet[n][5:0])
            $fatal(1, "Arccosine key mismatch at payload byte %0d", n - 8);
        expected = expected + 1;
    end
    if (presses != expected) $fatal(1, "Arccosine emitted extra keys");
    $display("Arccosine VBK: all 288 tokens emitted through final NEXT");
endtask

task check_bank_ready(input bit raw_keys);
    emulate_input = 0; input_ready = 0; key_accepted = 0;
    music_available = raw_keys; symbols = 0;
    presses = 0; frame_tick = 1;
    for (integer bank = 0; bank < 3; bank = bank + 1) begin
        packet[8 + bank * 3] = raw_keys ? (bank == 0 ? 33 : bank == 1 ? 19 : 22) : 8'hfa + 8'(bank);
        packet[9 + bank * 3] = 1; packet[10 + bank * 3] = 0;
    end
    packet[17] = 29; packet[18] = 5; packet[19] = 2;
    init_packet(12); packet[3] = "2";
    send_packet(20, -1);
    for (integer bank = 0; bank < 3; bank = bank + 1) begin
        repeat (20) tick;
        if (keys != 0 || presses != bank || !busy)
            $fatal(1, "Bank pressed before readiness");
        input_ready = 1;
        repeat (20) tick;
        if (keys != (36'd1 << (bank == 0 ? 33 : bank == 1 ? 19 : 22)))
            $fatal(1, "Bank released without acknowledgment");
        input_ready = 0; key_accepted = 1; tick; key_accepted = 0;
        repeat (20) tick;
        if (keys != 0 || presses != bank + 1 || !busy)
            $fatal(1, "Bank advanced before release readiness");
        input_ready = 1;
        frame_tick = 0;
        repeat (2) tick;
        input_ready = 0;
        repeat (15) tick;
        if (bank != 2) frame_tick = 1;
    end
    if (keys != (36'd1 << 29)) $fatal(1, "Timed note did not follow banks");
    for (integer field = 0; field < 5; field = field + 1) begin
        frame_tick = 1; tick; frame_tick = 0; tick;
        if ((keys != 0) != (field < 4)) $fatal(1, "Bank changed note hold duration");
    end
    frame_tick = 1;
    finish_entry;
    if (error || !complete || presses != 4 || observed[3] != 29)
        $fatal(1, "Acknowledged banks lost the following timed note");

    init_packet(3); packet[3] = "2"; input_ready = 0;
    send_packet(11, -1); finish_entry;
    if (!error || complete) $fatal(1, "Missing bank readiness ignored");
    input_ready = 1;
    send_packet(11, -1);
    while (keys == 0) tick;
    input_ready = 0;
    finish_entry;
    if (!error || complete) $fatal(1, "Missing bank acceptance ignored");
    input_ready = 1;
    send_packet(11, -1);
    while (keys == 0) tick;
    input_ready = 0; key_accepted = 1; tick; key_accepted = 0;
    finish_entry;
    if (!error || complete) $fatal(1, "Missing bank release ignored");
    input_ready = 1;
    send_packet(11, -1);
    while (keys == 0) tick;
    cancel = 1; tick; cancel = 0;
    if (busy || keys != 0 || complete) $fatal(1, "Bank cancel failed");
    emulate_input = 1; input_ready = 0; music_available = 0;
endtask

task check_bank_gap(input bit late_release, input bit raw_keys,
                    input [7:0] held = 2, input [7:0] gap = 2);
    integer interval_fields;
    interval_fields = raw_keys ? int'(held) + int'(gap) : int'(gap);
    emulate_input = 0; input_ready = 1; key_accepted = 0;
    music_available = raw_keys; symbols = 0;
    presses = 0; frame_tick = 0;
    packet[8] = 29; packet[9] = 2; packet[10] = 0;
    packet[11] = raw_keys ? 33 : 8'hfa; packet[12] = held; packet[13] = gap;
    packet[14] = 30; packet[15] = 2; packet[16] = 2;
    init_packet(9); packet[3] = "2";
    send_packet(17, -1);
    frame_tick = 1;
    while (!started) tick;
    frame_tick = 0;
    repeat (20) tick;
    if (keys != (36'd1 << 29)) $fatal(1, "Initial overlap note missing");
    repeat (2) begin frame_tick = 1; tick; frame_tick = 0; tick; end
    repeat (20) tick;
    if (keys != (36'd1 << 33)) $fatal(1, "Octave did not start inside note gap");
    input_ready = 0; key_accepted = 1; tick; key_accepted = 0;
    if (!late_release) input_ready = 1;
    repeat (20) tick;
    if (keys != 0) $fatal(1, "Octave overlap shortened score gap");
    for (integer field = 1; field <= interval_fields; field = field + 1) begin
        frame_tick = 1; tick; frame_tick = 0; tick;
        repeat (20) tick;
        if (field < interval_fields && keys != 0)
            $fatal(1, "Octave switch shortened encoded score interval");
    end
    if (late_release) begin
        if (keys != 0) $fatal(1, "Score deadline bypassed ROM readiness");
        repeat (3) begin frame_tick = 1; tick; frame_tick = 0; tick; end
        input_ready = 1;
        repeat (20) tick;
    end
    if (keys != (36'd1 << 30)) $fatal(1, "Ready note missed score deadline");
    if (press_field[2] - press_field[0] != 2 + interval_fields + (late_release ? 3 : 0))
        $fatal(1, "Octave switch changed score onset spacing");
    frame_tick = 1; finish_entry;
    if (error || !complete || presses != 3) $fatal(1, "Octave overlap lost a key");
    emulate_input = 1; input_ready = 0; music_available = 0;
endtask

task check_shifted_bank_keys;
    music_available = 1; symbols = 1; presses = 0;
    input_ready = 0; key_accepted = 0; frame_tick = 1;
    packet[8] = 33; packet[11] = 19; packet[14] = 22;
    for (integer n = 8; n < 17; n = n + 3) begin
        packet[n + 1] = 2; packet[n + 2] = 2;
    end
    init_packet(9); packet[3] = "2";
    send_packet(17, -1); finish_entry;
    if (error || !complete || presses != 3 || observed[0] != 33 ||
        observed[1] != 19 || observed[2] != 22)
        $fatal(1, "Shifted music commands used bank handshake");
    music_available = 0; symbols = 0;
endtask

task check_modes(input bit initial_mode);
    symbols = initial_mode; presses = 0;
    packet[8] = 8'hf9; packet[11] = 19;
    packet[14] = 8'hf8; packet[17] = 29;
    packet[20] = 8'hf9; packet[23] = 7; packet[26] = 8'hf8;
    for (integer n = 8; n < 29; n = n + 3) begin
        packet[n + 1] = 8; packet[n + 2] = 8;
    end
    init_packet(21); packet[3] = "2";
    send_packet(29, -1); finish_entry;
    if (error || !complete || symbols || presses != (initial_mode ? 6 : 7))
        $fatal(1, "Explicit music modes failed from mode %0d", initial_mode);
    if (observed[presses - 1] != 11 || observed[presses - 2] != 7)
        $fatal(1, "Song did not restore lower mode");
    presses = 0; auto_repeat = 1;
    send_packet(29, -1);
    for (integer i = 0; i < 2000 && presses < 14; i = i + 1) tick;
    auto_repeat = 0; finish_entry;
    if (error || !complete || symbols || presses != 14)
        $fatal(1, "Repeated song lost SHIFT synchronization");

    emulate_shift = 0; symbols = 0; presses = 0;
    init_packet(3); packet[3] = "2";
    send_packet(11, -1);
    repeat (40) tick;
    if (keys != (36'd1 << 11) || !busy || error)
        $fatal(1, "SHIFT released before delayed acknowledgement");
    symbols = 1; finish_entry;
    if (error || !complete || presses != 1)
        $fatal(1, "Delayed SHIFT acknowledgement failed");
    symbols = 0; presses = 0;
    send_packet(11, -1); finish_entry;
    if (!error || complete || presses != 1)
        $fatal(1, "Missing timed SHIFT acknowledgement ignored");
    emulate_shift = 1;
endtask

task check_music_limit(input integer notes, input bit playback_mode, input bit repeat_song,
                       input bit explicit_modes);
    integer offset, entered, expected;
    symbols = 0;
    packet[8] = explicit_modes ? 8'hf9 : 11; packet[11] = 19; packet[14] = 8'hfe;
    packet[17] = explicit_modes ? 8'hf8 : 11; packet[20] = 19;
    offset = 23;
    for (integer n = 0; n < notes; n = n + 1) begin
        packet[offset] = 255; packet[offset + 3] = 22; packet[offset + 6] = 29;
        offset = offset + 9;
    end
    packet[offset] = explicit_modes ? 8'hf9 : 11; packet[offset + 3] = 7;
    packet[offset + 6] = explicit_modes ? 8'hf8 : 11; packet[offset + 9] = 8'hfd;
    offset = offset + 12;
    for (integer n = 8; n < offset; n = n + 3) begin
        packet[n + 1] = 2; packet[n + 2] = 1;
    end
    init_packet(offset - 8); packet[3] = "2";
    entered = !playback_mode && notes > 79 ? 79 : notes;
    expected = 5 + entered * 2 + (playback_mode ? 3 : 4);
    music_playback = playback_mode; auto_repeat = repeat_song; presses = 0;
    send_packet(offset, -1);
    if (repeat_song) begin
        for (integer i = 0; i < 10000 && presses < expected * 2; i = i + 1) tick;
        if (!busy || error || complete || presses != expected * 2)
            $fatal(1, "Music cutoff repeat failed");
        cancel = 1; tick; cancel = 0;
    end else begin
        finish_entry;
        if (error || !complete || presses != expected)
            $fatal(1, "Music cutoff failed: notes=%0d playback=%0d presses=%0d expected=%0d",
                   notes, playback_mode, presses, expected);
    end
    for (integer pass = 0; pass < (repeat_song ? 2 : 1); pass = pass + 1) begin
        offset = pass * expected;
        if (observed[offset + 2] != (playback_mode ? 7 : 33))
            $fatal(1, "Music recording selector failed");
        for (integer n = 0; n < entered; n = n + 1)
            if (observed[offset + 5 + n * 2] != 22 || observed[offset + 6 + n * 2] != 29)
                $fatal(1, "Music note/bank order failed");
        offset = offset + 5 + entered * 2;
        if (observed[offset] != 11 || observed[offset + 1] != 7 || observed[offset + 2] != 11 ||
            (!playback_mode && observed[offset + 3] != 12))
            $fatal(1, "Music closing controls lost at cutoff");
    end
    if (symbols) $fatal(1, "Music cutoff left SHIFT active");
    auto_repeat = 0; music_playback = 0;
endtask

task check_rtc_clock;
    integer fh, count;
    reg [8*16-1:0] digits;
    reg [5:0] digit_keys[0:9];
    digit_keys[0] = 34; digit_keys[1] = 33; digit_keys[2] = 30;
    digit_keys[3] = 26; digit_keys[4] = 29; digit_keys[5] = 25;
    digit_keys[6] = 21; digit_keys[7] = 24; digit_keys[8] = 20;
    digit_keys[9] = 16;
    emulate_input = 1; emulate_shift = 1;
    music_available = 0; auto_repeat = 0; available = 0;
    frame_tick = 1; enabled = 1; symbols = 0; presses = 0;

    packet[8] = 8'hf7; packet[9] = 8'd8; packet[10] = 8'd8;
    init_packet(3); packet[3] = "2";
    send_packet(11, -1);
    if (!error || busy || presses != 0) $fatal(1, "VBK2 accepted RTC control");
    packet[3] = "3";
    send_packet(11, -1); finish_entry;
    if (!error || complete || presses != 0) $fatal(1, "Missing RTC not rejected");

    // Friday October 30, 2026 23:59:58; entry lead crosses midnight.
    rtc = {1'b1, 8'h40, 8'h05, 8'h26, 8'h10, 8'h30, 8'h23, 8'h59, 8'h58};
    tick; tick;
    if (!dut.rtc_valid) $fatal(1, "RTC snapshot not latched");
    fh = $fopen("../examples/clock-from-rtc.vbk", "rb");
    if (!fh) $fatal(1, "Cannot open RTC example");
    count = $fread(packet, fh);
    $fclose(fh);
    if (count != 29 || packet[3] != "3") $fatal(1, "Bad RTC example");
    presses = 0; symbols = 0;
    send_packet(count, -1); finish_entry;
    if (!complete || error || presses != 22)
        $fatal(1, "RTC script failed, presses %0d error %0b", presses, error);
    if (observed[0] != 11 || observed[1] != 27 || observed[2] != 11 ||
        observed[3] != 29 || observed[4] != 11 || observed[21] != 17)
        $fatal(1, "RTC setup and start keys mismatch");
    digits = "2026103106000002";
    for (integer i = 0; i < 16; i = i + 1)
        if (observed[5+i] != digit_keys[digits[(15-i)*8 +:8] - "0"])
            $fatal(1, "RTC digit %0d mismatch", i);
    $display("RTC VBK3: setup, midnight rollover, 16 digits and start verified");
    available = 1;
endtask

initial begin
    tick; reset = 0; tick;
    enabled = 1;
    check_handshake;
    enabled = 0; presses = 0; symbols = 0;
    packet[8] = 8'h61; packet[9] = 8'h56; packet[10] = 8'h61; packet[11] = 8'h9b;
    packet[12] = 8'h5e; packet[13] = 8'h56; packet[14] = 8'h5a; packet[15] = 8'h9b;
    init_packet(8);
    send_packet(16, -1);
    repeat (5) tick;
    if (!busy || error || presses != 0) $fatal(1, "OSD wait failed");
    enabled = 1; frame_tick = 1;
    finish_entry;
    if (error || !complete || presses != 9 || observed[0] != 11 || observed[1] != 33 ||
        observed[2] != 22 || observed[3] != 33 || observed[4] != 27 ||
        observed[5] != 30 || observed[6] != 22 || observed[7] != 26 || observed[8] != 27)
        $fatal(1, "Arithmetic key sequence mismatch");

    presses = 0;
    send_packet(16, -1); finish_entry;
    if (error || presses != 8 || observed[0] != 33) $fatal(1, "Live mode mismatch");

    packet[8] = 0; // letter i requires a transition back to letters
    init_packet(4); presses = 0;
    send_packet(12, -1); finish_entry;
    if (error || observed[0] != 11 || observed[1] != 0) $fatal(1, "Letter mode mismatch");

    presses = 0; packet[6] = packet[6] ^ 1;
    send_packet(12, -1);
    if (!error || busy || presses != 0) $fatal(1, "Bad CRC accepted");
    init_packet(4); send_packet(11, -1);
    if (!error || busy || presses != 0) $fatal(1, "Truncated stream accepted");
    send_packet(12, 9);
    if (!error || busy || presses != 0) $fatal(1, "Wrong address accepted");
    packet[0] = "X"; send_packet(12, -1);
    if (!error || busy || presses != 0) $fatal(1, "Bad magic accepted");
    init_packet(4); packet[4] = 0; packet[5] = 0; send_packet(12, -1);
    if (!error || busy || presses != 0) $fatal(1, "Zero length accepted");
    init_packet(4); packet[4] = 1; packet[5] = 16; send_packet(12, -1);
    if (!error || busy || presses != 0) $fatal(1, "Oversize length accepted");
    packet[8] = 11; init_packet(4); send_packet(12, -1);
    if (!error || busy || presses != 0) $fatal(1, "Raw SHIFT accepted");

    packet[8] = 8'h61; init_packet(4);
    available = 0; send_packet(12, -1);
    if (!error || busy || presses != 0) $fatal(1, "Wrong cartridge accepted");
    available = 1;

    send_packet(12, -1);
    while (keys == 0) tick;
    cancel = 1; tick; cancel = 0;
    if (busy || keys != 0 || complete || !aborted || error)
        $fatal(1, "Cancel left a key held or reported completion");
    send_packet(12, -1);
    while (keys == 0) tick;
    enabled = 0; tick;
    if (busy || keys != 0 || !aborted || error || complete) $fatal(1, "OSD cancel failed");
    enabled = 1;

    symbols = 0; emulate_shift = 0;
    send_packet(12, -1); finish_entry;
    if (!error) $fatal(1, "Missing SHIFT acknowledgement ignored");
    emulate_shift = 1;

    for (integer n = 8; n < 4104; n = n + 1) packet[n] = 0;
    packet[4103] = 8'h9b;
    init_packet(4096); send_packet(4104, -1); finish_entry;
    if (error) $fatal(1, "Maximum stream failed");

    available = 0; presses = 0;
    packet[8] = 11; packet[9] = 3; packet[10] = 2;
    packet[11] = 35; packet[12] = 5; packet[13] = 4;
    packet[14] = 255; packet[15] = 7; packet[16] = 0;
    packet[17] = 27; packet[18] = 2; packet[19] = 0;
    init_packet(12); packet[3] = "2";
    send_packet(20, -1); finish_entry;
    if (error || !complete || presses != 3 || observed[0] != 11 ||
        observed[1] != 35 || observed[2] != 27 || held_cycles[0] != 3 ||
        held_cycles[1] != 5 || held_cycles[2] != 2)
        $fatal(1, "Timed event sequence or hold duration mismatch");

    // space field ticks apart to check release gaps and a silent wait
    presses = 0; frame_tick = 0;
    send_packet(20, -1);
    for (integer i = 0; i < 50 && busy; i = i + 1) begin
        repeat (20) tick;
        frame_tick = 1; tick;
        frame_tick = 0; tick;
    end
    if (busy || error || presses != 3 || press_field[1] - press_field[0] != 5 ||
        press_field[2] - press_field[1] != 16)
        $fatal(1, "Timed release gap or silent wait mismatch");
    frame_tick = 1;

    presses = 0; packet[9] = 0;
    init_packet(12); packet[3] = "2"; send_packet(20, -1);
    if (!error || busy || presses != 0) $fatal(1, "Zero hold accepted");
    packet[9] = 3; packet[8] = 36;
    init_packet(12); packet[3] = "2"; send_packet(20, -1);
    if (!error || busy || presses != 0) $fatal(1, "Invalid physical key accepted");
    packet[8] = 11;
    init_packet(11); packet[3] = "2"; send_packet(19, -1);
    if (!error || busy || presses != 0) $fatal(1, "Partial timed event accepted");
    init_packet(12); packet[3] = "2";
    send_packet(20, -1);
    while (keys == 0) tick;
    cancel = 1; tick; cancel = 0;
    if (busy || keys != 0 || complete) $fatal(1, "Timed cancel failed");

    presses = 0;
    for (integer n = 8; n < 4103; n = n + 3) begin
        packet[n] = 35; packet[n + 1] = 1; packet[n + 2] = 0;
    end
    init_packet(4095); packet[3] = "2";
    send_packet(4103, -1); finish_entry;
    if (error || !complete || presses != 1365) $fatal(1, "Maximum timed stream failed");
    packet[8] = 8'hfe; packet[9] = 3; packet[10] = 2;
    packet[11] = 29; packet[12] = 5; packet[13] = 4;
    packet[14] = 8'hfd; packet[15] = 7; packet[16] = 0;
    init_packet(9); packet[3] = "2";
    presses = 0;
    send_packet(17, -1); finish_entry;
    if (error || !complete || presses != 3 || observed[0] != 33 ||
        observed[1] != 29 || observed[2] != 12)
        $fatal(1, "Record controls failed");
    music_playback = 1; presses = 0;
    send_packet(17, -1);
    music_playback = 0; // mode is latched for the whole file
    finish_entry;
    if (error || !complete || presses != 2 || observed[0] != 7 || observed[1] != 29)
        $fatal(1, "Playback controls failed");

    music_playback = 1; auto_repeat = 1; presses = 0;
    frame_tick = 0;
    send_packet(17, -1);
    for (integer i = 0; i < 100 && presses < 6; i = i + 1) begin
        repeat (20) tick;
        frame_tick = 1; tick;
        frame_tick = 0; tick;
    end
    if (!busy || error || complete || presses != 6)
        $fatal(1, "Timed repeat failed");
    for (integer i = 0; i < 6; i = i + 1)
        if (observed[i] != (i % 2 == 0 ? 7 : 29)) $fatal(1, "Repeat order failed");
    for (integer i = 2; i < 6; i = i + 1)
        if (press_field[i] - press_field[i - 2] != 21) $fatal(1, "Repeat timing failed");
    cancel = 1; tick; cancel = 0;
    if (busy || keys != 0 || complete) $fatal(1, "Repeat cancel failed");
    repeat (40) tick;
    if (busy || presses != 6) $fatal(1, "Repeat restarted after cancel");

    frame_tick = 1;
    presses = 0; send_packet(17, -1);
    for (integer i = 0; i < 500 && presses < 3; i = i + 1) tick;
    enabled = 0; tick;
    if (busy || keys != 0 || complete) $fatal(1, "Repeat OSD cancel failed");
    enabled = 1; auto_repeat = 0; music_playback = 0;

    for (integer raw_keys = 0; raw_keys < 2; raw_keys = raw_keys + 1) begin
        check_bank_ready(1'(raw_keys));
        check_bank_gap(0, 1'(raw_keys));
        check_bank_gap(1, 1'(raw_keys));
    end
    check_bank_gap(0, 1, 255, 255);
    check_bank_gap(0, 1, 2, 0);
    check_bank_gap(0, 0, 255, 2);
    check_shifted_bank_keys;
    check_modes(0);
    check_modes(1);
    for (integer explicit_modes = 0; explicit_modes < 2; explicit_modes = explicit_modes + 1) begin
        check_music_limit(78, 0, 0, 1'(explicit_modes));
        check_music_limit(79, 0, 0, 1'(explicit_modes));
        check_music_limit(80, 0, 0, 1'(explicit_modes));
        check_music_limit(90, 0, 1, 1'(explicit_modes));
        check_music_limit(90, 1, 0, 1'(explicit_modes));
    end

    available = 1;
    for (integer line_end = 0; line_end < 2; line_end = line_end + 1) begin
        packet[8] = line_end != 0 ? 8'h9b : 0;
        init_packet(1); presses = 0; auto_repeat = 1;
        send_packet(9, -1);
        for (integer i = 0; i < 500 && presses < 3; i = i + 1) tick;
        if (!busy || error || complete || presses != 3) $fatal(1, "VBK1 repeat failed");
        auto_repeat = 0; finish_entry;
        if (!complete || error) $fatal(1, "Repeat disable failed");
    end

    check_arccosine;
    check_rtc_clock;
    $display("APL source loader tests passed");
    $finish;
end
initial begin
    #5000000; $fatal(1, "Test timed out");
end
endmodule
