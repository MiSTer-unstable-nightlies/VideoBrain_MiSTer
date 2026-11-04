LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY cartridge_loader IS
  PORT (
    clk : IN std_logic;
    unload : IN std_logic;
    download : IN std_logic;
    wr : IN std_logic;
    addr : IN unsigned(15 DOWNTO 0);
    data : IN unsigned(7 DOWNTO 0);
    rom_wr : OUT std_logic;
    rom_addr : OUT unsigned(15 DOWNTO 0);
    valid : OUT std_logic;
    declared : OUT std_logic;
    profile : OUT unsigned(7 DOWNTO 0);
    joy_preset : OUT unsigned(7 DOWNTO 0)
  );
END ENTITY;

ARCHITECTURE rtl OF cartridge_loader IS
  TYPE state_t IS (probe, raw, riff_size, form, tag, length, payload, pad, done, bad);
  SIGNAL state : state_t := probe;
  SIGNAL active, container : std_logic := '0';
  SIGNAL count : natural RANGE 0 TO 81920 := 0;
  SIGNAL file_end : natural RANGE 0 TO 81920 := 0;
  SIGNAL pos, chunk_size : natural RANGE 0 TO 81920 := 0;
  SIGNAL word, chunk_id : unsigned(31 DOWNTO 0) := (OTHERS => '0');
  SIGNAL seen : unsigned(18 DOWNTO 0) := (OTHERS => '0');
  SIGNAL mapper, joystick : unsigned(7 DOWNTO 0) := (OTHERS => '0');
  SIGNAL checksum, expected_crc : unsigned(31 DOWNTO 0) := (OTHERS => '1');
  SIGNAL supp : unsigned(31 DOWNTO 0) := (OTHERS => '0');

  FUNCTION crc_byte(crc : unsigned; b : unsigned) RETURN unsigned IS
    VARIABLE c : unsigned(31 DOWNTO 0) := crc XOR resize(b, 32);
  BEGIN
    FOR i IN 0 TO 7 LOOP
      IF c(0) = '1' THEN c := shift_right(c, 1) XOR x"EDB88320";
      ELSE c := shift_right(c, 1); END IF;
    END LOOP;
    RETURN c;
  END FUNCTION;

  FUNCTION chunk_number(id : unsigned) RETURN integer IS
  BEGIN
    IF id = x"44414548" THEN RETURN 0; END IF; -- HEAD
    IF id = x"204D4F52" THEN RETURN 1; END IF; -- ROM
    IF id = x"53594F4A" THEN RETURN 2; END IF; -- JOYS
    IF id = x"50505553" THEN RETURN 3; END IF; -- SUPP
    IF id = x"20435243" THEN RETURN 4; END IF; -- CRC
    IF id = x"54415453" THEN RETURN 5; END IF; -- STAT
    IF id = x"45534142" THEN RETURN 6; END IF; -- BASE
    IF id = x"454D414E" THEN RETURN 7; END IF;
    IF id = x"48545541" THEN RETURN 8; END IF;
    IF id = x"4C425550" THEN RETURN 9; END IF;
    IF id = x"504D5544" THEN RETURN 10; END IF;
    IF id = x"45544144" THEN RETURN 11; END IF;
    IF id = x"54414444" THEN RETURN 12; END IF;
    IF id = x"53524556" THEN RETURN 13; END IF;
    IF id = x"45544F4E" THEN RETURN 14; END IF;
    IF id = x"454D414D" THEN RETURN 15; END IF;
    RETURN -1;
  END FUNCTION;
BEGIN
  rom_wr <= wr AND download WHEN unload = '0' AND
    ((active = '0') OR state = probe OR state = raw OR
     (state = payload AND chunk_id = x"204D4F52")) ELSE '0';
  rom_addr <= to_unsigned(pos MOD 65536, 16) WHEN active = '1' AND state = payload AND container = '1'
              ELSE addr;
  valid <= '1' WHEN (container = '0' AND count > 0 AND count <= 16384 AND
                    (state = probe OR state = raw)) OR
                   (container = '1' AND state = done AND count = file_end)
           ELSE '0';
  declared <= container;
  profile <= mapper;
  joy_preset <= joystick;

  PROCESS (clk) IS
    VARIABLE w : unsigned(31 DOWNTO 0);
    VARIABLE n : integer;
    VARIABLE size : natural;
    VARIABLE ok : boolean;
  BEGIN
    IF rising_edge(clk) THEN
      IF unload = '1' THEN
        active <= '0'; container <= '0'; count <= 0; state <= probe;
        mapper <= (OTHERS => '0'); joystick <= (OTHERS => '0');
      ELSIF download = '0' THEN
        active <= '0';
      ELSIF active = '0' AND wr = '0' THEN
        count <= 0; container <= '0'; state <= probe;
        mapper <= (OTHERS => '0'); joystick <= (OTHERS => '0');
      ELSIF wr = '1' THEN
        IF active = '0' THEN
          active <= '1'; container <= '0'; count <= 1; state <= probe;
          word <= resize(data, 32); seen <= (OTHERS => '0');
          mapper <= (OTHERS => '0'); joystick <= (OTHERS => '0');
          checksum <= (OTHERS => '1'); expected_crc <= (OTHERS => '1');
          IF addr /= 0 THEN state <= bad; END IF;
        ELSIF count = 81920 OR addr /= to_unsigned(count MOD 65536, 16) THEN
          state <= bad;
        ELSE
          count <= count + 1;
          w := word;
          CASE state IS
            WHEN probe =>
              w((count MOD 4)*8+7 DOWNTO (count MOD 4)*8) := data;
              word <= w;
              IF count = 3 THEN
                IF w = x"46464952" THEN
                  container <= '1'; state <= riff_size;
                ELSE state <= raw; END IF;
              END IF;
            WHEN raw =>
              IF count >= 16384 THEN state <= bad; END IF;
            WHEN riff_size | form | tag | length =>
              -- Chunk headers need not be aligned to four bytes.
              IF state = tag OR state = length THEN
                w((pos MOD 4)*8+7 DOWNTO (pos MOD 4)*8) := data;
                pos <= pos + 1;
              ELSE
                w((count MOD 4)*8+7 DOWNTO (count MOD 4)*8) := data;
              END IF;
              word <= w;
              IF ((state = riff_size OR state = form) AND count MOD 4 = 3) OR
                 ((state = tag OR state = length) AND pos MOD 4 = 3) THEN
                CASE state IS
                  WHEN riff_size =>
                    IF w < 52 OR w > 81912 THEN state <= bad;
                    ELSE file_end <= to_integer(w) + 8; state <= form; END IF;
                  WHEN form =>
                    IF w /= x"52434256" THEN state <= bad;
                    ELSE state <= tag; pos <= 0; END IF;
                  WHEN tag => chunk_id <= w; state <= length; pos <= 0;
                  WHEN length =>
                    ok := w <= 65536 AND count + 1 <= file_end;
                    size := 0;
                    IF ok THEN
                      size := to_integer(w);
                      ok := size + size MOD 2 <= file_end - count - 1;
                    END IF;
                    n := chunk_number(chunk_id);
                    IF n >= 0 THEN
                      IF seen(n) = '1' THEN ok := false; END IF;
                      seen(n) <= '1';
                    END IF;
                    IF seen(0) = '0' AND n /= 0 THEN ok := false; END IF;
                    CASE n IS
                      WHEN 0 => IF size /= 32 THEN ok := false; END IF;
                      WHEN 1 =>
                        IF count + 1 > 65536 OR count + 1 + size + size MOD 2 /= file_end THEN ok := false; END IF;
                        CASE to_integer(mapper) IS
                          WHEN 0 | 5 => ok := ok AND size >= 1 AND size <= 4096;
                          WHEN 1 => ok := ok AND size = 2048;
                          WHEN 2 => ok := ok AND size = 4096;
                          WHEN 3 | 6 => ok := ok AND size = 16384;
                          WHEN 4 => ok := ok AND size = 8192;
                          WHEN OTHERS => ok := false;
                        END CASE;
                      WHEN 2 | 4 | 5 => IF size /= 4 THEN ok := false; END IF;
                      WHEN 3 => IF size /= 8 THEN ok := false; END IF;
                      WHEN 6 => IF size /= 20 THEN ok := false; END IF;
                      WHEN OTHERS => NULL;
                    END CASE;
                    chunk_size <= size; pos <= 0;
                    IF NOT ok THEN state <= bad;
                    ELSIF size = 0 THEN state <= tag;
                    ELSE state <= payload; END IF;
                  WHEN OTHERS => NULL;
                END CASE;
              END IF;
            WHEN payload =>
              pos <= pos + 1;
              w((pos MOD 4)*8+7 DOWNTO (pos MOD 4)*8) := data;
              word <= w;
              IF pos + 1 = chunk_size THEN
                pos <= 0;
                IF chunk_id = x"204D4F52" THEN
                  IF chunk_size MOD 2 = 1 THEN state <= pad;
                  ELSE state <= done; END IF;
                  IF seen(4) = '1' AND NOT crc_byte(checksum, data) /= expected_crc THEN
                    state <= bad;
                  END IF;
                ELSIF chunk_size MOD 2 = 1 THEN state <= pad;
                ELSE state <= tag; END IF;
              END IF;
              CASE chunk_number(chunk_id) IS
                WHEN 0 =>
                  CASE pos IS
                    WHEN 0 | 6 => IF data /= 1 THEN state <= bad; END IF;
                    WHEN 1 | 2 | 3 | 5 | 7 | 28 | 29 | 30 | 31 =>
                      IF data /= 0 THEN state <= bad; END IF;
                    WHEN 4 =>
                      mapper <= data;
                      IF data > 6 THEN state <= bad; END IF;
                    WHEN 27 => IF w = 0 THEN state <= bad; END IF;
                    WHEN OTHERS => NULL;
                  END CASE;
                WHEN 1 => checksum <= crc_byte(checksum, data);
                WHEN 2 =>
                  IF pos = 2 THEN
                    joystick <= data;
                    IF data > 2 THEN state <= bad; END IF;
                  ELSIF (pos < 2 AND data > 15 AND data /= 255) OR (pos = 3 AND data /= 0) THEN
                    state <= bad;
                  END IF;
                WHEN 3 =>
                  IF pos = 3 THEN supp <= w; END IF;
                  IF pos = 7 AND (w AND NOT supp) /= 0 THEN state <= bad; END IF;
                WHEN 4 => IF pos = 3 THEN expected_crc <= w; END IF;
                WHEN 5 => IF pos = 3 AND w > 3 THEN state <= bad; END IF;
                WHEN OTHERS => NULL;
              END CASE;
            WHEN pad =>
              IF data /= 0 THEN state <= bad;
              ELSIF chunk_id = x"204D4F52" THEN state <= done;
              ELSE state <= tag; pos <= 0; END IF;
            WHEN done | bad => state <= bad;
          END CASE;
        END IF;
      END IF;
    END IF;
  END PROCESS;
END ARCHITECTURE;
