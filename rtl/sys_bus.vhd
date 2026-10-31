
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.uv202_pack.ALL;

ENTITY sys_bus IS
  PORT (
    clk      : IN  std_logic;
    reset_na : IN  std_logic;
    power_cycle : IN std_logic := '0';
    power_busy : OUT std_logic := '0';
    clock_seed_we : IN std_logic := '0';
    clock_seed_addr : IN unsigned(9 DOWNTO 0) := (OTHERS => '0');
    clock_seed_data : IN uv8 := (OTHERS => '0');

    ext_addr  : IN  unsigned(13 DOWNTO 0);
    ext_rd    : IN  std_logic;
    ext_fetch : IN  std_logic := '0';
    ext_wr    : IN  std_logic;
    ext_wdata : IN  uv8;
    ext_rdata : OUT uv8;

    bb_addr  : IN  unsigned(12 DOWNTO 0);
    bb_rdata : OUT uv8;

    uv_cur_field   : IN std_logic;
    uv_cur_vpos    : IN unsigned(8 DOWNTO 0);
    uv_capture_stb : IN std_logic;
    uv_capture_x   : IN uv8;
    uv_capture_y   : IN unsigned(8 DOWNTO 0);

    uv_o_x_zm   : OUT std_logic;
    uv_o_frz    : OUT std_logic;
    uv_o_enb    : OUT std_logic;
    uv_o_int    : OUT std_logic;
    uv_o_kbd    : OUT std_logic;
    uv_o_y_zm   : OUT std_logic;
    uv_o_a_b    : OUT std_logic;
    uv_o_yint_ho: OUT std_logic;
    uv_y_int    : OUT uv8;
    uv_final_mod : OUT uv8;
    uv_background: OUT uv8;

    uv_obj_addr  : IN  uv8;
    uv_obj_rdata : OUT uv8;

    dl_addr  : IN unsigned(15 DOWNTO 0);
    dl_data  : IN uv8;
    dl_wr    : IN std_logic;
    dl_index : IN uv8;
    cart_unload : IN std_logic := '0';
    cart_loaded : OUT std_logic := '0';
    apl_hold : OUT std_logic;
    apl_paused : IN std_logic := '0';
    apl_available : OUT std_logic;
    music_available : OUT std_logic;
    apl_load_error : OUT std_logic;
    apl_symbols : OUT std_logic := '0';
    apl_input_ready : OUT std_logic := '0';
    apl_key_accepted : OUT std_logic := '0';

    joy_linear_base : OUT unsigned(13 DOWNTO 0) := to_unsigned(2580, 14);
    joy_linear_step : OUT unsigned(6 DOWNTO 0) := to_unsigned(7, 7);
    unknown_cart_profile : IN uv8;
    infoman_printer_fix : IN std_logic := '0'
    );
END ENTITY sys_bus;

ARCHITECTURE rtl OF sys_bus IS

  FUNCTION crc32_byte(crc : uv32; data : uv8) RETURN uv32 IS
    VARIABLE c : uv32 := crc XOR resize(data, 32);
  BEGIN
    FOR i IN 0 TO 7 LOOP
      IF c(0) = '1' THEN
        c := shift_right(c, 1) XOR x"EDB88320";
      ELSE
        c := shift_right(c, 1);
      END IF;
    END LOOP;
    RETURN c;
  END FUNCTION;

  FUNCTION is_standard_cart(crc : uv32; size : unsigned) RETURN boolean IS
    CONSTANT hash : uv32 := NOT crc;
  BEGIN
    IF size = to_unsigned(16#0800#, size'length) THEN
      RETURN hash = CART_CRC_MUSICTEACHER1 OR
             hash = CART_CRC_WORDWISE1 OR
             hash = CART_CRC_WORDWISE2 OR
             hash = CART_CRC_VIDEOARTIST OR
             hash = CART_CRC_PINBALL OR
             hash = CART_CRC_BLACKJACK;
    ELSIF size = to_unsigned(16#1000#, size'length) THEN
      RETURN hash = CART_CRC_MATHTUTOR1 OR
             hash = CART_CRC_LEMONADE OR
             hash = CART_CRC_GLADIATOR OR
             hash = CART_CRC_TENNIS OR
             hash = CART_CRC_CHECKERS OR
             hash = CART_CRC_VICE_VERSA OR
             hash = CART_CRC_FINANCIER OR
             hash = CART_CRC_DEMONSTRATION;
    END IF;
    RETURN false;
  END FUNCTION;

  SIGNAL a_eff : unsigned(13 DOWNTO 0);
  SIGNAL bus_wr : std_logic;
  SIGNAL bus_wdata : uv8;

  TYPE rom_t IS ARRAY (0 TO 2047) OF uv8;
  SIGNAL res1_rom : rom_t := (OTHERS => (OTHERS => '0'));
  SIGNAL res2_rom : rom_t := (OTHERS => (OTHERS => '0'));

  -- apl uses seven 2k chips; the final 2k of its image is padding
  TYPE cart_t IS ARRAY (0 TO 16383) OF uv8;
  SIGNAL cart_rom : cart_t := (OTHERS => (OTHERS => '0'));
  SIGNAL cart_rom_we : std_logic;
  SIGNAL cart_rom_wa : unsigned(13 DOWNTO 0);
  SIGNAL cart_rom_wdata : uv8;

  TYPE printer_patch_byte_t IS RECORD
    address : natural RANGE 0 TO 16383;
    data : uv8;
  END RECORD;
  TYPE printer_patch_t IS ARRAY (natural RANGE <>) OF printer_patch_byte_t;
  -- infoman prototype: initialize printer rows and prime 300-baud serial idle
  CONSTANT INFOMAN_PRINTER_PATCH : printer_patch_t := (
    (16#16CA#, x"28"), (16#16CB#, x"17"), (16#16CC#, x"F8"),
    (16#16CD#, x"2B"), (16#16CE#, x"2B"),
    (16#07F8#, x"40"), (16#07F9#, x"2A"), (16#07FA#, x"0C"),
    (16#07FB#, x"28"), (16#07FC#, x"17"), (16#07FD#, x"29"),
    (16#07FE#, x"3F"), (16#07FF#, x"F9"),
    (16#1FF9#, x"70"), (16#1FFA#, x"2A"), (16#1FFB#, x"0F"),
    (16#1FFC#, x"DF"), (16#1FFD#, x"17"), (16#1FFE#, x"1C"),
    (16#1E31#, x"32"), (16#1E32#, x"94"), (16#1E33#, x"FE"),
    (16#1E34#, x"20"), (16#1E35#, x"20"), (16#1E36#, x"B1")
    );
  SIGNAL printer_patch_active : std_logic := '0';
  SIGNAL printer_patch_index : natural RANGE INFOMAN_PRINTER_PATCH'RANGE := 0;

  TYPE cart_ram_t IS ARRAY (0 TO 1023) OF uv8;
  SIGNAL cart_ram : cart_ram_t := (OTHERS => (OTHERS => '0'));
  SIGNAL cart_ram_a  : unsigned(9 DOWNTO 0);
  SIGNAL cart_ram_we : std_logic;
  SIGNAL cart_ram_rd : std_logic;

  TYPE exp_ram_t IS ARRAY (0 TO 4095) OF uv8;
  SIGNAL exp_ram : exp_ram_t := (OTHERS => (OTHERS => '0'));
  SIGNAL exp_ram_sel, exp_ram_we : std_logic;

  TYPE ram_t IS ARRAY (0 TO 1023) OF uv8;
  SIGNAL sys_ram : ram_t := (OTHERS => (OTHERS => '0'));
  SIGNAL sys_ram_we : std_logic;
  SIGNAL sys_ram_wa, cart_ram_wa : unsigned(9 DOWNTO 0);
  SIGNAL sys_ram_wdata, cart_ram_wdata : uv8;
  SIGNAL clear_active : std_logic := '0';
  SIGNAL clear_addr : unsigned(9 DOWNTO 0) := (OTHERS => '0');

  SIGNAL uv_reg_addr  : uv8;
  SIGNAL uv_reg_we    : std_logic;
  SIGNAL uv_reg_wdata : uv8;
  SIGNAL uv_reg_rdata : uv8;

  SIGNAL rdata_l : uv8;
  SIGNAL cart_cpu_rdata : uv8;
  SIGNAL cart_cpu_sel : std_logic;

  SIGNAL bb_res2_addr  : unsigned(10 DOWNTO 0);
  SIGNAL bb_res2_rdata : uv8;
  SIGNAL bb_ram_addr   : unsigned(9 DOWNTO 0);
  SIGNAL bb_ram_rdata  : uv8;
  SIGNAL bb_cart_addr  : unsigned(11 DOWNTO 0);
  SIGNAL bb_cart_rdata : uv8;
  SIGNAL bb_cart_rom_rdata : uv8;
  SIGNAL bb_cart_ram_rdata : uv8;
  SIGNAL bb_cart_ram_sel : std_logic;

  SIGNAL dl_res1, dl_res2, dl_cart : std_logic;
  SIGNAL cs1, cs2, exp : std_logic;
  SIGNAL cart_dl_prev : std_logic := '0';
  SIGNAL cart_loaded_l : std_logic := '0';
  SIGNAL cart_crc     : uv32 := (OTHERS => '1');
  SIGNAL cart_size    : unsigned(16 DOWNTO 0) := (OTHERS => '0');
  SIGNAL cart_auto_type : uv8 := to_unsigned(CART_UNRECOGNIZED, 8);
  SIGNAL cart_effective_type : uv8;
  SIGNAL music_input : std_logic;

  -- writes above 17ff distinguish larger carts from mirrored 2k images
  SIGNAL cart_big : std_logic := '0';
  SIGNAL cart_a   : unsigned(11 DOWNTO 0);
  SIGNAL cart_cpu_a : unsigned(13 DOWNTO 0);
  SIGNAL cart_bank : natural RANGE 0 TO 2 := 0;
  SIGNAL basic_bank : unsigned(2 DOWNTO 0) := (OTHERS => '0');
  SIGNAL bb_cart_rom_a : unsigned(13 DOWNTO 0);
  SIGNAL cart_exp_rom : std_logic;

BEGIN

  power_busy <= power_cycle OR clear_active;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF power_cycle = '1' THEN
        clear_active <= '1';
        clear_addr <= (OTHERS => '0');
      ELSIF clear_active = '1' THEN
        IF clear_addr = 1023 THEN
          clear_active <= '0';
        ELSE
          clear_addr <= clear_addr + 1;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  cart_loaded <= cart_loaded_l;
  apl_available <= '1' WHEN cart_auto_type = to_unsigned(CART_COMPLANG, 8) ELSE '0';
  music_available <= music_input;
  -- ed01 and the static-staff patches share the bank acceptance hook
  music_input <= '1' WHEN cart_loaded_l = '1' AND dl_cart = '0' AND
    cart_size = to_unsigned(2048, cart_size'length) AND
    (NOT cart_crc = CART_CRC_MUSICTEACHER1 OR NOT cart_crc = x"F4390144" OR
     NOT cart_crc = x"3BE4D855" OR NOT cart_crc = x"7A568961" OR
     NOT cart_crc = x"9E59066B" OR NOT cart_crc = x"7CFE495D" OR
     NOT cart_crc = x"99CC38F2" OR NOT cart_crc = x"6FD7A98B") ELSE '0';
  -- bank d input loop: release verified at 3c14, new key accepted at 3c20
  apl_key_accepted <= '1' WHEN reset_na = '1' AND
    ext_rd = '1' AND ext_fetch = '1' AND
    ((cart_auto_type = to_unsigned(CART_COMPLANG, 8) AND cart_bank = 0 AND
      ext_addr = x"3C20") OR (music_input = '1' AND ext_addr = x"1154")) ELSE '0';

  PROCESS (clk, reset_na) IS
  BEGIN
    IF reset_na = '0' THEN
      apl_input_ready <= '0';
    ELSIF rising_edge(clk) THEN
      IF dl_cart = '1' OR cart_unload = '1' THEN
        apl_input_ready <= '0';
      ELSIF music_input = '1' THEN
        IF ext_rd = '1' AND ext_fetch = '1' THEN
          IF ext_addr = x"14D8" OR ext_addr = x"158F" OR
             ((NOT cart_crc = x"7A568961" OR NOT cart_crc = x"9E59066B" OR
               NOT cart_crc = x"7CFE495D" OR NOT cart_crc = x"99CC38F2" OR
               NOT cart_crc = x"6FD7A98B") AND
              ext_addr = x"13B5") THEN
            apl_input_ready <= '1';
          ELSIF ext_addr = x"10A1" OR ext_addr = x"1154" OR
                ext_addr = x"14C8" OR ext_addr = x"14E4" OR
                ((NOT cart_crc = x"7A568961" OR NOT cart_crc = x"9E59066B" OR
                  NOT cart_crc = x"7CFE495D" OR NOT cart_crc = x"99CC38F2" OR
                  NOT cart_crc = x"6FD7A98B") AND
                 ext_addr = x"13C0") THEN
            apl_input_ready <= '0';
          END IF;
        END IF;
      ELSIF cart_auto_type /= to_unsigned(CART_COMPLANG, 8) THEN
        apl_input_ready <= '0';
      ELSIF cart_bank = 0 AND ext_rd = '1' AND ext_fetch = '1' THEN
        IF ext_addr = x"3C14" THEN
          apl_input_ready <= '1';
        ELSIF ext_addr = x"3C20" THEN
          apl_input_ready <= '0';
        END IF;
      END IF;
    END IF;
  END PROCESS;

  apl_load_error <= '0';
  apl_hold <= '0';
  a_eff <= cpu_addr_fold(ext_addr);
  bus_wr <= ext_wr;
  bus_wdata <= ext_wdata;
  cart_effective_type <= cart_auto_type
                         WHEN cart_auto_type /= to_unsigned(CART_UNRECOGNIZED, 8)
                         ELSE unknown_cart_profile;

  u_uv201_regs : ENTITY work.uv201_regs
    PORT MAP (
      clk         => clk,
      reset_na    => reset_na,
      reg_addr    => uv_reg_addr,
      reg_we      => uv_reg_we,
      reg_wdata   => uv_reg_wdata,
      reg_rdata   => uv_reg_rdata,
      cur_field   => uv_cur_field,
      cur_vpos    => uv_cur_vpos,
      capture_stb => uv_capture_stb,
      capture_x   => uv_capture_x,
      capture_y   => uv_capture_y,
      o_x_zm      => uv_o_x_zm,
      o_frz       => uv_o_frz,
      o_enb       => uv_o_enb,
      o_int       => uv_o_int,
      o_kbd       => uv_o_kbd,
      o_y_zm      => uv_o_y_zm,
      o_a_b       => uv_o_a_b,
      o_yint_ho   => uv_o_yint_ho,
      y_int       => uv_y_int,
      final_mod   => uv_final_mod,
      background  => uv_background,
      obj_addr    => uv_obj_addr,
      obj_rdata   => uv_obj_rdata
      );

  uv_reg_addr  <= a_eff(7 DOWNTO 0);
  uv_reg_we <= bus_wr WHEN a_eff >= to_unsigned(ADDR_UV201_LO, 14) AND
                               a_eff <= to_unsigned(ADDR_UV201_HI, 14) ELSE '0';
  uv_reg_wdata <= bus_wdata;

  sys_ram_we <= clock_seed_we OR (bus_wr AND
    to_std_logic(a_eff >= to_unsigned(ADDR_RAM_LO, 14) AND
                 a_eff <= to_unsigned(ADDR_RAM_HI, 14)));
  sys_ram_wa <= clock_seed_addr WHEN clock_seed_we = '1' ELSE a_eff(9 DOWNTO 0);
  sys_ram_wdata <= clock_seed_data WHEN clock_seed_we = '1' ELSE bus_wdata;

  PROCESS (clk, reset_na) IS
  BEGIN
    IF reset_na = '0' THEN
      apl_symbols <= '0';
    ELSIF rising_edge(clk) THEN
      IF sys_ram_we = '1' THEN
        IF sys_ram_wa = 16#3E2# THEN apl_symbols <= sys_ram_wdata(0); END IF;
      END IF;
    END IF;
  END PROCESS;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF clear_active = '1' THEN
        sys_ram(to_integer(clear_addr)) <= (OTHERS => '0');
      ELSIF reset_na = '1' AND sys_ram_we = '1' THEN
        sys_ram(to_integer(sys_ram_wa)) <= sys_ram_wdata;
      END IF;
    END IF;
  END PROCESS;

  -- arbiter waits cover synchronous block ram latency on rdata_l/ext_rdata

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      cart_cpu_sel <= '0';
      IF a_eff <= to_unsigned(ADDR_RES1_HI, 14) THEN
        rdata_l <= res1_rom(to_integer(a_eff));

      ELSIF a_eff <= to_unsigned(ADDR_UV201_HI, 14) THEN
        rdata_l <= uv_reg_rdata;

      ELSIF a_eff <= to_unsigned(ADDR_RAM_HI, 14) THEN
        rdata_l <= sys_ram(to_integer(a_eff - to_unsigned(ADDR_RAM_LO, 14)));

      ELSIF a_eff <= to_unsigned(ADDR_CART2_HI, 14) THEN
        IF cart_loaded_l = '0' THEN
          rdata_l <= (OTHERS => '1');
        ELSIF cart_ram_rd = '1' THEN
          rdata_l <= cart_ram(to_integer(cart_ram_a));
        ELSE
          cart_cpu_sel <= '1';
        END IF;

      ELSIF a_eff <= to_unsigned(ADDR_RES2_HI, 14) THEN
        rdata_l <= res2_rom(to_integer(a_eff - to_unsigned(ADDR_RES2_LO, 14)));

      ELSIF a_eff >= to_unsigned(ADDR_EXP_LO, 14) THEN
        IF exp_ram_sel = '1' THEN
          rdata_l <= exp_ram(to_integer(a_eff(11 DOWNTO 0)));
        ELSIF cart_ram_rd = '1' THEN
          rdata_l <= cart_ram(to_integer(cart_ram_a));
        ELSIF cart_exp_rom = '1' THEN
          cart_cpu_sel <= '1';
        ELSE
          rdata_l <= (OTHERS => '1');
        END IF;

      ELSE
        rdata_l <= (OTHERS => '1');
      END IF;
    END IF;
  END PROCESS;

  -- register rom reads before selection for block ram inference
  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      cart_cpu_rdata <= cart_rom(to_integer(cart_cpu_a));
      bb_cart_rom_rdata <= cart_rom(to_integer(bb_cart_rom_a));
    END IF;
  END PROCESS;

  bb_cart_rom_a <= basic_bank & bb_cart_addr(10 DOWNTO 0)
    WHEN cart_effective_type = CART_BASIC ELSE
    resize(bb_cart_addr AND (cart_big & "11111111111"), 14);

  ext_rdata <= cart_cpu_rdata WHEN cart_cpu_sel = '1' ELSE rdata_l;
  bb_cart_rdata <= (OTHERS => '1') WHEN cart_loaded_l = '0' ELSE
                  bb_cart_ram_rdata WHEN bb_cart_ram_sel = '1'
                  ELSE bb_cart_rom_rdata;

  -- one process per array for ghdl ram inference
  dl_res1 <= dl_wr WHEN dl_index = to_unsigned(0, 8) ELSE '0';
  dl_res2 <= dl_wr WHEN dl_index = to_unsigned(1, 8) ELSE '0';
  dl_cart <= dl_wr WHEN dl_index = to_unsigned(2, 8) ELSE '0';

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF dl_res1 = '1' THEN
        res1_rom(to_integer(dl_addr(10 DOWNTO 0))) <= dl_data;
      END IF;
    END IF;
  END PROCESS;

  cart_rom_we <= '0' WHEN cart_unload = '1' ELSE
                 dl_cart WHEN dl_index = to_unsigned(2, 8) ELSE printer_patch_active;
  cart_rom_wa <= dl_addr(13 DOWNTO 0) WHEN dl_index = to_unsigned(2, 8) ELSE
                 to_unsigned(INFOMAN_PRINTER_PATCH(printer_patch_index).address, 14);
  cart_rom_wdata <= dl_data WHEN dl_index = to_unsigned(2, 8) ELSE
                    INFOMAN_PRINTER_PATCH(printer_patch_index).data;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF cart_rom_we = '1' THEN
        cart_rom(to_integer(cart_rom_wa)) <= cart_rom_wdata;
      END IF;
    END IF;
  END PROCESS;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF cart_unload = '1' THEN
        cart_loaded_l <= '0';
        cart_dl_prev <= '0';
        cart_crc <= (OTHERS => '1');
        cart_size <= (OTHERS => '0');
        cart_auto_type <= to_unsigned(CART_UNRECOGNIZED, 8);
        joy_linear_base <= to_unsigned(2580, 14);
        joy_linear_step <= to_unsigned(7, 7);
      ELSIF dl_index = to_unsigned(2, 8) THEN
        cart_dl_prev <= '1';
        IF dl_wr = '1' THEN
          IF dl_addr = to_unsigned(0, 16) THEN
            cart_loaded_l <= '0';
            cart_crc <= crc32_byte((OTHERS => '1'), dl_data);
            cart_size <= to_unsigned(1, cart_size'length);
            cart_auto_type <= to_unsigned(CART_UNRECOGNIZED, 8);
            joy_linear_base <= to_unsigned(2580, 14);
            joy_linear_step <= to_unsigned(7, 7);
          ELSE
            cart_crc <= crc32_byte(cart_crc, dl_data);
            cart_size <= cart_size + 1;
          END IF;
        END IF;
      ELSIF cart_dl_prev = '1' THEN
        cart_dl_prev <= '0';
        IF cart_size /= 0 THEN cart_loaded_l <= '1'; END IF;
        -- tennis uses fixed scaling instead of the bios gain selection
        IF cart_size = to_unsigned(16#1000#, cart_size'length) AND
           (NOT cart_crc) = CART_CRC_TENNIS THEN
          joy_linear_base <= to_unsigned(2644, 14);
          joy_linear_step <= to_unsigned(24, 7);
        END IF;
        IF cart_size = to_unsigned(16#0800#, cart_size'length) AND
           (NOT cart_crc) = CART_CRC_TIMESHARE THEN
          cart_auto_type <= to_unsigned(CART_TIMESHARE, 8);
        ELSIF cart_size = to_unsigned(16#1000#, cart_size'length) AND
              (NOT cart_crc) = CART_CRC_MONEYMINDER THEN
          cart_auto_type <= to_unsigned(CART_MONEYMINDER, 8);
        ELSIF cart_size = to_unsigned(16#4000#, cart_size'length) AND
              (NOT cart_crc) = CART_CRC_COMPLANG THEN
          cart_auto_type <= to_unsigned(CART_COMPLANG, 8);
        ELSIF cart_size = to_unsigned(16#2000#, cart_size'length) AND
              (NOT cart_crc) = CART_CRC_INFOMAN THEN
          cart_auto_type <= to_unsigned(CART_INFOMAN, 8);
          IF infoman_printer_fix = '1' THEN cart_loaded_l <= '0'; END IF;
        ELSIF is_standard_cart(cart_crc, cart_size) THEN
          cart_auto_type <= to_unsigned(CART_STD, 8);
        END IF;
      ELSIF printer_patch_active = '1' AND
            printer_patch_index = INFOMAN_PRINTER_PATCH'high THEN
        cart_loaded_l <= '1';
      ELSE
        cart_dl_prev <= '0';
      END IF;
    END IF;
  END PROCESS;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF dl_res2 = '1' THEN
        res2_rom(to_integer(dl_addr(10 DOWNTO 0))) <= dl_data;
      END IF;
    END IF;
  END PROCESS;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF cart_unload = '1' THEN
        printer_patch_active <= '0';
        printer_patch_index <= 0;
      ELSIF dl_index = to_unsigned(2, 8) THEN
        printer_patch_active <= '0';
        printer_patch_index <= 0;
      ELSIF cart_dl_prev = '1' AND
            infoman_printer_fix = '1' AND
            cart_size = to_unsigned(16#2000#, cart_size'length) AND
            (NOT cart_crc) = CART_CRC_INFOMAN THEN
        printer_patch_active <= '1';
        printer_patch_index <= 0;
      ELSIF printer_patch_active = '1' THEN
        IF printer_patch_index = INFOMAN_PRINTER_PATCH'high THEN
          printer_patch_active <= '0';
        ELSE
          printer_patch_index <= printer_patch_index + 1;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF cart_unload = '1' THEN
        cart_big <= '0';
      ELSIF dl_cart = '1' THEN
        IF dl_addr(11) = '1' THEN
          cart_big <= '1';
        ELSIF dl_addr = x"0000" THEN
          cart_big <= '0';
        END IF;
      END IF;
    END IF;
  END PROCESS;

  cart_ram_we <= bus_wr AND cart_ram_rd;
  cart_ram_wa <= cart_ram_a;
  cart_ram_wdata <= bus_wdata;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF clear_active = '1' THEN
        cart_ram(to_integer(clear_addr)) <= (OTHERS => '0');
      ELSIF reset_na = '1' AND cart_ram_we = '1' THEN
        cart_ram(to_integer(cart_ram_wa)) <= cart_ram_wdata;
      END IF;
    END IF;
  END PROCESS;

  u_buffered_bus : ENTITY work.buffered_bus
    PORT MAP (
      bb_addr     => bb_addr,
      bb_rdata    => bb_rdata,
      res2_sel    => OPEN,
      res2_addr   => bb_res2_addr,
      res2_rdata  => bb_res2_rdata,
      ram_sel     => OPEN,
      ram_addr    => bb_ram_addr,
      ram_rdata   => bb_ram_rdata,
      cart_sel    => OPEN,
      cart_addr   => bb_cart_addr,
      cart_rdata  => bb_cart_rdata,
      open_bus    => OPEN
      );

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      bb_res2_rdata <= res2_rom(to_integer(bb_res2_addr));
      bb_ram_rdata  <= sys_ram(to_integer(bb_ram_addr));
      bb_cart_ram_rdata <= cart_ram(to_integer(bb_cart_addr(9 DOWNTO 0)));
      IF (cart_effective_type = CART_COMPLANG AND bb_cart_addr >= x"C00") OR
         (cart_effective_type = CART_INFOMAN AND bb_cart_addr(11) = '1') OR
         ((cart_effective_type = CART_TIMESHARE OR cart_effective_type = CART_BASIC) AND
          bb_cart_addr(11) = '1') THEN
        bb_cart_ram_sel <= '1';
      ELSE
        bb_cart_ram_sel <= '0';
      END IF;
    END IF;
  END PROCESS;

  -- /cs1: 1000-17ff, /cs2: 1800-1fff
  -- 3000-3fff has no chip select, only some mappers respond
  cs1 <= cart_loaded_l AND to_std_logic(a_eff >= to_unsigned(16#1000#, 14) AND
                      a_eff <= to_unsigned(16#17FF#, 14));
  cs2 <= cart_loaded_l AND to_std_logic(a_eff >= to_unsigned(16#1800#, 14) AND
                      a_eff <= to_unsigned(16#1FFF#, 14));
  exp <= cart_loaded_l AND to_std_logic(a_eff >= to_unsigned(ADDR_EXP_LO, 14));

  cart_a <= resize(a_eff(11 DOWNTO 0), 12) AND (cart_big & "11111111111");
  PROCESS (a_eff, cart_a, cart_effective_type, cs1, exp, cart_bank, basic_bank) IS
    VARIABLE chip : natural RANGE 0 TO 6;
  BEGIN
    cart_cpu_a <= resize(cart_a, 14);
    IF cart_effective_type = CART_BASIC THEN
      cart_cpu_a <= basic_bank & a_eff(10 DOWNTO 0);
    ELSIF cart_effective_type = CART_TIMESHARE OR cart_effective_type = CART_INFOMAN THEN
      IF cs1 = '1' THEN
        cart_cpu_a <= resize(a_eff(10 DOWNTO 0), 14);
      ELSIF exp = '1' AND cart_effective_type = CART_INFOMAN THEN
        cart_cpu_a <= '0' & '1' & a_eff(11 DOWNTO 0);
      END IF;
    ELSIF cart_effective_type = CART_COMPLANG AND exp = '1' THEN
      -- c/d, e/g, e/f are the three hardware bank pairs
      CASE cart_bank IS
        WHEN 0 => chip := 2 + to_integer(a_eff(11 DOWNTO 11));
        WHEN 1 =>
          IF a_eff(11) = '0' THEN chip := 4; ELSE chip := 6; END IF;
        WHEN 2 => chip := 4 + to_integer(a_eff(11 DOWNTO 11));
      END CASE;
      cart_cpu_a <= to_unsigned(chip * 2048, 14) OR resize(a_eff(10 DOWNTO 0), 14);
    END IF;
  END PROCESS;

  PROCESS (clk) IS
    TYPE bank_lut_t IS ARRAY (0 TO 3, 0 TO 3) OF natural RANGE 0 TO 2;
    CONSTANT bank_lut : bank_lut_t := ((0, 1, 2, 0), (2, 1, 2, 1),
                                      (0, 2, 2, 0), (2, 2, 2, 2));
  BEGIN
    IF rising_edge(clk) THEN
      IF cart_unload = '1' OR power_cycle = '1' THEN
        cart_bank <= 0;
      ELSIF dl_cart = '1' AND dl_addr = x"0000" THEN
        cart_bank <= 0;
      -- apl's rom bus conflict makes both data and address select the bank
      ELSIF reset_na = '1' AND ext_wr = '1' AND cs1 = '1' AND
            cart_effective_type = CART_COMPLANG THEN
        cart_bank <= bank_lut(to_integer(ext_wdata(1 DOWNTO 0)),
                             to_integer(a_eff(1 DOWNTO 0)));
      END IF;
    END IF;
  END PROCESS;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF reset_na = '0' OR cart_unload = '1' OR power_cycle = '1' OR
         (dl_cart = '1' AND dl_addr = x"0000") THEN
        basic_bank <= (OTHERS => '0');
      ELSIF ext_wr = '1' AND cart_loaded_l = '1' AND
            cart_effective_type = CART_BASIC AND a_eff = 16#17FF# THEN
        basic_bank <= ext_wdata(2 DOWNTO 0);
      END IF;
    END IF;
  END PROCESS;

  cart_exp_rom <= exp AND to_std_logic(cart_effective_type = CART_COMPLANG OR
                                      cart_effective_type = CART_INFOMAN);

  cart_ram_rd <= (cs2 AND to_std_logic(cart_effective_type = CART_TIMESHARE)) OR
                 (cs2 AND to_std_logic(cart_effective_type = CART_BASIC)) OR
                 (cs2 AND to_std_logic(cart_effective_type = CART_INFOMAN)) OR
                 (cs2 AND a_eff(10) AND to_std_logic(cart_effective_type = CART_COMPLANG)) OR
                 (exp AND a_eff(11) AND to_std_logic(cart_effective_type = CART_MONEYMINDER));
  cart_ram_a  <= a_eff(9 DOWNTO 0);

  exp_ram_sel <= exp AND
    to_std_logic(cart_effective_type = CART_EXP_RAM OR cart_effective_type = CART_BASIC);
  exp_ram_we <= bus_wr AND exp_ram_sel;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF reset_na = '1' AND exp_ram_we = '1' THEN
        exp_ram(to_integer(a_eff(11 DOWNTO 0))) <= bus_wdata;
      END IF;
    END IF;
  END PROCESS;

END ARCHITECTURE rtl;
