`timescale 1ns/1ps
module tb_video_clock_control;
reg clk = 0, reset = 1, progressive = 0, stall = 0, external_lock = 1;
always #5 clk = ~clk;
integer busy_cycles = 0, accepted = 0;
wire waitrequest = stall || busy_cycles != 0;
wire locked = external_lock && busy_cycles == 0;
wire ready, write;
wire [5:0] address;
wire [31:0] writedata;
videobrain_video_clock dut (
    .clk(clk), .reset(reset), .progressive(progressive),
    .locked(locked), .waitrequest(waitrequest), .ready(ready),
    .write(write), .address(address), .writedata(writedata)
);
always @(posedge clk) begin
    if (reset) begin
        busy_cycles <= 0;
        accepted <= 0;
    end else begin
        if (busy_cycles != 0) busy_cycles <= busy_cycles - 1;
        if (write && !waitrequest) begin
            if (accepted % 2 == 0) begin
                if (address != 7 || writedata != ((accepted / 2) % 2 == 0 ? 32'd2680059593 : 32'd2576980378))
                    $fatal(1, "Incorrect or uncaptured PLL frequency request");
            end else begin
                if (address != 2 || writedata != 1) $fatal(1, "Missing PLL apply command");
                busy_cycles <= 12;
            end
            accepted <= accepted + 1;
        end
    end
end
initial begin
    repeat (3) @(negedge clk);
    reset = 0;
    #1;
    if (!ready) $fatal(1, "Native startup not ready");
    progressive = 1;
    wait (write);
    @(negedge clk); stall = 1; progressive = 0;
    repeat (4) begin
        @(negedge clk);
        if (!write || address != 7 || writedata != 2680059593 || ready)
            $fatal(1, "PLL command changed while stalled");
    end
    stall = 0;
    wait (accepted == 4 && ready);
    @(negedge clk); progressive = 1;
    wait (accepted == 6);
    @(negedge clk); external_lock = 0;
    repeat (20) begin
        @(negedge clk);
        if (ready) $fatal(1, "Video released before PLL lock");
    end
    external_lock = 1;
    wait (ready);
    repeat (10) @(negedge clk);
    if (accepted != 6) $fatal(1, "Stable selection repeated PLL writes");
    reset = 1;
    repeat (2) @(negedge clk);
    if (write || ready) $fatal(1, "PLL controller active during reset");
    $display("Video PLL startup, stalled writes, queued selections, lock gating and reset passed");
    $finish;
end
initial begin
    #10000;
    $fatal(1, "Video PLL controller test timed out");
end
endmodule
