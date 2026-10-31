
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.uv201_pack.ALL;

ENTITY uv201_render IS
  PORT (
    clk      : IN std_logic;
    reset_na : IN std_logic;
    timing_reset_na : IN std_logic := '0';

    brclk_ena : IN std_logic;

    hblank : IN std_logic;
    vblank : IN std_logic;
    hpos   : IN unsigned(7 DOWNTO 0);
    vpos   : IN unsigned(8 DOWNTO 0);

    fifo_valid : IN  std_logic;
    fifo_entry : IN  uv201_fifo_entry_t;
    fifo_pop   : OUT std_logic;

    final_mod  : IN std_logic_vector(7 DOWNTO 0);
    background : IN std_logic_vector(7 DOWNTO 0);
    x_zoom     : IN std_logic;
    video_en   : IN std_logic;

    ce_pix : OUT std_logic;
    idx    : OUT std_logic_vector(4 DOWNTO 0);
    r      : OUT unsigned(7 DOWNTO 0);
    g      : OUT unsigned(7 DOWNTO 0);
    b      : OUT unsigned(7 DOWNTO 0);
    de     : OUT std_logic;
    hs     : OUT std_logic;
    vs     : OUT std_logic;
    hb     : OUT std_logic;
    vb     : OUT std_logic
    );
END ENTITY uv201_render;

ARCHITECTURE rtl OF uv201_render IS

  SIGNAL shift_reg    : uv8 := (OTHERS => '0');
  SIGNAL shift_cnt    : natural RANGE 0 TO 7 := 0;
  SIGNAL shift_color  : std_logic_vector(4 DOWNTO 0) := (OTHERS => '0');
  SIGNAL shift_active : std_logic := '0';
  SIGNAL gap_cnt      : uv8 := (OTHERS => '0');
  SIGNAL dbl          : std_logic := '0';

  SIGNAL active     : std_logic;
  SIGNAL need_entry : std_logic;
  SIGNAL fresh_data : std_logic;
  SIGNAL in_object  : std_logic;
  SIGNAL obj_bit    : std_logic;
  SIGNAL obj_color  : std_logic_vector(4 DOWNTO 0);
  SIGNAL idx_c      : std_logic_vector(4 DOWNTO 0);
  SIGNAL obj_idx    : std_logic_vector(4 DOWNTO 0);

  SIGNAL off_l, on_l : uv8;
  SIGNAL r_c, g_c, b_c : uv8;
  SIGNAL show        : std_logic;

  SIGNAL ce_pix_l : std_logic := '0';
  SIGNAL idx_l    : std_logic_vector(4 DOWNTO 0) := (OTHERS => '0');
  SIGNAL r_l, g_l, b_l : uv8 := (OTHERS => '0');
  SIGNAL de_l : std_logic := '0';
  SIGNAL hs_l, vs_l, hb_l, vb_l : std_logic := '1';
  SIGNAL timing_live : std_logic;

BEGIN

  timing_live <= reset_na OR timing_reset_na;

  -- MiSTer must keep receiving pixels and sync while the machine resets.
  PROCESS (clk, timing_live) IS
  BEGIN
    IF timing_live = '0' THEN
      ce_pix_l <= '0';
      de_l <= '0';
      hb_l <= '1';
      vb_l <= '1';
      hs_l <= '1';
      vs_l <= '1';
    ELSIF rising_edge(clk) THEN
      ce_pix_l <= brclk_ena;
      IF brclk_ena = '1' THEN
        de_l <= active AND reset_na;
        hb_l <= hblank;
        vb_l <= vblank;
        hs_l <= to_std_logic(hpos < 18);
        vs_l <= to_std_logic(vpos < 3);
      END IF;
    END IF;
  END PROCESS;

  active     <= NOT hblank AND NOT vblank;
  need_entry <= active AND NOT shift_active AND
                to_std_logic(gap_cnt = 0) AND fifo_valid;

  fifo_pop <= need_entry AND brclk_ena;

  PROCESS (clk, reset_na) IS
  BEGIN
    IF reset_na = '0' THEN
      shift_active <= '0';
      shift_cnt    <= 0;
      gap_cnt      <= (OTHERS => '0');
      dbl          <= '0';
      idx_l <= (OTHERS => '0');
      r_l <= (OTHERS => '0');
      g_l <= (OTHERS => '0');
      b_l <= (OTHERS => '0');

    ELSIF rising_edge(clk) THEN
      IF brclk_ena = '1' THEN
        IF active = '0' THEN
          shift_active <= '0';
          shift_cnt    <= 0;
          gap_cnt      <= (OTHERS => '0');
          dbl          <= '0';

        ELSIF shift_active = '1' THEN
          IF x_zoom = '1' AND dbl = '0' THEN
            dbl <= '1';
          ELSE
            dbl <= '0';
            shift_reg <= shift_reg(6 DOWNTO 0) & '0';
            IF shift_cnt = 0 THEN
              shift_active <= '0';
            ELSE
              shift_cnt <= shift_cnt - 1;
            END IF;
          END IF;

        ELSIF gap_cnt /= 0 THEN
          gap_cnt <= gap_cnt - 1;

        ELSIF fifo_valid = '1' THEN
          IF fifo_entry.is_gap = '1' THEN
            IF fifo_entry.payload = 0 THEN
              gap_cnt <= (OTHERS => '0');
            ELSE
              gap_cnt <= fifo_entry.payload - 1;
            END IF;
          ELSE
            shift_color  <= fifo_entry.color;
            shift_active <= '1';
            IF x_zoom = '1' THEN
              -- shift after bit 7 has appeared twice
              shift_reg <= fifo_entry.payload;
              shift_cnt <= 7;
              dbl       <= '1';
            ELSE
              shift_reg <= fifo_entry.payload(6 DOWNTO 0) & '0';
              shift_cnt <= 6;
              dbl       <= '0';
            END IF;
          END IF;
        END IF;

        idx_l <= idx_c;
        IF show = '1' THEN
          r_l <= r_c;
          g_l <= g_c;
          b_l <= b_c;
        ELSE
          r_l <= (OTHERS => '0');
          g_l <= (OTHERS => '0');
          b_l <= (OTHERS => '0');
        END IF;
      END IF;
    END IF;
  END PROCESS;

  fresh_data <= (NOT shift_active) AND to_std_logic(gap_cnt = 0) AND
                fifo_valid AND (NOT fifo_entry.is_gap);
  in_object  <= shift_active OR fresh_data;
  obj_bit    <= shift_reg(7) WHEN shift_active = '1' ELSE fifo_entry.payload(7);
  obj_color  <= shift_color  WHEN shift_active = '1' ELSE fifo_entry.color;

  obj_idx <= obj_color WHEN in_object = '1' AND obj_bit = '1'
             ELSE background(4 DOWNTO 0);
  idx_c   <= obj_idx XOR final_mod(4 DOWNTO 0);

  off_l <= x"C0" WHEN idx_c(4) = '1' ELSE x"00";
  on_l  <= x"FF" WHEN idx_c(4) = '1' ELSE x"A0";

  r_c <= on_l WHEN idx_c(0) = '1' ELSE off_l;
  g_c <= on_l WHEN idx_c(1) = '1' ELSE off_l;
  b_c <= on_l WHEN idx_c(2) = '1' ELSE off_l;

  show <= active AND video_en;

  ce_pix <= ce_pix_l;
  idx    <= idx_l;
  r      <= r_l;
  g      <= g_l;
  b      <= b_l;
  de     <= de_l;
  hs     <= hs_l;
  vs     <= vs_l;
  hb     <= hb_l;
  vb     <= vb_l;

END ARCHITECTURE rtl;
