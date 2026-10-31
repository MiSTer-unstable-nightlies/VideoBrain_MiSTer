`timescale 1ns/1ps
module tb_rtc_boot;
reg clk = 0;
always #5 clk = ~clk;
reg reset = 1, power_cycle = 0;
reg rtc_clock_enable = 1, rtc_time_valid = 1;
reg [55:0] rtc_time = 56'h05261030235958;
reg dl_wr = 0;
reg [15:0] dl_addr = 0;
reg [7:0] dl_data = 0, dl_index = 8'hff;
wire [15:0] pc;

videobrain_core core (
    .clk(clk), .reset_na(!reset), .power_cycle(power_cycle),
    .timing_reset_na(1'b0), .progressive(1'b1),
    .rtc_clock_enable(rtc_clock_enable), .rtc_time_valid(rtc_time_valid), .rtc_time(rtc_time),
    .kbd_matrix(36'd0), .joy_fire(4'd0), .joy_pots(64'h8080808080808080),
    .joy_connected(1'b1), .joy_timer_base(14'd2580), .joy_timer_step(7'd7),
    .joy_timer_curve(1'b0), .joy_timer_auto(1'b0),
    .expander_playback_data(1'b1), .expander_modem_rxd(1'b1),
    .dl_addr(dl_addr), .dl_data(dl_data), .dl_wr(dl_wr), .dl_index(dl_index),
    .cart_unload(1'b0), .unknown_cart_profile(8'd0), .infoman_printer_fix(1'b0),
    .pc0(pc)
);

// GHDL packs ascending VHDL arrays with element zero at the high end.
function automatic [7:0] ram(input integer address);
    ram = core.u_sys_bus.sys_ram[(1023 - address)*8 +: 8];
endfunction
function automatic [7:0] scratch(input integer address);
    scratch = core.u_cpu.scratch_regs[(63 - address)*8 +: 8];
endfunction

task load_image(input string path, input [7:0] index);
    integer fd, value, address;
    fd = $fopen(path, "rb");
    if (!fd) $fatal(1, "Cannot open %s", path);
    dl_index = index;
    address = 0;
    value = $fgetc(fd);
    while (value != -1) begin
        @(negedge clk);
        dl_addr = 16'(address); dl_data = 8'(value); dl_wr = 1;
        address++;
        value = $fgetc(fd);
    end
    @(negedge clk); dl_wr = 0; dl_index = 8'hff;
    $fclose(fd);
endtask

task cold_boot;
    @(negedge clk); reset = 1; power_cycle = 1;
    repeat (8) @(negedge clk);
    power_cycle = 0; reset = 0;
endtask

task seeded;
    wait (core.clock_seed_done);
    @(negedge clk);
    if (ram('h3e1) != 'haa || scratch(21) != 60 || scratch(22) != 'h80)
        $fatal(1, "Clock initialization flags/countdown mismatch");
    if (scratch(23) != rtc_time[7:0] || scratch(63) != rtc_time[15:8])
        $fatal(1, "Clock minutes/seconds mismatch");
    $display("RTC seed complete at PC %h", pc);
endtask

string bios1, bios2;
initial begin
    if (!$value$plusargs("bios1=%s", bios1) || !$value$plusargs("bios2=%s", bios2))
        $fatal(1, "Supply +bios1 and +bios2");
    load_image(bios1, 0); load_image(bios2, 1);
    cold_boot; seeded;
    if ({ram('h3f1), ram('h3f0), ram('h3ef), ram('h3ee), ram('h3ed), ram('h3ec)} !=
        48'h202609300423)
        $fatal(1, "Initial clock date/hour mismatch");

    // The unmodified BIOS must advance the seeded clock across midnight.
    wait (ram('h3ee) == 'h31 && ram('h3ec) == 0);
    if (ram('h3ed) != 5 || scratch(63) != 0 || scratch(23) != 0)
        $fatal(1, "BIOS midnight rollover mismatch");

    // Warm CPU reset preserves memory, but the enabled option reseeds it.
    @(negedge clk); reset = 1; rtc_time = 56'h00270228010203;
    repeat (8) @(negedge clk);
    reset = 0; seeded;
    if ({ram('h3f1), ram('h3f0), ram('h3ef), ram('h3ee), ram('h3ed), ram('h3ec)} !=
        48'h202701280601)
        $fatal(1, "Warm reset did not reseed date/hour");

    rtc_clock_enable = 0; cold_boot;
    wait (core.clock_boot_ready); repeat (20) @(negedge clk);
    if (core.clock_seed_done || ram('h3e1) != 0 || scratch(22) != 0)
        $fatal(1, "Disabled option changed the clock");

    rtc_clock_enable = 1; rtc_time_valid = 0; cold_boot;
    wait (core.clock_boot_ready); repeat (20) @(negedge clk);
    if (core.clock_seed_done || ram('h3e1) != 0 || scratch(22) != 0)
        $fatal(1, "Missing RTC changed the clock");

    // An RTC arriving after startup is applied at a later BIOS clock call.
    rtc_time = 56'h01280101000000; rtc_time_valid = 1;
    seeded;
    if ({ram('h3f1), ram('h3f0), ram('h3ef), ram('h3ee), ram('h3ed), ram('h3ec)} !=
        48'h202800010000)
        $fatal(1, "Late RTC did not initialize the clock");
    $display("RTC boot, reset, disabled/missing RTC and BIOS rollover passed");
    $finish;
end
initial begin
    #2000000000;
    $fatal(1, "RTC boot test timed out at PC %h", pc);
end
endmodule
