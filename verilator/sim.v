`timescale 1ns/1ns

module top(
   input         clk_sys /*verilator public_flat*/,
   input         reset /*verilator public_flat*/,
   input         progressive,

   output [7:0]  VGA_R /*verilator public_flat*/,
   output [7:0]  VGA_G /*verilator public_flat*/,
   output [7:0]  VGA_B /*verilator public_flat*/,
   output        VGA_HS,
   output        VGA_VS,
   output        VGA_HB,
   output        VGA_VB,
   output        VGA_DE /*verilator public_flat*/,
   output        ce_pix /*verilator public_flat*/,

   output [15:0] AUDIO_L,
   output [15:0] AUDIO_R,

   input         ioctl_download,
   input         ioctl_upload,
   input         ioctl_wr,
   input [24:0]  ioctl_addr,
   input [7:0]   ioctl_dout,
   input [7:0]   ioctl_din,
   input [7:0]   ioctl_index,
   output reg    ioctl_wait = 1'b0,
   output        apl_available,
   output        apl_load_error,
   output        source_busy,
   output        source_error,
   output        source_complete,
   output        record_data,
   output        record_enable,
   input         playback_data,
   output        playback_enable,

   input [10:0]  ps2_key,

   input [35:0]  kbd_matrix /*verilator public_flat*/,
   input [3:0]   joy_fire /*verilator public_flat*/,
   input [63:0]  joy_pots /*verilator public_flat*/,
   input [13:0]  joy_timer_base /*verilator public_flat*/,
   input [6:0]   joy_timer_step /*verilator public_flat*/,
   input         joy_timer_curve /*verilator public_flat*/,
   input         joy_timer_auto /*verilator public_flat*/,
   input [7:0]   cart_type /*verilator public_flat*/
);

   wire        brclk_ena /*verilator public_flat*/;
   wire        hblank, vblank, csync, burst, scanline, field;
   wire [7:0]  hpos /*verilator public_flat*/;
   wire [8:0]  vpos /*verilator public_flat*/;

   wire        fifo_valid /*verilator public_flat*/;
   wire [3:0]  fifo_level /*verilator public_flat*/;

   wire [7:0]  final_mod /*verilator public_flat*/;
   wire [7:0]  background /*verilator public_flat*/;
   wire        x_zoom, y_zoom;
   wire        video_en /*verilator public_flat*/;
   wire        apl_symbols;
   wire        music_available;
   wire        apl_input_ready, apl_key_accepted;
   wire        tiny_available, tiny_input_ready, tiny_key_accepted;
   wire [35:0] source_keys;
   reg source_vs_d = 0;
   always @(posedge clk_sys) source_vs_d <= vid_vs;

   apl_source_loader source_loader (
      .clk(clk_sys), .reset(reset), .frame_tick(vid_vs && !source_vs_d),
      .download(ioctl_download && ioctl_index == 5), .wr(ioctl_wr),
      .addr(ioctl_addr), .data(ioctl_dout), .available(apl_available),
      .tiny_available(tiny_available), .tiny_input_ready(tiny_input_ready),
      .tiny_key_accepted(tiny_key_accepted),
      .music_available(music_available),
      .symbols(apl_symbols), .enabled(1'b1), .cancel(|kbd_matrix),
      .input_ready(apl_input_ready), .key_accepted(apl_key_accepted),
      .music_playback(1'b0), .auto_repeat(1'b0),
      .busy(source_busy), .started(), .complete(source_complete), .aborted(), .error(source_error), .keys(source_keys)
   );

   wire [15:0] pc0 /*verilator public_flat*/;
   wire [15:0] pc1 /*verilator public_flat*/;
   wire [15:0] dc0 /*verilator public_flat*/;
   wire [7:0]  po_a_n /*verilator public_flat*/;
   wire [7:0]  po_b_n /*verilator public_flat*/;
   wire [1:0]  audio_code /*verilator public_flat*/;
   wire        audio_stb;
   wire        joy_enable;

   wire        dl_wr = ioctl_download & ioctl_wr;
   wire [4:0]  idx_r /*verilator public_flat*/;
   wire [7:0]  vid_r, vid_g, vid_b;
   wire        vid_de, vid_hs, vid_vs, vid_hb, vid_vb;

   videobrain_core core(
      .clk        (clk_sys),
      .reset_na   (~reset),
      .power_cycle(1'b0),
      .timing_reset_na(1'b0),
      .progressive(progressive),

      .kbd_matrix (source_busy ? source_keys : kbd_matrix),
      .joy_fire   (joy_fire),
      .joy_pots   (joy_pots),
      .joy_connected (1'b1),
      .joy_timer_base (joy_timer_base),
      .joy_timer_step (joy_timer_step),
      .joy_timer_curve (joy_timer_curve),
      .joy_timer_auto (joy_timer_auto),
      .audio_code (audio_code),
      .audio_stb  (audio_stb),
      .joy_enable (joy_enable),
      .expander_record_data (record_data),
      .expander_record_enable (record_enable),
      .expander_playback_data (playback_data),
      .expander_playback_enable (playback_enable),
      .expander_modem_rxd (1'b1),
      .expander_modem_txd (),
      .expander_printer_txd (),
      .f8_po_a_n  (po_a_n),
      .f8_po_b_n  (po_b_n),

      .brclk_ena  (brclk_ena),
      .ce_pix     (ce_pix),
      .vid_idx    (idx_r),
      .vid_r      (vid_r),
      .vid_g      (vid_g),
      .vid_b      (vid_b),
      .vid_de     (vid_de),
      .vid_hs     (vid_hs),
      .vid_vs     (vid_vs),
      .vid_hb     (vid_hb),
      .vid_vb     (vid_vb),
      .fifo_valid (fifo_valid),
      .fifo_level (fifo_level),

      .hblank     (hblank),
      .vblank     (vblank),
      .burst      (burst),
      .csync      (csync),
      .scanline   (scanline),
      .field      (field),
      .hpos       (hpos),
      .vpos       (vpos),

      .final_mod  (final_mod),
      .background (background),
      .x_zoom     (x_zoom),
      .y_zoom     (y_zoom),
      .video_en   (video_en),

      .dl_addr    (ioctl_addr[15:0]),
      .dl_data    (ioctl_dout),
      .dl_wr      (dl_wr),
      .dl_index   (ioctl_download ? ioctl_index : 8'hff),
      .cart_unload(1'b0),
      .cart_loaded(),
      .unknown_cart_profile (cart_type),
      .infoman_printer_fix (1'b0),
      .apl_available (apl_available),
      .music_available (music_available),
      .apl_load_error (apl_load_error),
      .apl_symbols (apl_symbols),
      .apl_input_ready (apl_input_ready),
      .apl_key_accepted (apl_key_accepted),
      .tiny_available (tiny_available),
      .tiny_input_ready (tiny_input_ready),
      .tiny_key_accepted (tiny_key_accepted),

      .pc0        (pc0),
      .pc1        (pc1),
      .dc0        (dc0)
   );

   assign VGA_R  = vid_r;
   assign VGA_G  = vid_g;
   assign VGA_B  = vid_b;
   assign VGA_DE = vid_de;
   assign VGA_HB = vid_hb;
   assign VGA_VB = vid_vb;
   assign VGA_HS = vid_hs;
   assign VGA_VS = vid_vs;

   wire signed [15:0] dac;
   videobrain_audio audio
   (
      .clk(clk_sys),
      .reset(reset),
      .code(audio_code),
      .stb(audio_stb),
      .sample(dac)
   );
   assign AUDIO_L = dac;
   assign AUDIO_R = dac;

endmodule
