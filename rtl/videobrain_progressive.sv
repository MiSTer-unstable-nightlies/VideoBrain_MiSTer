module videobrain_progressive (
    input wire clk,
    input wire reset,
    input wire linedouble,
    input wire ce_pix,
    input wire field,
    input wire [7:0] r, g, b,
    input wire hs, vs,
    output reg ce_out = 0,
    output reg [7:0] r_out = 0, g_out = 0, b_out = 0,
    output reg hs_out = 0, vs_out = 0, hb_out = 1, vb_out = 1
);

// clk is 1052/525 times the native clock. Four banks cover the half-line
// field-length variation with a 2.5-line delay from the first long field.
reg [23:0] lines [0:1023];
reg hs_d = 0, vs_d = 1, saw_vsync_end = 0;
reg capturing = 0, ready = 0;
reg [1:0] write_bank = 0, read_bank = 0;
reg [7:0] write_x = 0, read_x = 0;
reg [8:0] read_y = 0;
reg read_field = 0, repeat_line = 0;
reg [12:0] startup_delay = 0;
reg [2:0] pixel_delay = 0;
wire tick = pixel_delay == 0;
wire line_start = ce_pix && hs && !hs_d;
wire anchor = ce_pix && vs && !vs_d && !field && saw_vsync_end && !capturing;
wire [1:0] next_bank = anchor ? 2'd0 : write_bank + 1'b1;
wire [9:0] write_addr = line_start || anchor ? {next_bank, 8'd0} : {write_bank, write_x};
wire padded = read_field && read_y == 262;

always @(posedge clk) begin
    if (!reset && ce_pix && (capturing || anchor))
        lines[write_addr] <= {r, g, b};
    if (reset) begin
        r_out <= 0;
        g_out <= 0;
        b_out <= 0;
    end else if (tick) begin
        if (!ready || padded) {r_out, g_out, b_out} <= 0;
        else {r_out, g_out, b_out} <= lines[{read_bank, read_x}];
    end
end

always @(posedge clk) begin
    ce_out <= !reset && tick;
    if (reset) begin
        hs_d <= 0;
        vs_d <= 1;
        saw_vsync_end <= 0;
        capturing <= 0;
        ready <= 0;
        write_bank <= 0;
        read_bank <= 0;
        write_x <= 0;
        read_x <= 0;
        read_y <= 0;
        read_field <= 0;
        repeat_line <= 0;
        startup_delay <= 0;
        pixel_delay <= linedouble ? 3'd3 : 3'd7;
        hs_out <= 0;
        vs_out <= 0;
        hb_out <= 1;
        vb_out <= 1;
    end else begin
        if (ce_pix) begin
            hs_d <= hs;
            vs_d <= vs;
            if (!vs) saw_vsync_end <= 1;
            if (capturing || anchor) begin
                if (line_start || anchor) begin
                    write_bank <= next_bank;
                    write_x <= 1;
                end else write_x <= write_x + 1'b1;
            end
        end
        if (anchor) begin
            capturing <= 1;
            startup_delay <= 4569;
        end else if (startup_delay != 0) startup_delay <= startup_delay - 1'b1;

        if (!tick) pixel_delay <= pixel_delay - 1'b1;
        if (tick) begin
            pixel_delay <= linedouble ? 3'd3 : 3'd7;
            hs_out <= read_x < 18;
            vs_out <= read_y < 3;
            hb_out <= read_x < 33 || read_x >= 222;
            vb_out <= !ready || read_y < 21;
            if (read_x == 227) begin
                read_x <= 0;
                repeat_line <= linedouble && !repeat_line;
                if (!linedouble || repeat_line) begin
                    if (!padded) read_bank <= read_bank + 1'b1;
                    if (read_y == 262) begin
                        read_y <= 0;
                        read_field <= !read_field;
                    end else read_y <= read_y + 1'b1;
                end
            end else read_x <= read_x + 1'b1;
        end
        if (startup_delay == 1) begin
            ce_out <= 0;
            ready <= 1;
            pixel_delay <= linedouble ? 3'd3 : 3'd7;
            read_x <= 0;
            read_y <= 0;
            read_bank <= 0;
            read_field <= 0;
            repeat_line <= 0;
        end
    end
end

endmodule
