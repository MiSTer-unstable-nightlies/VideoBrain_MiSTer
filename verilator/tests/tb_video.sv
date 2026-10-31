`timescale 1ns/1ns

module tb_video;
reg clk = 0;
always #5 clk = ~clk;
reg reset = 1;
reg [127:0] status_native = 0, status_progressive = 0;
wire ce, field, de, hs, vs, hb, vb;
wire [7:0] x, r, g, b;
wire [8:0] y;
wire p_ce, p_field, p_de, p_hs, p_vs, p_hb, p_vb;
wire [7:0] p_x, p_r, p_g, p_b;
wire [8:0] p_y;
wire [7:0] nr, ng, nb, pr, pg, pb;
wire nf, pf, nhs, nvs, nde, phs, pvs, pde, nce, pce;

video_test_source source(
    .clk(clk), .reset_na(~reset), .ce_pix(ce), .field(field),
    .progressive(1'b0),
    .de(de), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .hpos(x), .vpos(y), .r(r), .g(g), .b(b)
);
video_test_source progressive_source(
    .clk(clk), .reset_na(~reset), .progressive(progressive.progressive),
    .ce_pix(p_ce), .field(p_field), .de(p_de), .hs(p_hs), .vs(p_vs),
    .hb(p_hb), .vb(p_vb), .hpos(p_x), .vpos(p_y),
    .r(p_r), .g(p_g), .b(p_b)
);

emu native(
    .RESET(reset), .HDMI_WIDTH(12'd1920), .HDMI_HEIGHT(12'd1080),
    .VGA_R(nr), .VGA_G(ng), .VGA_B(nb), .VGA_F1(nf),
    .VGA_HS(nhs), .VGA_VS(nvs), .VGA_DE(nde), .CE_PIXEL(nce)
);
emu progressive(
    .RESET(reset), .HDMI_WIDTH(12'd1920), .HDMI_HEIGHT(12'd1080),
    .VGA_R(pr), .VGA_G(pg), .VGA_B(pb), .VGA_F1(pf),
    .VGA_HS(phs), .VGA_VS(pvs), .VGA_DE(pde), .CE_PIXEL(pce)
);

emu startup(.RESET(reset));
reg [45:0] startup_bus = 0;
reg startup_field = 0;
initial begin
    force startup.clk_sys = clk;
    force startup.HPS_BUS = startup_bus;
    force startup.vid_field = startup_field;
    repeat (2) @(negedge clk);
    startup_bus[34:33] = 2'b11;
    startup_bus[31:16] = 16'h001e;
    @(negedge clk);
    startup_bus[31:16] = 0;
    repeat (2) @(negedge clk);
    startup_bus[31:16] = 16'h0400;
    @(negedge clk);
    startup_bus[34:33] = 0;
    wait (!reset);
    repeat (3) @(negedge clk);
    if (startup.video_output != 0) $fatal(1, "Startup output changed before field boundary");
    startup_field = 1;
    repeat (3) @(negedge clk);
    if (startup.video_output != 2) $fatal(1, "Saved 480p output was not restored");
end

// exercise top-level routing and measurement with native timing and rendering
// board peripherals and unused scaler arithmetic are omitted with iverilog -i
initial begin
    force native.clk_sys = clk;
    force native.reset = reset;
    force native.status = status_native;
    force native.ce_pix = ce;
    force native.vid_field = field;
    force native.vid_de = de;
    force native.vid_hs = hs;
    force native.vid_vs = vs;
    force native.vid_hb = hb;
    force native.vid_vb = vb;
    force native.vid_r = r;
    force native.vid_g = g;
    force native.vid_b = b;
    force progressive.clk_sys = clk;
    force progressive.reset = reset;
    force progressive.status = status_progressive;
    force progressive.ce_pix = p_ce;
    force progressive.vid_field = p_field;
    force progressive.vid_de = p_de;
    force progressive.vid_hs = p_hs;
    force progressive.vid_vs = p_vs;
    force progressive.vid_hb = p_hb;
    force progressive.vid_vb = p_vb;
    force progressive.vid_r = p_r;
    force progressive.vid_g = p_g;
    force progressive.vid_b = p_b;
end

integer cycles = 0, last_field_cycle = 0, fields = 0;
integer native_measurements = 0, progressive_measurements = 0;
integer active_rows = 0, bottom_pixels = 0;
integer p_last_field_cycle = 0, p_fields = 0, p_active_rows = 0, p_bottom_pixels = 0;
reg old_field = 0, old_de = 0, old_nmeasure = 0, old_pmeasure = 0;
reg old_pmode = 0, old_pfield = 0, old_pde = 0, p_field_mode = 0;
reg [27:0] source_pixels [0:1048575];
integer source_count = 0, source_line = 0, doubled_pixels = 0, source_base = 0;
integer output_lines = 0, output_rows = 0, output_frames = 0;
integer last_output_line = 0, last_output_frame = 0;
reg source_hs_d = 0, output_hs_d = 0, output_vs_d = 0, output_de_d = 0;
always @(negedge clk) begin
    cycles = cycles + 1;
    if (!reset) begin
        if (native.video_mixer.scandoubler || native.video_mixer.hq2x || native.VGA_SL != 0 ||
            progressive.video_mixer.scandoubler || progressive.video_mixer.hq2x || progressive.VGA_SL != 0)
            $fatal(1, "Generic scandoubler effects must stay disabled");
        if (field != old_field) begin
            if (fields > 0 && cycles - last_field_cycle != (old_field ? 262 : 263)*912)
                $fatal(1, "Native field timing changed");
            if (fields > 0 && active_rows != (old_field ? 241 : 242))
                $fatal(1, "Visible rows changed: %0d", active_rows);
            if (fields > 0 && bottom_pixels != 189)
                $fatal(1, "Bottom row missing: %0d", bottom_pixels);
            last_field_cycle = cycles;
            active_rows = 0;
            bottom_pixels = 0;
            fields = fields + 1;
        end
        old_field = field;
        if (ce) begin
            if (de && !old_de) active_rows = active_rows + 1;
            if (de && y == (field ? 261 : 262)) bottom_pixels = bottom_pixels + 1;
            old_de = de;
            if (native.video_freak.VGA_VS && !old_nmeasure)
                native_measurements = native_measurements + 1;
            old_nmeasure = native.video_freak.VGA_VS;
        end
        if (p_field != old_pfield) begin
            if (p_fields > 0 && cycles - p_last_field_cycle != (p_field_mode || !old_pfield ? 263 : 262)*912)
                $fatal(1, "Progressive field timing incorrect");
            if (p_fields > 0 && p_active_rows != (p_field_mode || !old_pfield ? 242 : 241))
                $fatal(1, "Progressive visible rows changed: %0d", p_active_rows);
            if (p_fields > 0 && p_bottom_pixels != 189)
                $fatal(1, "Progressive bottom row missing: %0d", p_bottom_pixels);
            p_last_field_cycle = cycles;
            p_active_rows = 0;
            p_bottom_pixels = 0;
            p_fields = p_fields + 1;
        end
        old_pfield = p_field;
        if (p_y == 10) p_field_mode = progressive.progressive;
        if (p_ce) begin
            if (p_de && !old_pde) p_active_rows = p_active_rows + 1;
            if (p_de && p_y == (p_field_mode || !p_field ? 262 : 261))
                p_bottom_pixels = p_bottom_pixels + 1;
            old_pde = p_de;
            if (progressive.video_freak.VGA_VS && !old_pmeasure)
                progressive_measurements = progressive_measurements + 1;
            old_pmeasure = progressive.video_freak.VGA_VS;
        end
        if (nf !== field) $fatal(1, "Native parity changed");
        if (pf !== (progressive.progressive ? 1'b0 : p_field))
            $fatal(1, "Progressive parity metadata incorrect");
        if (progressive.progressive != old_pmode && p_vs)
            $fatal(1, "Mode changed during VSYNC");
        old_pmode = progressive.progressive;
        if (fields >= 1 && nce) begin
            if ({nhs, nvs, nde, nr, ng, nb} !== {hs, vs, de, r, g, b})
                $fatal(1, "Native video routing changed");
        end
        if (p_fields >= 1 && pce && !progressive.linedouble) begin
            if ({phs, pvs, pde, pr, pg, pb} !== {p_hs, p_vs, p_de, p_r, p_g, p_b})
                $fatal(1, "Progressive video routing changed");
        end
        if (fields >= 2 && fields <= 3 && y == 50 && ce) begin
            if (native.video_freak.vsize != 483)
                $fatal(1, "Wrong scaler height");
            if (native.video_freak.hsize != 189 || progressive.video_freak.hsize != 189)
                $fatal(1, "Wrong scaler width");
        end
        if (p_fields >= 2 && p_fields <= 3 && p_y == 50 && p_ce &&
            progressive.video_freak.vsize != 242)
            $fatal(1, "Progressive scaler height must stay at 242");
        if (!progressive.linedouble) begin
            source_count = 0;
            doubled_pixels = 0;
            source_hs_d = 0;
        end else begin
            if (pf !== 0) $fatal(1, "480p must report progressive output");
            if (p_ce) begin
                source_pixels[source_count] = {p_hs, p_vs, p_hb, p_vb, p_r, p_g, p_b};
                if (p_hs && !source_hs_d) source_line = source_count;
                source_hs_d = p_hs;
                source_count = source_count + 1;
            end
            if (pce) begin
                if (doubled_pixels == 0) source_base = source_line - 228;
                if (source_base < 0 || source_base + (doubled_pixels / 456)*228 + doubled_pixels % 228 >= source_count)
                    $fatal(1, "480p read an incomplete source line");
                if ({phs, pvs, progressive.video_mixer.HBlank, progressive.video_mixer.VBlank, pr, pg, pb} !==
                    source_pixels[source_base + (doubled_pixels / 456)*228 + doubled_pixels % 228])
                    $fatal(1, "480p pixel/blanking mismatch at output pixel %0d", doubled_pixels);
                if (doubled_pixels > 0 && cycles - last_output_line != 2)
                    $fatal(1, "480p pixel enable must run every two clocks");
                last_output_line = cycles;
                doubled_pixels = doubled_pixels + 1;
                if (phs && !output_hs_d) output_lines = output_lines + 1;
                if (pde && !output_de_d) output_rows = output_rows + 1;
                if (pvs && !output_vs_d) begin
                    if (output_frames > 1) begin
                        if (output_lines != 526 || output_rows != 484 || cycles - last_output_frame != 263*912)
                            $fatal(1, "480p full raster changed: %0d lines, %0d rows", output_lines, output_rows);
                        if (progressive.video_freak.vsize != 484 || progressive.video_freak.hsize != 189)
                            $fatal(1, "480p scaler must measure 189 by 484");
                    end
                    output_lines = 0;
                    output_rows = 0;
                    last_output_frame = cycles;
                    output_frames = output_frames + 1;
                end
                output_hs_d = phs;
                output_vs_d = pvs;
                output_de_d = pde;
            end
        end
    end
    if (cycles > 6000000) $fatal(1, "Video test timed out");
end

task request_mode(input bit mode);
begin
    wait (p_y == 100 && p_x == 100);
    @(negedge clk);
    status_progressive[42:41] = mode ? 2'd1 : 2'd0;
    repeat (1000) @(negedge clk);
    if (progressive.progressive !== !mode)
        $fatal(1, "Selection applied without Apply Video Output");
    status_progressive[43] = 1;
    @(negedge clk);
    status_progressive[43] = 0;
    #1;
    if (progressive.progressive !== !mode)
        $fatal(1, "Mode changed within active field");
    wait (p_field != old_pfield);
    repeat (3) @(negedge clk);
    if (progressive.progressive !== mode) $fatal(1, "Mode did not latch");
end
endtask

initial begin
    repeat (10) @(negedge clk);
    reset = 0;
    status_native[4:3] = 3;
    status_progressive[4:3] = 1;
    if (progressive.progressive !== 0) $fatal(1, "240p must default off");
    request_mode(1);
    wait (p_fields == 4);
    if (native_measurements != 3 || progressive_measurements != 4)
        $fatal(1, "Wrong measurement cadence: %0d/%0d", native_measurements, progressive_measurements);
    request_mode(0);
    request_mode(1);
    wait (p_y == 100 && p_x == 100);
    @(negedge clk);
    status_progressive[42:41] = 2;
    wait (p_field != old_pfield);
    repeat (3) @(negedge clk);
    if (progressive.video_output != 1) $fatal(1, "480p selection applied without confirmation");
    status_progressive[43] = 1;
    @(negedge clk);
    status_progressive[43] = 0;
    // Applying captures the selection even if it changes before the boundary.
    status_progressive[42:41] = 0;
    wait (p_field != old_pfield);
    repeat (3) @(negedge clk);
    if (progressive.video_output != 2) $fatal(1, "480p did not apply at the boundary");
    force progressive.system_reset = 1'b1;
    repeat (10) @(negedge clk);
    if (progressive.video_output != 2) $fatal(1, "Machine reset changed the applied output");
    release progressive.system_reset;
    wait (output_frames == 3);
    wait (p_vs == 0 && p_y == 50);
    @(negedge clk);
    reset = 1;
    repeat (3) @(negedge clk);
    if (progressive.progressive !== 0) $fatal(1, "Reset did not restore native metadata");
    $display("Video routing, apply controls, 480p pixels, full raster and measurement test passed");
    $finish;
end
endmodule

// mixer passthrough isolates input routing from quartus-specific sys constructs
module video_mixer #(parameter GAMMA = 0)(
    input CLK_VIDEO, ce_pix, scandoubler, hq2x,
    output CE_PIXEL,
    inout [21:0] gamma_bus,
    input [7:0] R, G, B,
    input HSync, VSync, HBlank, VBlank,
    output [7:0] VGA_R, VGA_G, VGA_B,
    output VGA_VS, VGA_HS, VGA_DE
);
assign CE_PIXEL = ce_pix;
assign {VGA_R, VGA_G, VGA_B} = {R, G, B};
assign {VGA_VS, VGA_HS, VGA_DE} = {VSync, HSync, ~(HBlank | VBlank)};
endmodule
