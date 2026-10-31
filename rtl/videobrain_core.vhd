
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.f8_pack.ALL;
USE work.uv201_pack.ALL;
USE work.uv202_pack.ALL;

ENTITY videobrain_core IS
  GENERIC (
    CLK_DIV_MCLK : positive := 1;
    CPU_CLK_DIV  : positive := 7
    );
  PORT (
    clk      : IN  std_logic;
    reset_na : IN  std_logic;
    power_cycle : IN std_logic := '0';
    timing_reset_na : IN std_logic := '0';
    progressive : IN std_logic := '0';
    rtc_clock_enable : IN std_logic := '0';
    rtc_time_valid : IN std_logic := '0';
    rtc_time : IN unsigned(55 DOWNTO 0) := (OTHERS => '0');

    kbd_matrix : IN std_logic_vector(35 DOWNTO 0);
    joy_fire   : IN std_logic_vector(3 DOWNTO 0);
    joy_pots   : IN std_logic_vector(63 DOWNTO 0);
    joy_connected : IN std_logic := '1';
    joy_timer_base : IN unsigned(13 DOWNTO 0);
    joy_timer_step : IN unsigned(6 DOWNTO 0);
    joy_timer_curve : IN std_logic;
    joy_timer_auto : IN std_logic := '0';

    audio_code : OUT std_logic_vector(1 DOWNTO 0);
    audio_stb  : OUT std_logic;
    joy_enable : OUT std_logic;
    expander_record_data : OUT std_logic;
    expander_record_enable : OUT std_logic;
    expander_playback_data : IN std_logic := '1';
    expander_playback_enable : OUT std_logic;
    expander_modem_rxd : IN std_logic := '1';
    expander_modem_txd : OUT std_logic;
    expander_printer_txd : OUT std_logic;

    f8_po_a_n : OUT uv8;
    f8_po_b_n : OUT uv8;

    brclk_ena  : OUT std_logic;

    ce_pix : OUT std_logic;
    vid_idx: OUT std_logic_vector(4 DOWNTO 0);
    vid_r  : OUT uv8;
    vid_g  : OUT uv8;
    vid_b  : OUT uv8;
    vid_de : OUT std_logic;
    vid_hs : OUT std_logic;
    vid_vs : OUT std_logic;
    vid_hb : OUT std_logic;
    vid_vb : OUT std_logic;

    -- debug ports avoid quartus vhdl record limits at the systemverilog boundary
    fifo_valid : OUT std_logic;
    fifo_level : OUT unsigned(3 DOWNTO 0);

    hblank   : OUT std_logic;
    vblank   : OUT std_logic;
    burst    : OUT std_logic;
    csync    : OUT std_logic;
    scanline : OUT std_logic;
    field    : OUT std_logic;
    hpos     : OUT unsigned(7 DOWNTO 0);
    vpos     : OUT unsigned(8 DOWNTO 0);

    final_mod  : OUT uv8;
    background : OUT uv8;
    x_zoom     : OUT std_logic;
    y_zoom     : OUT std_logic;
    video_en   : OUT std_logic;

    dl_addr  : IN unsigned(15 DOWNTO 0);
    dl_data  : IN uv8;
    dl_wr    : IN std_logic;
    dl_index : IN uv8;
    cart_unload : IN std_logic := '0';
    cart_loaded : OUT std_logic := '0';
    unknown_cart_profile: IN uv8;
    infoman_printer_fix : IN std_logic := '0';
    apl_available : OUT std_logic;
    music_available : OUT std_logic;
    apl_load_error : OUT std_logic;
    apl_symbols : OUT std_logic := '0';
    apl_input_ready : OUT std_logic := '0';
    apl_key_accepted : OUT std_logic := '0';

    pc0 : OUT uv16;
    pc1 : OUT uv16;
    dc0 : OUT uv16
    );
END ENTITY videobrain_core;

ARCHITECTURE rtl OF videobrain_core IS
  SIGNAL machine_reset_na, power_busy : std_logic;

  SIGNAL cpu_dr, cpu_dw : uv8;
  SIGNAL romc : uv5;
  SIGNAL tick : std_logic;
  SIGNAL phase : uint4;
  SIGNAL cpu_ce : std_logic;
  SIGNAL smi_ce : std_logic;
  SIGNAL cpu_ce_raw, apl_paused : std_logic;

  SIGNAL ext_addr  : unsigned(13 DOWNTO 0);
  SIGNAL ext_rd    : std_logic;
  SIGNAL ext_wr    : std_logic;
  SIGNAL ext_wdata : uv8;
  SIGNAL ext_rdata : uv8;
  SIGNAL ext_req   : std_logic;
  SIGNAL ext_class : bus_access_t;
  SIGNAL ext_grant : std_logic;

  SIGNAL brclk_ena_l : std_logic;
  SIGNAL dmareq0 : std_logic;
  SIGNAL line_start_l   : std_logic;
  SIGNAL hblank_rising  : std_logic;
  SIGNAL field_l : std_logic;
  SIGNAL vpos_l  : unsigned(8 DOWNTO 0);

  SIGNAL uv_o_enb : std_logic;
  SIGNAL uv_o_a_b : std_logic;
  SIGNAL uv_obj_addr  : uv8;
  SIGNAL uv_obj_rdata : uv8;
  SIGNAL bb_addr  : unsigned(12 DOWNTO 0);
  SIGNAL bb_rdata : uv8;

  SIGNAL fetch_umireq : std_logic;
  SIGNAL fifo_writable : std_logic;
  SIGNAL fifo_wr_en : std_logic;
  SIGNAL fifo_wr_entry : uv201_fifo_entry_t;

  SIGNAL po_a_n_l, po_b_n_l, pi_b_n_l : uv8;
  SIGNAL kbd_b_in_n : uv8;
  SIGNAL expander_data_n, expander_clock_n, expander_interrupt_n : std_logic;
  SIGNAL modem_rxd_meta, modem_rxd_sync : std_logic := '1';
  SIGNAL port1_wr_l : std_logic;
  SIGNAL key_latch_l : uv8;
  SIGNAL joy_enable_l : std_logic;
  SIGNAL joy_timer : unsigned(13 DOWNTO 0) := (OTHERS => '0');
  SIGNAL joy_linear_base : unsigned(13 DOWNTO 0);
  SIGNAL joy_linear_step : unsigned(6 DOWNTO 0);
  SIGNAL joy_timer_active : std_logic := '0';
  SIGNAL joy_capture_stb : std_logic := '0';
  SIGNAL joy_capture_x : uv8 := (OTHERS => '0');
  SIGNAL joy_capture_y : unsigned(8 DOWNTO 0) := (OTHERS => '0');
  SIGNAL joy_out, joy_int : std_logic := '0';
  SIGNAL joy_armed : std_logic := '1';
  SIGNAL joy_line : std_logic := '1';
  SIGNAL uv_o_kbd_l : std_logic;
  SIGNAL x_zoom_l, y_zoom_l : std_logic;
  SIGNAL fifo_pop_l   : std_logic;
  SIGNAL fifo_entry_l : uv201_fifo_entry_t;
  SIGNAL fifo_valid_l : std_logic;
  SIGNAL hblank_l, vblank_l : std_logic;
  SIGNAL hpos_l : unsigned(7 DOWNTO 0);
  SIGNAL final_mod_l, background_l : uv8;

  SIGNAL io_addr  : uv8;
  SIGNAL io_rd    : std_logic;
  SIGNAL io_wr    : std_logic;
  SIGNAL io_wdata : uv8;
  SIGNAL io_rdata : uv8;
  SIGNAL smi_rdata : uv8;
  SIGNAL smi_sel   : std_logic;

  SIGNAL int_req    : std_logic;
  SIGNAL int_vector : uv16;
  SIGNAL int_ack    : std_logic;
  SIGNAL clock_seed_phase : natural RANGE 0 TO 7 := 0;
  SIGNAL clock_seed_done, clock_boot_ready : std_logic := '0';
  SIGNAL clock_snapshot : unsigned(55 DOWNTO 0) := (OTHERS => '0');
  SIGNAL clock_seed_we : std_logic;
  SIGNAL clock_ram_addr : unsigned(9 DOWNTO 0);
  SIGNAL clock_ram_data, clock_cpu_data : uv8;
  SIGNAL clock_cpu_addr : unsigned(5 DOWNTO 0);
  SIGNAL ext_int    : std_logic;
  SIGNAL yint_irq : std_logic;
  SIGNAL uv_current_y : unsigned(8 DOWNTO 0);

  SIGNAL uv_o_int_l  : std_logic;
  SIGNAL uv_o_frz_l  : std_logic;
  SIGNAL uv_y_int_l  : uv8;
  SIGNAL uv_yint_ho_l : std_logic;

BEGIN
  machine_reset_na <= reset_na AND NOT power_busy;

  apl_paused <= '0';
  cpu_ce <= cpu_ce_raw WHEN clock_seed_phase = 0 ELSE '0';

  -- Seed after BIOS initialization, before cartridge dispatch or a later clock call.
  PROCESS (clk, machine_reset_na) IS
  BEGIN
    IF machine_reset_na = '0' THEN
      clock_seed_phase <= 0;
      clock_seed_done <= '0';
      clock_boot_ready <= '0';
    ELSIF rising_edge(clk) THEN
      IF clock_seed_phase /= 0 THEN
        IF clock_seed_phase = 7 THEN
          clock_seed_phase <= 0;
          clock_seed_done <= '1';
        ELSE
          clock_seed_phase <= clock_seed_phase + 1;
        END IF;
      ELSIF ext_rd = '1' AND romc = ROMC_00 THEN
        IF ext_addr = x"003C" THEN clock_boot_ready <= '1'; END IF;
        IF rtc_clock_enable = '1' AND rtc_time_valid = '1' AND clock_seed_done = '0' AND
           (ext_addr = x"003C" OR (clock_boot_ready = '1' AND ext_addr = x"024D")) THEN
          clock_snapshot <= rtc_time;
          clock_seed_phase <= 1;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  clock_seed_we <= '1' WHEN clock_seed_phase /= 0 ELSE '0';
  PROCESS (ALL) IS
  BEGIN
    clock_ram_addr <= to_unsigned(16#3E1#, 10);
    clock_ram_data <= x"AA";
    clock_cpu_addr <= to_unsigned(22, 6);
    clock_cpu_data <= x"80";
    CASE clock_seed_phase IS
      WHEN 1 =>
        clock_ram_addr <= to_unsigned(16#3EC#, 10);
        clock_ram_data <= clock_snapshot(23 DOWNTO 16);
        clock_cpu_addr <= to_unsigned(21, 6);
        clock_cpu_data <= x"3C";
      WHEN 2 =>
        clock_ram_addr <= to_unsigned(16#3ED#, 10);
        IF clock_snapshot(55 DOWNTO 48) = 0 THEN clock_ram_data <= x"06";
        ELSE clock_ram_data <= clock_snapshot(55 DOWNTO 48) - 1; END IF;
        clock_cpu_addr <= to_unsigned(23, 6);
        clock_cpu_data <= clock_snapshot(7 DOWNTO 0);
      WHEN 3 =>
        clock_ram_addr <= to_unsigned(16#3EE#, 10);
        clock_ram_data <= clock_snapshot(31 DOWNTO 24);
        clock_cpu_addr <= to_unsigned(63, 6);
        clock_cpu_data <= clock_snapshot(15 DOWNTO 8);
      WHEN 4 =>
        clock_ram_addr <= to_unsigned(16#3EF#, 10);
        IF clock_snapshot(39 DOWNTO 32) = x"10" THEN clock_ram_data <= x"09";
        ELSE clock_ram_data <= clock_snapshot(39 DOWNTO 32) - 1; END IF;
      WHEN 5 =>
        clock_ram_addr <= to_unsigned(16#3F0#, 10);
        clock_ram_data <= clock_snapshot(47 DOWNTO 40);
      WHEN 6 =>
        clock_ram_addr <= to_unsigned(16#3F1#, 10);
        clock_ram_data <= x"20";
      WHEN OTHERS => NULL;
    END CASE;
  END PROCESS;

  u_cpu : ENTITY work.f8_cpu
    PORT MAP (
      dr       => cpu_dr,
      dw       => cpu_dw,
      dv       => OPEN,
      romc     => romc,
      tick     => tick,
      phase    => phase,
      po_a_n   => po_a_n_l,
      pi_a_n   => po_a_n_l,
      po_b_n   => po_b_n_l,
      pi_b_n   => pi_b_n_l,
      port1_wr  => port1_wr_l,
      clk      => clk,
      ce       => cpu_ce,
      power_cycle => power_cycle,
      clock_seed_we => clock_seed_we,
      clock_seed_addr => clock_cpu_addr,
      clock_seed_data => clock_cpu_data,
      reset_na => machine_reset_na,
      intreq   => int_req,
      acco     => OPEN,
      visaro   => OPEN,
      iozcso   => OPEN
      );

  u_busif : ENTITY work.f8_busif
    PORT MAP (
      dw        => cpu_dw,
      dr        => cpu_dr,
      dv        => OPEN,
      romc      => romc,
      tick      => tick,
      phase     => phase,
      clk       => clk,
      ce        => cpu_ce,
      reset_na  => machine_reset_na,
      ext_addr  => ext_addr,
      ext_rd    => ext_rd,
      ext_wr    => ext_wr,
      ext_wdata => ext_wdata,
      ext_rdata => ext_rdata,
      ext_req   => ext_req,
      ext_class => ext_class,
      ext_grant => ext_grant,
      io_addr    => io_addr,
      io_rd      => io_rd,
      io_wr      => io_wr,
      io_wdata   => io_wdata,
      io_rdata   => io_rdata,
      int_vector => int_vector,
      int_ack    => int_ack,
      pc0o      => pc0,
      pc1o      => pc1,
      dc0o      => dc0
      );

  io_rdata <= smi_rdata WHEN smi_sel = '1' ELSE (OTHERS => '1');

  -- u16.2 phi drives cpu u17.1
  -- ce advances half a phi period, held during bus waits
  smi_ce <= cpu_ce WHEN phase MOD 2 = 1 ELSE '0';

  u_smi : ENTITY work.f3853
    PORT MAP (
      clk        => clk,
      reset_na   => machine_reset_na,
      ce         => smi_ce,
      io_addr    => io_addr,
      io_rd      => io_rd,
      io_wr      => io_wr,
      io_wdata   => io_wdata,
      io_rdata   => smi_rdata,
      io_sel     => smi_sel,
      ext_int    => ext_int,
      int_req    => int_req,
      int_vector => int_vector,
      int_ack    => int_ack
      );

  u_yint : ENTITY work.uv201_yint
    PORT MAP (
      clk            => clk,
      reset_na       => machine_reset_na,
      cur_vpos       => uv_current_y,
      y_int          => uv_y_int_l,
      yint_ho        => uv_yint_ho_l,
      cmd_int        => uv_o_int_l,
      cmd_frz        => uv_o_frz_l,
      irq_level      => yint_irq
      );

  u_uv202 : ENTITY work.uv202_top
    GENERIC MAP (
      CLK_DIV_MCLK => CLK_DIV_MCLK,
      CPU_CLK_DIV  => CPU_CLK_DIV
      )
    PORT MAP (
      clk            => clk,
      reset_na       => machine_reset_na,
      timing_reset_na => timing_reset_na,
      cpu_req        => ext_req,
      progressive    => progressive,
      cpu_class      => ext_class,
      cpu_grant      => ext_grant,
      cpu_wack       => OPEN,
      cpu_stall      => OPEN,
      umireq0        => fetch_umireq,
      umireq1        => '0',
      dmareq0        => dmareq0,
      dmareq1        => OPEN,
      mclk_ena       => OPEN,
      brclk_ena      => brclk_ena_l,
      brclk_phase    => OPEN,
      cpu_ena_raw    => OPEN,
      cpu_ce         => cpu_ce_raw,
      hblank         => hblank_l,
      vblank         => vblank_l,
      burst          => burst,
      csync          => csync,
      scanline       => scanline,
      field          => field_l,
      hpos           => hpos_l,
      vpos           => vpos_l,
      line_start     => line_start_l,
      hblank_falling => OPEN,
      hblank_rising  => hblank_rising,
      busy           => OPEN
      );

  u_sys_bus : ENTITY work.sys_bus
    PORT MAP (
      clock_seed_we => clock_seed_we,
      clock_seed_addr => clock_ram_addr,
      clock_seed_data => clock_ram_data,
      power_cycle => power_cycle, power_busy => power_busy,
      clk            => clk,
      reset_na       => machine_reset_na,
      ext_addr       => ext_addr,
      ext_rd         => ext_rd,
      ext_fetch      => to_std_logic(romc = ROMC_00),
      ext_wr         => ext_wr,
      ext_wdata      => ext_wdata,
      ext_rdata      => ext_rdata,
      bb_addr        => bb_addr,
      bb_rdata       => bb_rdata,
      uv_cur_field   => field_l,
      uv_cur_vpos    => uv_current_y,
      uv_capture_stb => joy_capture_stb,
      uv_capture_x   => joy_capture_x,
      uv_capture_y   => joy_capture_y,
      uv_o_x_zm      => x_zoom_l,
      uv_o_frz       => uv_o_frz_l,
      uv_o_enb       => uv_o_enb,
      uv_o_int       => uv_o_int_l,
      uv_o_kbd       => uv_o_kbd_l,
      uv_o_y_zm      => y_zoom_l,
      uv_o_a_b       => uv_o_a_b,
      uv_o_yint_ho   => uv_yint_ho_l,
      uv_y_int       => uv_y_int_l,
      uv_final_mod   => final_mod_l,
      uv_background  => background_l,
      uv_obj_addr    => uv_obj_addr,
      uv_obj_rdata   => uv_obj_rdata,
      dl_addr        => dl_addr,
      dl_data        => dl_data,
      dl_wr          => dl_wr,
      dl_index       => dl_index,
      cart_unload    => cart_unload,
      cart_loaded    => cart_loaded,
      apl_hold       => OPEN,
      apl_paused     => apl_paused,
      apl_available  => apl_available,
      music_available => music_available,
      apl_load_error => apl_load_error,
      apl_symbols    => apl_symbols,
      apl_input_ready => apl_input_ready,
      apl_key_accepted => apl_key_accepted,
      joy_linear_base => joy_linear_base,
      joy_linear_step => joy_linear_step,
      unknown_cart_profile => unknown_cart_profile,
      infoman_printer_fix => infoman_printer_fix
      );

  u_io : ENTITY work.videobrain_io
    PORT MAP (
      clk          => clk,
      reset_na     => machine_reset_na,
      port_a_n     => po_a_n_l,
      port_b_n     => po_b_n_l,
      port_b_wr    => port1_wr_l,
      port_b_in_n  => kbd_b_in_n,
      kbd_matrix   => kbd_matrix,
      joy_fire     => joy_fire,
      uv_kbd       => uv_o_kbd_l,
      key_latch    => key_latch_l,
      joy_enable   => joy_enable_l,
      accessory_p5 => OPEN,
      accessory_p1 => OPEN,
      audio_code   => audio_code,
      audio_stb    => audio_stb
      );

  f8_po_a_n <= po_a_n_l;
  f8_po_b_n <= po_b_n_l;
  joy_enable <= joy_enable_l;

  -- f3850 reads pins including output latch drive
  pi_b_n_l <= po_b_n_l AND kbd_b_in_n AND
             unsigned'('1' & expander_clock_n & expander_data_n & "11111");

  PROCESS (clk, machine_reset_na) IS
  BEGIN
    IF machine_reset_na = '0' THEN
      modem_rxd_meta <= '1';
      modem_rxd_sync <= '1';
    ELSIF rising_edge(clk) THEN
      modem_rxd_meta <= expander_modem_rxd;
      modem_rxd_sync <= modem_rxd_meta;
    END IF;
  END PROCESS;

  u_expander1 : ENTITY work.expander1
    GENERIC MAP (CLK_DIV_MCLK => CLK_DIV_MCLK)
    PORT MAP (
      clk => clk, reset_na => machine_reset_na, power_cycle => power_cycle,
      host_data_n => po_b_n_l(5), host_clock_n => po_b_n_l(6),
      data_n => expander_data_n, interrupt_n => expander_interrupt_n,
      clock_n => expander_clock_n,
      record_data => expander_record_data, record_enable => expander_record_enable,
      playback_data => expander_playback_data, playback_enable => expander_playback_enable,
      modem_rxd => modem_rxd_sync, modem_txd => expander_modem_txd,
      printer_rxd => '1', printer_txd => expander_printer_txd,
      dl_addr => dl_addr, dl_data => dl_data, dl_wr => dl_wr,
      dl_index => dl_index
      );

  ext_int <= yint_irq OR joy_int OR NOT expander_interrupt_n;

  -- uv201 y advances on hblank rising edge
  uv_current_y <= vpos_l + 1 WHEN hpos_l >= HBLANK_START ELSE vpos_l;

  -- TODO: verify pot timing range on hardware
  -- 555 reset while ejoy disabled and hblank high
  PROCESS (clk, machine_reset_na) IS
    VARIABLE pot_v  : unsigned(7 DOWNTO 0);
    VARIABLE out_v  : std_logic;
    VARIABLE line_v : std_logic;
  BEGIN
    IF machine_reset_na = '0' THEN
      joy_timer <= (OTHERS => '0');
      joy_armed <= '1';
      joy_timer_active <= '0';
      joy_capture_stb <= '0';
      joy_capture_x <= (OTHERS => '0');
      joy_capture_y <= (OTHERS => '0');
      joy_out   <= '0';
      joy_line  <= '1';
      joy_int   <= '0';

    ELSIF rising_edge(clk) THEN
      out_v := joy_out;
      joy_capture_stb <= '0';

      IF joy_enable_l = '0' AND hblank_l = '1' THEN
        joy_armed <= '1';
        joy_timer_active <= '0';
        out_v := '0';
      ELSIF joy_armed = '1' THEN
        pot_v := (OTHERS => '0');
        FOR i IN 0 TO 7 LOOP
          IF key_latch_l(i) = '1' THEN
            pot_v := pot_v OR unsigned(joy_pots(i * 8 + 7 DOWNTO i * 8));
          END IF;
        END LOOP;
        IF joy_timer_curve = '1' THEN
          IF pot_v <= 128 THEN
            joy_timer <= to_unsigned(1620 + 23 * to_integer(pot_v), joy_timer'length);
          ELSE
            joy_timer <= to_unsigned(4564 + 53 * (to_integer(pot_v) - 128), joy_timer'length);
          END IF;
        ELSIF joy_timer_auto = '1' THEN
          joy_timer <= joy_linear_base + resize(pot_v * joy_linear_step, joy_timer'length);
        ELSE
          joy_timer <= joy_timer_base + resize(pot_v * joy_timer_step, joy_timer'length);
        END IF;
        joy_armed <= '0';
        joy_timer_active <= '1';
        out_v := '1';
      -- unplugged pots leave no capacitor charging path
      ELSIF joy_timer_active = '1' AND joy_connected = '1' THEN
        IF joy_timer = 0 THEN
          joy_timer_active <= '0';
          out_v := '0';
        ELSE
          joy_timer <= joy_timer - 1;
        END IF;
      END IF;

      line_v := NOT joy_enable_l OR out_v;
      -- ejoy and timer expiry both drive falling ext int edges
      IF joy_line = '1' AND line_v = '0' THEN
        joy_capture_x <= hpos_l;
        joy_capture_y <= vpos_l;
        joy_capture_stb <= '1';
      END IF;
      joy_int  <= joy_line AND NOT line_v;
      joy_out  <= out_v;
      joy_line <= line_v;
    END IF;
  END PROCESS;

  u_fetcher : ENTITY work.uv201_fetcher
    PORT MAP (
      clk           => clk,
      reset_na      => machine_reset_na,
      brclk_ena     => brclk_ena_l,
      line_start    => line_start_l,
      fifo_clear    => hblank_rising,
      vpos          => vpos_l,
      video_en      => uv_o_enb,
      list_a        => uv_o_a_b,
      x_zoom        => x_zoom_l,
      y_zoom        => y_zoom_l,
      obj_addr      => uv_obj_addr,
      obj_rdata     => uv_obj_rdata,
      bb_addr       => bb_addr,
      bb_rdata      => bb_rdata,
      umireq        => fetch_umireq,
      dmareq        => dmareq0,
      fifo_writable => fifo_writable,
      fifo_wr_en    => fifo_wr_en,
      fifo_wr_entry => fifo_wr_entry,
      busy          => OPEN
      );

  u_fifo : ENTITY work.uv201_fifo
    PORT MAP (
      clk           => clk,
      reset_na      => machine_reset_na,
      brclk_ena     => brclk_ena_l,
      hblank_rising => hblank_rising,
      wr_en         => fifo_wr_en,
      wr_entry      => fifo_wr_entry,
      writable      => fifo_writable,
      full          => OPEN,
      rd_pop        => fifo_pop_l,
      rd_valid      => fifo_valid_l,
      rd_entry      => fifo_entry_l,
      level         => fifo_level
      );

  u_render : ENTITY work.uv201_render
    PORT MAP (
      clk        => clk,
      reset_na   => machine_reset_na,
      timing_reset_na => timing_reset_na,
      brclk_ena  => brclk_ena_l,
      hblank     => hblank_l,
      vblank     => vblank_l,
      hpos       => hpos_l,
      vpos       => vpos_l,
      fifo_valid => fifo_valid_l,
      fifo_entry => fifo_entry_l,
      fifo_pop   => fifo_pop_l,
      final_mod  => std_logic_vector(final_mod_l),
      background => std_logic_vector(background_l),
      x_zoom     => x_zoom_l,
      video_en   => uv_o_enb,
      ce_pix     => ce_pix,
      idx        => vid_idx,
      r          => vid_r,
      g          => vid_g,
      b          => vid_b,
      de         => vid_de,
      hs         => vid_hs,
      vs         => vid_vs,
      hb         => vid_hb,
      vb         => vid_vb
      );

  hblank     <= hblank_l;
  vblank     <= vblank_l;
  hpos       <= hpos_l;
  final_mod  <= final_mod_l;
  background <= background_l;
  fifo_valid <= fifo_valid_l;

  field    <= field_l;
  vpos     <= vpos_l;
  video_en <= uv_o_enb;
  x_zoom   <= x_zoom_l;
  y_zoom   <= y_zoom_l;
  brclk_ena <= brclk_ena_l;

END ARCHITECTURE rtl;
