LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.env.ALL;
USE work.base_pack.ALL;
USE work.uv201_pack.ALL;

ENTITY tb_render IS
END ENTITY;

ARCHITECTURE test OF tb_render IS
  SIGNAL clk : std_logic := '0';
  SIGNAL reset_na, brclk_ena, hblank, vblank, fifo_valid : std_logic := '0';
  SIGNAL x_zoom, video_en : std_logic := '0';
  SIGNAL four_level_intensity : std_logic := '0';
  SIGNAL entry : uv201_fifo_entry_t := UV201_FIFO_ENTRY_ZERO;
  SIGNAL background, final_mod : std_logic_vector(7 DOWNTO 0) := x"00";
  SIGNAL idx : std_logic_vector(4 DOWNTO 0);
  SIGNAL r, g, b : uv8;
  SIGNAL ce_pix, de : std_logic;
BEGIN
  clk <= NOT clk AFTER 5 ns;
  dut : ENTITY work.uv201_render
    PORT MAP (clk => clk, reset_na => reset_na, brclk_ena => brclk_ena,
              hblank => hblank, vblank => vblank,
              hpos => to_unsigned(40, 8), vpos => to_unsigned(30, 9),
              fifo_valid => fifo_valid, fifo_entry => entry, fifo_pop => OPEN,
              final_mod => final_mod, background => background,
              four_level_intensity => four_level_intensity,
              x_zoom => x_zoom, video_en => video_en,
              ce_pix => ce_pix, idx => idx, r => r, g => g, b => b,
              de => de, hs => OPEN, vs => OPEN, hb => OPEN, vb => OPEN);

  PROCESS
    TYPE levels_t IS ARRAY(0 TO 3) OF natural;
    CONSTANT low_level : levels_t := (0, 64, 128, 192);
    CONSTANT high_level : levels_t := (160, 192, 224, 255);
    IMPURE FUNCTION channel(index, bit_number : natural) RETURN natural IS
      VARIABLE level : natural := index / 8;
    BEGIN
      IF four_level_intensity = '0' THEN level := (index / 16) * 3; END IF;
      IF (index / (2 ** bit_number)) MOD 2 = 1 THEN
        RETURN high_level(level);
      END IF;
      RETURN low_level(level);
    END FUNCTION;
    PROCEDURE tick IS
    BEGIN
      WAIT UNTIL rising_edge(clk);
      WAIT FOR 1 ns;
    END PROCEDURE;
    PROCEDURE pixel(expected : natural) IS
    BEGIN
      tick;
      ASSERT unsigned(idx) = expected REPORT "Wrong pixel index" SEVERITY failure;
      ASSERT r = channel(expected, 0) AND g = channel(expected, 1) AND
             b = channel(expected, 2) REPORT "Wrong pixel RGB" SEVERITY failure;
      ASSERT ce_pix = '1' AND de = '1' REPORT "Missing active pixel" SEVERITY failure;
    END PROCEDURE;
    VARIABLE bg, color : natural;
    CONSTANT pattern : unsigned(7 DOWNTO 0) := x"A5";
  BEGIN
    tick;
    reset_na <= '1';
    brclk_ena <= '1';
    video_en <= '1';
    FOR mode IN 0 TO 1 LOOP
      reset_na <= '0';
      tick;
      reset_na <= '1';
      fifo_valid <= '0';
      final_mod <= x"00";
      x_zoom <= '0';
      four_level_intensity <= to_std_logic(mode = 1);
      FOR code IN 0 TO 31 LOOP
        background <= std_logic_vector(to_unsigned(code, 8));
        pixel(code);
      END LOOP;
      FOR zoom IN 0 TO 1 LOOP
        x_zoom <= to_std_logic(zoom = 1);
        FOR modifier IN 0 TO 31 LOOP
          bg := (modifier + 9) MOD 32;
          color := (modifier + 17) MOD 32;
          background <= std_logic_vector(to_unsigned(bg, 8));
          final_mod <= std_logic_vector(to_unsigned(modifier, 8));
          fifo_valid <= '0';
          pixel(to_integer(to_unsigned(bg, 5) XOR to_unsigned(modifier, 5)));
          fifo_valid <= '1';
          entry <= (is_gap => '1', payload => x"03", color => "11111");
          pixel(to_integer(to_unsigned(bg, 5) XOR to_unsigned(modifier, 5)));
          fifo_valid <= '0';
          FOR gap IN 1 TO 2 LOOP
            pixel(to_integer(to_unsigned(bg, 5) XOR to_unsigned(modifier, 5)));
          END LOOP;
          fifo_valid <= '1';
          entry <= (is_gap => '0', payload => x"A5",
                    color => std_logic_vector(to_unsigned(color, 5)));
          FOR bit_num IN 7 DOWNTO 0 LOOP
            FOR copy IN 0 TO zoom LOOP
              IF pattern(bit_num) = '1' THEN
                pixel(to_integer(to_unsigned(color, 5) XOR to_unsigned(modifier, 5)));
              ELSE
                pixel(to_integer(to_unsigned(bg, 5) XOR to_unsigned(modifier, 5)));
              END IF;
              fifo_valid <= '0';
            END LOOP;
          END LOOP;
          pixel(to_integer(to_unsigned(bg, 5) XOR to_unsigned(modifier, 5)));
        END LOOP;
      END LOOP;
    END LOOP;
    final_mod <= x"1F";
    video_en <= '0';
    tick;
    ASSERT r = 0 AND g = 0 AND b = 0 REPORT "Video disable failed" SEVERITY failure;
    video_en <= '1';
    hblank <= '1';
    tick;
    ASSERT de = '0' AND r = 0 AND g = 0 AND b = 0 REPORT "HBLANK failed" SEVERITY failure;
    hblank <= '0';
    vblank <= '1';
    tick;
    ASSERT de = '0' AND r = 0 AND g = 0 AND b = 0 REPORT "VBLANK failed" SEVERITY failure;
    REPORT "Renderer test passed";
    stop;
    WAIT;
  END PROCESS;
END ARCHITECTURE;
