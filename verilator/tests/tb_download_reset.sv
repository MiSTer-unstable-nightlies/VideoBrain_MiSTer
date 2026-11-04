`timescale 1ns/1ps
module tb_download_reset;
reg clk = 0;
always #5 clk = ~clk;
reg external_reset = 0, download = 0, check_no_reset = 0;
reg [15:0] index = 4;
reg [127:0] status = 0;
reg [1:0] buttons = 0;
reg pll_locked = 1, osd_status = 0, vblank = 1;
reg [10:0] ps2_key = 0;

emu dut (.RESET(external_reset));

task field_edge;
    vblank = 1;
    repeat (2) @(posedge clk);
    #1;
    vblank = 0;
    repeat (2) @(posedge clk);
    #1;
endtask

task key_event(input [8:0] code, input pressed, input [35:0] expected);
    ps2_key = {!ps2_key[10], pressed, code};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.kbd_matrix !== expected)
        $fatal(1, "Keyboard code %h pressed %b: got %h expected %h",
               code, pressed, dut.kbd_matrix, expected);
endtask

task edit_alias(input [8:0] alias_code, original_code, input integer bit_index);
    reg [35:0] expected;
    expected = 36'd1 << bit_index;
    key_event(alias_code, 1, expected);
    key_event(alias_code, 1, expected); // typematic repeat
    key_event(alias_code, 0, 0);
    key_event(alias_code, 1, expected);
    key_event(original_code, 1, expected);
    key_event(alias_code, 0, expected);
    key_event(original_code, 0, 0);
    key_event(original_code, 1, expected);
    key_event(alias_code, 1, expected);
    key_event(original_code, 0, expected);
    key_event(alias_code, 0, 0);
endtask

task number_alias(input [8:0] row_code, pad_code, original_code, input integer bit_index);
    reg [35:0] expected;
    expected = 36'd1 << bit_index;
    key_event(row_code, 1, expected);
    key_event(row_code, 1, expected); // typematic repeat
    key_event(row_code, 0, 0);
    key_event(pad_code, 1, expected);
    key_event(pad_code, 0, 0);
    key_event(original_code, 1, expected);
    key_event(row_code, 1, expected);
    key_event(pad_code, 1, expected);
    key_event(original_code, 0, expected);
    key_event(row_code, 0, expected);
    key_event(pad_code, 0, 0);
    key_event(row_code, 1, expected);
    key_event(original_code, 1, expected);
    key_event(row_code, 0, expected);
    key_event(original_code, 0, 0);
    key_event(pad_code | 9'h100, 1,
              pad_code == 9'h06c ? 36'd1 << 31 : pad_code == 9'h069 ? 36'd1 << 23 : 0);
    key_event(pad_code | 9'h100, 0, 0);
endtask

always @(posedge dut.reset)
    if (check_no_reset) $fatal(1, "Keyboard download pulsed reset");

task keyboard_download(input [15:0] file_index);
    index = file_index;
    #1;
    // model source_dl arriving after the raw download signal
    force dut.source_dl = 1'b0;
    check_no_reset = 1;
    download = 1;
    #1;
    if (dut.reset !== 0) $fatal(1, "Keyboard download asserted reset");
    if (dut.dl_wr !== 0 || dut.dl_index !== 8'hff)
        $fatal(1, "Keyboard download reached ROM write path");
    release dut.source_dl;
    #1;
    download = 0;
    #1;
    check_no_reset = 0;
endtask

task rom_download(input [15:0] file_index);
    index = file_index;
    force dut.source_dl = 1'b1;
    download = 1;
    #1;
    if (dut.reset !== 1) $fatal(1, "ROM download did not assert reset");
    if (file_index[5:0] == 1 && (dut.cart_dl !== 1 || dut.dl_wr !== 1 || dut.dl_index !== 8'd2))
        $fatal(1, "Cartridge download index %h did not reach loader", file_index);
    download = 0;
    release dut.source_dl;
    #1;
    if (dut.reset !== 0) $fatal(1, "Download reset did not release");
endtask

task hot_cartridge_download(input [15:0] file_index);
    status[24] = 1;
    index = file_index;
    check_no_reset = 1;
    download = 1;
    #1;
    if (dut.reset !== 0 || dut.system_reset !== 0)
        $fatal(1, "Hot cartridge download asserted reset");
    if (dut.joysticks.reset !== 1)
        $fatal(1, "Hot cartridge download did not reset joystick positions");
    if (dut.dl_wr !== 1 || dut.dl_index !== 8'd2)
        $fatal(1, "Hot cartridge download did not reach cartridge ROM");
    download = 0;
    #1;
    if (dut.reset !== 0) $fatal(1, "Hot cartridge download left reset asserted");
    check_no_reset = 0;

    status[27] = 1;
    field_edge;
    #1;
    if (dut.reset !== 1 || dut.system_reset !== 0 || dut.power_cycle !== 0)
        $fatal(1, "Master Control did not refresh hot-loaded cartridge");
    status[27] = 0;
    field_edge;

    rom_download(16'd2);
    status[24] = 0;
    #1;
    if (dut.reset !== 0) $fatal(1, "Master Control reset did not release");
endtask

initial begin
    force dut.clk_sys = clk;
    force dut.raw_vblank = vblank;
    force dut.pll_locked = pll_locked;
    force dut.buttons = buttons;
    force dut.ps2_key = ps2_key;
    force dut.OSD_STATUS = osd_status;
    force dut.status = status;
    force dut.ioctl_download = download;
    force dut.ioctl_index = index;
    force dut.ioctl_wr = 1'b1;
    #1;
    keyboard_download(16'd4);
    keyboard_download(16'h0104);
    rom_download(16'd0);
    rom_download(16'd1);
    rom_download(16'h0041); // second extension in BINVBC
    rom_download(16'd2);
    rom_download(16'd64);
    hot_cartridge_download(16'd1);
    hot_cartridge_download(16'h0041);
    index = 4;
    download = 1;
    status[0] = 1;
    #1;
    if (dut.reset !== 1 || dut.power_cycle !== 1) $fatal(1, "OSD reset did not power cycle");
    status[0] = 0;
    external_reset = 1;
    #1;
    if (dut.reset !== 1 || dut.power_cycle !== 1) $fatal(1, "External reset did not power cycle");
    external_reset = 0; download = 0;
    #1;
    buttons[1] = 1;
    #1;
    if (dut.reset !== 1 || dut.power_cycle !== 1) $fatal(1, "Framework button did not power cycle");
    buttons = 0; pll_locked = 0;
    #1;
    if (dut.reset !== 1) $fatal(1, "PLL unlock did not reset");
    pll_locked = 1;
    #1;
    if (dut.reset !== 0) $fatal(1, "Reset did not release");
    if (dut.joystick_connected !== 1) $fatal(1, "Joystick did not default to connected");
    if (dut.joysticks.relative_mode !== 0) $fatal(1, "Joystick did not default to Absolute");
    status[38] = 1;
    #1;
    if (dut.joysticks.relative_mode !== 1) $fatal(1, "Relative mode OSD connection");
    if (dut.joysticks.relative_speed !== 0) $fatal(1, "Relative speed default");
    status[40:39] = 2;
    #1;
    if (dut.joysticks.relative_speed !== 2) $fatal(1, "Relative speed OSD connection");
    status[5] = 1;
    #1;
    if (dut.joystick_connected !== 0) $fatal(1, "Joystick did not disconnect");
    status = 0;
    status[27] = 1;
    field_edge;
    #1;
    if (dut.reset !== 1 || dut.system_reset !== 0 || dut.power_cycle !== 0)
        $fatal(1, "OSD MASTER CONTROL did not use the warm reset path");
    status = 0;
    field_edge;
    status[28] = 1;
    #1;
    if (dut.reset !== 1 || dut.system_reset !== 1)
        $fatal(1, "Cartridge unload did not reset the machine");
    status = 0;

    check_no_reset = 1;
    osd_status = 1; status = ~(128'd1 | (128'd1 << 27) | (128'd1 << 28));
    #1;
    osd_status = 0; status = 0;
    #1;
    check_no_reset = 0;

    osd_status = 1;
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    ps2_key = {1'b1, 1'b1, 1'b0, 8'h76};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.reset !== 1 || dut.master_control !== 1)
        $fatal(1, "ESC did not assert MASTER CONTROL: reset=%b system=%b master=%b key=%h toggle=%b",
               dut.reset, dut.system_reset, dut.master_control, dut.ps2_key, dut.key_toggle);
    ps2_key = {1'b0, 1'b0, 1'b0, 8'h76};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.reset !== 0) $fatal(1, "ESC release did not clear MASTER CONTROL");
    for (integer code = 0; code < 512; code = code + 1) begin
        for (integer pressed = 1; pressed >= 0; pressed = pressed - 1) begin
            ps2_key = {!ps2_key[10], 1'(pressed), 9'(code)};
            repeat (2) @(posedge clk);
            #1;
            field_edge;
            if (dut.reset !== (code == 9'h076 && pressed != 0))
                $fatal(1, "Unexpected reset for PS/2 code %h, pressed %0d", code, pressed);
        end
    end
    key_event(9'h015, 1, 36'd1 << 28);
    key_event(9'h076, 1, 36'd1 << 28);
    if (dut.reset !== 1) $fatal(1, "Held-key Master Control did not reset");
    field_edge;
    if (dut.reset !== 0 || dut.kbd_matrix !== (36'd1 << 28))
        $fatal(1, "Held Master Control repeated reset or released another key");
    key_event(9'h076, 0, 36'd1 << 28);
    key_event(9'h015, 0, 0);

    status[29] = 1;
    ps2_key = {!ps2_key[10], 1'b1, 9'h076};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.reset !== 0 || dut.master_control !== 0)
        $fatal(1, "Disabled ESC asserted MASTER CONTROL");
    ps2_key = {!ps2_key[10], 1'b0, 9'h076};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    ps2_key = {!ps2_key[10], 1'b1, 9'h005};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.kbd_matrix[35] !== 1 || dut.reset !== 0)
        $fatal(1, "Disabling ESC blocked F1");
    ps2_key = {!ps2_key[10], 1'b0, 9'h005};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    status[27] = 1;
    field_edge;
    #1;
    if (dut.reset !== 1 || dut.system_reset !== 0 || dut.power_cycle !== 0)
        $fatal(1, "Disabling ESC blocked OSD MASTER CONTROL");
    status[27] = 0;
    field_edge;
    status[29] = 0;
    ps2_key = {!ps2_key[10], 1'b1, 9'h076};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.master_control !== 1) $fatal(1, "Reenabled ESC did not reset");
    status[29] = 1;
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.reset !== 0 || dut.master_control !== 0)
        $fatal(1, "Disabling held ESC did not release MASTER CONTROL");
    status[29] = 0;
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.reset !== 0) $fatal(1, "Reenabling held ESC retriggered reset");
    ps2_key = {!ps2_key[10], 1'b0, 9'h076};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    number_alias(9'h016, 9'h069, 9'h01a, 33); // 1 = z
    number_alias(9'h01e, 9'h072, 9'h022, 30); // 2 = x
    number_alias(9'h026, 9'h07a, 9'h021, 26); // 3 = c
    number_alias(9'h025, 9'h06b, 9'h01b, 29); // 4 = s
    number_alias(9'h02e, 9'h073, 9'h023, 25); // 5 = d
    number_alias(9'h036, 9'h074, 9'h02b, 21); // 6 = f
    number_alias(9'h03d, 9'h06c, 9'h01d, 24); // 7 = w
    number_alias(9'h03e, 9'h075, 9'h024, 20); // 8 = e
    number_alias(9'h046, 9'h07d, 9'h02d, 16); // 9 = r
    number_alias(9'h045, 9'h070, 9'h04a, 34); // 0 = ?/0
    edit_alias(9'h05a, 9'h004, 27); // enter = f3
    edit_alias(9'h15a, 9'h004, 27); // keypad enter = f3
    edit_alias(9'h066, 9'h005, 35); // backspace = f1
    edit_alias(9'h16c, 9'h006, 31); // home = f2
    edit_alias(9'h169, 9'h00c, 23); // end = f4
    for (integer ctrl = 0; ctrl < 2; ctrl = ctrl + 1) begin
        for (integer pad = 0; pad < 2; pad = pad + 1) begin
            key_event(ctrl ? 9'h114 : 9'h014, 1, 0);
            key_event(pad ? 9'h15a : 9'h05a, 1, 36'd1 << 15);
            key_event(9'h003, 1, 36'd1 << 15);
            key_event(ctrl ? 9'h114 : 9'h014, 0, 36'd1 << 15);
            key_event(pad ? 9'h15a : 9'h05a, 1, 36'd1 << 15);
            key_event(9'h003, 0, 36'd1 << 15);
            key_event(pad ? 9'h15a : 9'h05a, 0, 0);
        end
    end
    key_event(9'h014, 1, 0);
    key_event(9'h114, 1, 0);
    key_event(9'h014, 0, 0);
    key_event(9'h05a, 1, 36'd1 << 15);
    key_event(9'h114, 0, 36'd1 << 15);
    key_event(9'h15a, 1, (36'd1 << 15) | (36'd1 << 27));
    key_event(9'h05a, 0, 36'd1 << 27);
    key_event(9'h014, 1, 36'd1 << 27); // ctrl after enter must not retarget it
    key_event(9'h15a, 1, 36'd1 << 27);
    key_event(9'h15a, 0, 0);
    key_event(9'h014, 0, 0);
    key_event(9'h05a, 1, 36'd1 << 27);
    key_event(9'h15a, 1, 36'd1 << 27);
    key_event(9'h05a, 0, 36'd1 << 27);
    key_event(9'h15a, 0, 0);
    key_event(9'h012, 1, 36'd1 << 11);
    key_event(9'h016, 1, (36'd1 << 11) | (36'd1 << 33));
    key_event(9'h072, 1, (36'd1 << 11) | (36'd1 << 33) | (36'd1 << 30));
    key_event(9'h016, 0, (36'd1 << 11) | (36'd1 << 30));
    key_event(9'h072, 0, 36'd1 << 11);
    key_event(9'h012, 0, 0);
    key_event(9'h016, 1, 36'd1 << 33);
    key_event(9'h072, 1, (36'd1 << 33) | (36'd1 << 30));
    key_event(9'h021, 1, (36'd1 << 33) | (36'd1 << 30) | (36'd1 << 26));
    key_event(9'h05a, 1, (36'd1 << 33) | (36'd1 << 30) | (36'd1 << 26) | (36'd1 << 27));
    key_event(9'h15a, 1, (36'd1 << 33) | (36'd1 << 30) | (36'd1 << 26) | (36'd1 << 27));
    key_event(9'h066, 1, (36'd1 << 33) | (36'd1 << 30) | (36'd1 << 26) | (36'd1 << 27) | (36'd1 << 35));
    ps2_key = {!ps2_key[10], 1'b1, 9'h014};
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    key_event(9'h16c, 1, dut.kbd_matrix | (36'd1 << 31));
    key_event(9'h169, 1, dut.kbd_matrix | (36'd1 << 23));
    external_reset = 1;
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.kbd_matrix !== 0) $fatal(1, "Reset did not clear held keyboard aliases");
    external_reset = 0;
    repeat (2) @(posedge clk);
    #1;
    field_edge;
    if (dut.kbd_matrix !== 0) $fatal(1, "Keyboard aliases returned after reset");
    key_event(9'h05a, 1, 36'd1 << 27);
    key_event(9'h05a, 0, 0); // reset also cleared the held ctrl modifier
    $display("Download reset and keyboard alias checks passed");
    $finish;
end
endmodule
