`timescale 1ps/1ps

module tb_video;
reg clk = 0, clk_native = 0, clk_progressive = 0;
always #10520 clk = ~clk;
always #5260 clk_native = ~clk_native;
always #5250 clk_progressive = ~clk_progressive;
wire clk_video = dut.clk_video;
wire clock_model = dut.video_output != 0 ? clk_progressive : clk_native;
reg reset = 1;
reg [127:0] status = 0;
wire ce, field, de, hs, vs, hb, vb;
wire [7:0] x, r, g, b;
wire [8:0] y;

video_test_source source (
    .clk(clk), .reset_na(~reset), .progressive(1'b0),
    .ce_pix(ce), .field(field), .de(de), .hs(hs), .vs(vs), .hb(hb), .vb(vb),
    .hpos(x), .vpos(y), .r(r), .g(g), .b(b)
);
emu dut (.RESET(reset), .HDMI_WIDTH(12'd1920), .HDMI_HEIGHT(12'd1080));

wire [23:0] osd_rgb;
wire osd_de, osd_hs;
osd osd_probe (
    .clk_sys(clk), .io_osd(1'b0), .io_strobe(1'b0), .io_din(16'd0),
    .clk_video(clk_video), .din(24'd0),
    .hs_in(dut.VGA_HS), .vs_in(dut.VGA_VS), .de_in(dut.VGA_DE),
    .dout(osd_rgb), .de_out(osd_de), .hs_out(osd_hs), .vs_out(), .osd_status()
);
integer osd_address;
initial begin
    force osd_probe.osd_enable = 1'b1;
    force osd_probe.info = 1'b1;
    force osd_probe.infox = 22'd32;
    force osd_probe.infoy = 22'd32;
    force osd_probe.infow = 9'd256;
    force osd_probe.infoh = 9'd32;
    for (osd_address = 0; osd_address < 4096; osd_address = osd_address + 1)
        osd_probe.osd_buffer[osd_address] = osd_address[0] ? 8'hff : 8'h00;
end

initial begin
    force dut.clk_sys = clk;
    force dut.clk_video = clock_model;
    force dut.video_ready = 1'b1;
    force dut.reset = reset;
    force dut.status = status;
    force dut.ce_pix = ce;
    force dut.vid_field = field;
    force dut.vid_de = de;
    force dut.vid_hs = hs;
    force dut.vid_vs = vs;
    force dut.vid_hb = hb;
    force dut.vid_vb = vb;
    force dut.vid_r = r;
    force dut.vid_g = g;
    force dut.vid_b = b;
end

emu startup (.RESET(reset));
reg [45:0] startup_bus = 0;
reg startup_field = 0;
initial begin
    force startup.clk_sys = clk;
    force startup.clk_video = clk_video;
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

integer machine_cycles = 0, last_field = 0, fields = 0;
reg [29:0] native_history [0:15];
integer native_written = 0;
reg field_d = 0;
always @(negedge clk) begin
    machine_cycles = machine_cycles + 1;
    if (!reset && ce) begin
        native_history[native_written % 16] = {field, hs, vs, hb, vb, de, r, g, b};
        native_written = native_written + 1;
    end
    if (!reset && field != field_d) begin
        if (fields > 0 && machine_cycles - last_field != (field_d ? 262 : 263)*912)
            $fatal(1, "Output mode changed native machine timing");
        last_field = machine_cycles;
        fields = fields + 1;
    end
    field_d = field;
end

// Compare against complete source fields, independently of the four line banks.
reg [23:0] pixels [0:2398559];
reg source_short [0:39];
integer source_frame = -1, source_x = 0, source_y = 0;
reg source_hs_d = 0, source_vs_d = 1;
integer expected_frame = -1, output_x = 0, output_y = 0, output_copy = 0;
integer frames_240 = 0, frames_480 = 0, checked_pixels = 0;
integer cycles = 0, last_pixel = 0, last_frame = 0;
integer native_pixels = 0, bridge_pixels = 0, mixer_pixels = 0, output_pixels = 0;
integer frame_pixels = 0, settled_frames = 0;
reg checking = 0, old_ready = 0, old_ce = 0;
reg [23:0] expected_rgb;
integer expected_index;
reg [1:0] old_mode = 0;

// Check both sync-relative picture position and stripes within the OSD.
reg [23:0] osd_row [0:1511], osd_reference [0:1511];
integer osd_width = 0, osd_column, osd_rows_240 = 0, osd_rows_480 = 0;
reg osd_de_d = 0, osd_present = 0, osd_reference_valid = 0;
reg [1:0] osd_mode = 0;
reg osd_hs_d = 0;
integer osd_cycles = 0, osd_line_start = 0, osd_active_offset = -1;
always @(negedge clk_video) begin
    osd_cycles = osd_cycles + 1;
    if (osd_hs && !osd_hs_d) osd_line_start = osd_cycles;
    if (reset || dut.output_mode != osd_mode || !dut.progressive_video.ready || settled_frames < 3) begin
        osd_width = 0;
        osd_present = 0;
        osd_reference_valid = 0;
        osd_active_offset = -1;
    end else if (osd_de) begin
        if (!osd_de_d) begin
            if (osd_active_offset != -1 && osd_cycles - osd_line_start != osd_active_offset)
                $fatal(1, "Picture moved relative to horizontal sync: mode %0d", dut.output_mode);
            osd_active_offset = osd_cycles - osd_line_start;
        end
        if (osd_width >= 1512) $fatal(1, "OSD active line too wide");
        osd_row[osd_width] = osd_rgb;
        osd_width = osd_width + 1;
        if (osd_rgb != 0) osd_present = 1;
    end else if (osd_de_d) begin
        if (osd_width != (dut.output_mode == 2 ? 756 : 1512))
            $fatal(1, "OSD active duration varies: mode %0d, %0d clocks", dut.output_mode, osd_width);
        if (osd_present) begin
            for (osd_column = 0; osd_column < osd_width; osd_column = osd_column + 1) begin
                if (osd_reference_valid && osd_row[osd_column] !== osd_reference[osd_column])
                    $fatal(1, "OSD horizontal phase changed: mode %0d, clock %0d", dut.output_mode, osd_column);
                osd_reference[osd_column] = osd_row[osd_column];
            end
            osd_reference_valid = 1;
            if (dut.output_mode == 2) osd_rows_480 = osd_rows_480 + 1;
            else osd_rows_240 = osd_rows_240 + 1;
        end
        osd_width = 0;
        osd_present = 0;
    end
    osd_de_d = osd_de;
    osd_hs_d = osd_hs;
    osd_mode = dut.output_mode;
end

always @(negedge clk_video) begin
    cycles = cycles + 1;
    if (!reset) begin
        if (dut.video_ce) begin
            if (bridge_pixels >= native_written ||
                {dut.video_field, dut.video_hs, dut.video_vs, dut.video_hb, dut.video_vb,
                 dut.video_de, dut.video_r, dut.video_g, dut.video_b} !== native_history[bridge_pixels % 16])
                $fatal(1, "Video clock transfer lost or changed a native pixel");
            bridge_pixels = bridge_pixels + 1;
            if (dut.video_hs && !source_hs_d) begin
                source_x = 0;
                source_y = source_y + 1;
            end
            if (dut.video_vs && !source_vs_d) begin
                source_frame = source_frame + 1;
                source_y = 0;
                if (source_frame >= 40) $fatal(1, "Source history exhausted");
                source_short[source_frame] = dut.video_field;
            end
            if (source_frame >= 0)
                pixels[source_frame*59964 + source_y*228 + source_x] = {dut.video_r, dut.video_g, dut.video_b};
            source_x = source_x + 1;
            source_hs_d = dut.video_hs;
            source_vs_d = dut.video_vs;
        end
        if (dut.progressive_video.anchor) begin
            expected_frame = source_frame;
            if (source_short[source_frame]) $fatal(1, "Buffer did not anchor to a long field");
        end
        if (dut.output_mode != old_mode) checking = 0;
        if (dut.progressive_video.ready && !old_ready) begin
            checking = 1;
            output_x = 0;
            output_y = 0;
            output_copy = 0;
            last_pixel = 0;
            last_frame = 0;
            frame_pixels = 0;
            settled_frames = 0;
        end
        old_ready = dut.progressive_video.ready;
        old_mode = dut.output_mode;
        if (dut.out_ce && old_ce) $fatal(1, "Consecutive pixel enables can merge in MiSTer");
        old_ce = dut.out_ce;
        if (dut.out_ce) output_pixels = output_pixels + 1;
        if (dut.CE_PIXEL) mixer_pixels = mixer_pixels + 1;
        if (dut.output_mode == 0 && dut.out_ce) begin
            native_pixels = native_pixels + 1;
            if ({dut.out_hs, dut.out_vs, dut.out_hb, dut.out_vb, dut.out_r, dut.out_g, dut.out_b} !==
                {dut.video_hs, dut.video_vs, dut.video_hb, dut.video_vb, dut.video_r, dut.video_g, dut.video_b})
                $fatal(1, "Native output routing changed");
            if (dut.VGA_F1 !== dut.video_field) $fatal(1, "Native parity changed");
        end
        if (checking && dut.sd_ce) begin
            if (dut.VGA_F1 !== 0) $fatal(1, "Progressive parity metadata incorrect");
            if (last_pixel != 0 && cycles - last_pixel != (dut.output_mode == 2 ? 4 : 8))
                $fatal(1, "Progressive pixel spacing changed");
            last_pixel = cycles;
            if (output_x == 0 && output_y == 0 && output_copy == 0) begin
                if (last_frame != 0 && cycles - last_frame != 479712)
                    $fatal(1, "Progressive cadence drifted from native field average");
                last_frame = cycles;
            end
            if ({dut.sd_hs, dut.sd_vs, dut.sd_hb, dut.sd_vb} !==
                {output_x < 18, output_y < 3, (output_x < 33 || output_x >= 222), output_y < 21})
                $fatal(1, "Progressive raster mismatch at %0d,%0d", output_x, output_y);
            expected_index = expected_frame*59964 + output_y*228 + output_x;
            expected_rgb = source_short[expected_frame] && output_y == 262 ? 24'd0 : pixels[expected_index];
            if ({dut.sd_r, dut.sd_g, dut.sd_b} !== expected_rgb)
                $fatal(1, "Buffered pixel mismatch: mode %0d frame %0d x %0d y %0d copy %0d: %h != %h",
                       dut.output_mode, expected_frame, output_x, output_y, output_copy,
                       {dut.sd_r, dut.sd_g, dut.sd_b}, expected_rgb);
            checked_pixels = checked_pixels + 1;
            frame_pixels = frame_pixels + 1;
            if (output_x == 227) begin
                output_x = 0;
                if (dut.output_mode == 2 && output_copy == 0) output_copy = 1;
                else begin
                    output_copy = 0;
                    if (output_y == 262) begin
                        if (frame_pixels != (dut.output_mode == 2 ? 119928 : 59964))
                            $fatal(1, "Progressive raster lost pixels");
                        if (dut.output_mode == 2) frames_480 = frames_480 + 1;
                        else frames_240 = frames_240 + 1;
                        settled_frames = settled_frames + 1;
                        if (settled_frames >= 3 &&
                            (dut.video_freak.hsize !== 12'd189 || dut.video_freak.vsize !== (dut.output_mode == 2 ? 12'd484 : 12'd242)))
                            $fatal(1, "Incorrect scaler dimensions: mode %0d, frame %0d: %0d by %0d",
                                   dut.output_mode, settled_frames, dut.video_freak.hsize, dut.video_freak.vsize);
                        expected_frame = expected_frame + 1;
                        output_y = 0;
                        frame_pixels = 0;
                    end else output_y = output_y + 1;
                end
            end else output_x = output_x + 1;
        end
        if (dut.video_mixer.scandoubler || dut.video_mixer.hq2x || dut.VGA_SL != 0)
            $fatal(1, "Generic scandoubler effects must stay disabled");
    end
    if (cycles > 16000000) $fatal(1, "Video test timed out");
end

task request_mode(input [1:0] mode);
    reg [1:0] previous;
begin
    wait (y == 100 && x == 100);
    @(negedge clk);
    previous = dut.video_output;
    status[42:41] = mode;
    repeat (1000) @(negedge clk);
    if (dut.video_output != previous) $fatal(1, "Selection applied without confirmation");
    status[43] = 1;
    @(negedge clk);
    status[43] = 0;
    status[42:41] = 3;
    if (dut.video_output != previous) $fatal(1, "Output applied within active field");
    @(field);
    repeat (5) @(negedge clk);
    if (dut.video_output != mode) $fatal(1, "Output did not apply at field boundary");
end
endtask

integer mixer_start, output_start, native_start, bridge_start;
initial begin
    repeat (10) @(negedge clk);
    reset = 0;
    request_mode(1);
    wait (frames_240 == 4);
    request_mode(2);
    wait (frames_480 == 4);
    mixer_start = mixer_pixels;
    output_start = output_pixels;
    wait (frames_480 == 8);
    if (mixer_pixels - mixer_start != output_pixels - output_start)
        $fatal(1, "Real MiSTer mixer lost pixel enables");
    force dut.system_reset = 1'b1;
    repeat (10) @(negedge clk);
    if (dut.video_output != 2) $fatal(1, "Machine reset changed video mode");
    release dut.system_reset;
    request_mode(1);
    wait (frames_240 == 8);
    request_mode(0);
    native_start = native_pixels;
    bridge_start = bridge_pixels;
    repeat (10000) @(negedge clk);
    if (native_pixels - native_start != bridge_pixels - bridge_start)
        $fatal(1, "Native output lost pixels");
    if (native_pixels < 1000 || checked_pixels < 1000000)
        $fatal(1, "Insufficient video coverage");
    if (osd_rows_240 < 32 || osd_rows_480 < 32)
        $fatal(1, "Insufficient OSD coverage: %0d/%0d rows", osd_rows_240, osd_rows_480);
    @(negedge clk); reset = 1;
    repeat (5) @(negedge clk);
    if (dut.output_mode != 0 || dut.progressive_video.ready)
        $fatal(1, "External reset did not clear progressive output");
    $display("Native timing, buffered pixels, padding, 240p/480p cadence, mode controls, MiSTer mixer and OSD passed");
    $finish;
end
endmodule
