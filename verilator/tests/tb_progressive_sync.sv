`timescale 1ns/1ps

module tb_progressive_sync;
reg clk = 0, reset = 1;
always #5 clk = ~clk;
wire done_240, done_480;
progressive_sync_check #(.DOUBLE(0)) mode_240(clk, reset, done_240);
progressive_sync_check #(.DOUBLE(1)) mode_480(clk, reset, done_480);
initial begin
    repeat (8) @(negedge clk);
    reset = 0;
    wait (done_240 && done_480);
    $display("240p/480p sync-to-picture alignment and frame cadence passed");
    $finish;
end
initial begin
    #15000000;
    $fatal(1, "Progressive sync test timed out");
end
endmodule

module progressive_sync_check #(parameter DOUBLE = 0)(
    input wire clk, reset,
    output reg done = 0
);
localparam PIXEL_CLOCKS = DOUBLE ? 4 : 8;
wire ce, hs, vs, hb;
videobrain_progressive dut (
    .clk(clk), .reset(reset), .linedouble(DOUBLE != 0),
    .ce_pix(1'b0), .field(1'b0), .r(8'd0), .g(8'd0), .b(8'd0),
    .hs(1'b0), .vs(1'b0), .ce_out(ce),
    .r_out(), .g_out(), .b_out(), .hs_out(hs), .vs_out(vs), .hb_out(hb), .vb_out()
);
integer cycles = 0, line_start = 0, line_period = 0, frame_start = 0, frames = 0;
reg hs_d = 0, vs_d = 0, hb_d = 1;
always @(negedge clk) begin
    cycles = cycles + 1;
    if (!reset && ce) begin
        if (hs && !hs_d) begin
            if (line_start != 0) begin
                if (line_period != 0 && cycles - line_start != line_period)
                    $fatal(1, "Mode %0d horizontal line period varies: %0d then %0d clocks",
                           DOUBLE, line_period, cycles - line_start);
                line_period = cycles - line_start;
            end
            line_start = cycles;
        end
        if (!hs && hs_d && cycles - line_start != 18*PIXEL_CLOCKS)
            $fatal(1, "Mode %0d sync width changed", DOUBLE);
        if (!hb && hb_d && cycles - line_start != 33*PIXEL_CLOCKS)
            $fatal(1, "Mode %0d sync-to-active offset: %0d, expected %0d",
                   DOUBLE, cycles - line_start, 33*PIXEL_CLOCKS);
        if (hb && !hb_d && cycles - line_start != 222*PIXEL_CLOCKS)
            $fatal(1, "Mode %0d active end moved relative to sync", DOUBLE);
        if (vs && !vs_d) begin
            if (frames != 0 && cycles - frame_start != 479712)
                $fatal(1, "Mode %0d frame cadence changed", DOUBLE);
            frame_start = cycles;
            frames = frames + 1;
            if (frames == 3) done = 1;
        end
        hs_d = hs;
        vs_d = vs;
        hb_d = hb;
    end
end
endmodule
