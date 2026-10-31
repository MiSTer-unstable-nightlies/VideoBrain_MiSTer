-- reference: kevtris "videobrain unwrapped" v0.05
-- mame src/mame/vidbrain/{vidbrain.cpp,uv201.cpp,uv201.h}

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

PACKAGE uv202_pack IS


  CONSTANT MCLK_HZ  : natural := 14_318_181;
  CONSTANT BRCLK_DIV : natural := 4;


  CONSTANT BRCLKS_PER_LINE   : natural := 228;

  CONSTANT CSYNC_WIDTH_NORM  : natural := 18;
  CONSTANT BURST_START       : natural := 21;
  CONSTANT BURST_WIDTH       : natural := 9;
  CONSTANT HBLANK_END        : natural := 33;
  CONSTANT HBLANK_START      : natural := 222;
  CONSTANT VISAREA_WIDTH     : natural := 189;

  CONSTANT EQ_PULSE_WIDTH    : natural := 9;
  CONSTANT EQ_PULSE2_START   : natural := 114;

  CONSTANT VSYNC_PULSE_WIDTH : natural := 18;
  CONSTANT VSYNC_PULSE1_START: natural := 105;
  CONSTANT VSYNC_PULSE2_START: natural := 219;

  CONSTANT LINES_ODD_FIELD   : natural := 263;
  CONSTANT LINES_EVEN_FIELD  : natural := 262;
  CONSTANT VSYNC_LINES       : natural := 3;
  CONSTANT EQ_LINES_PRE      : natural := 3;

  -- 14 cpu address lines, 4000-ffff mirrors 0000-3fff

  CONSTANT ADDR_RES1_LO   : natural := 16#0000#;
  CONSTANT ADDR_RES1_HI   : natural := 16#07FF#;

  CONSTANT ADDR_UV201_LO  : natural := 16#0800#;
  CONSTANT ADDR_UV201_HI  : natural := 16#0BFF#;

  CONSTANT ADDR_RAM_LO    : natural := 16#0C00#;
  CONSTANT ADDR_RAM_HI    : natural := 16#0FFF#;

  CONSTANT ADDR_CART2_LO  : natural := 16#1000#;
  CONSTANT ADDR_CART2_HI  : natural := 16#1FFF#;

  CONSTANT ADDR_RES2_LO   : natural := 16#2000#;
  CONSTANT ADDR_RES2_HI   : natural := 16#27FF#;

  CONSTANT ADDR_EXP_LO    : natural := 16#3000#;
  CONSTANT ADDR_EXP_HI    : natural := 16#3FFF#;

  CONSTANT CART_STD        : natural := 0;
  CONSTANT CART_TIMESHARE  : natural := 1;
  CONSTANT CART_MONEYMINDER: natural := 2;
  CONSTANT CART_COMPLANG   : natural := 3;
  CONSTANT CART_INFOMAN    : natural := 4;
  CONSTANT CART_EXP_RAM    : natural := 5;
  CONSTANT CART_BASIC      : natural := 6;
  CONSTANT CART_UNRECOGNIZED: natural := 255;

  -- crc-32 fingerprints from mame's hash/vidbrain.xml software list
  CONSTANT CART_CRC_MUSICTEACHER1 : uv32 := x"C8FEE8CD";
  CONSTANT CART_CRC_MATHTUTOR1    : uv32 := x"DB47F770";
  CONSTANT CART_CRC_WORDWISE1     : uv32 := x"D1546212";
  CONSTANT CART_CRC_WORDWISE2     : uv32 := x"4A08E999";
  CONSTANT CART_CRC_VIDEOARTIST   : uv32 := x"D68795F8";
  CONSTANT CART_CRC_LEMONADE      : uv32 := x"27C08D93";
  CONSTANT CART_CRC_GLADIATOR     : uv32 := x"E6A88A49";
  CONSTANT CART_CRC_PINBALL       : uv32 := x"484331FF";
  CONSTANT CART_CRC_TENNIS        : uv32 := x"1942F852";
  CONSTANT CART_CRC_CHECKERS      : uv32 := x"24C53410";
  CONSTANT CART_CRC_BLACKJACK     : uv32 := x"47F02B92";
  CONSTANT CART_CRC_VICE_VERSA    : uv32 := x"E23504EE";
  CONSTANT CART_CRC_TIMESHARE     : uv32 := x"957D7246";
  CONSTANT CART_CRC_MONEYMINDER   : uv32 := x"4F588081";
  CONSTANT CART_CRC_FINANCIER     : uv32 := x"721A4A14";
  CONSTANT CART_CRC_DEMONSTRATION : uv32 := x"A59EB765";
  CONSTANT CART_CRC_COMPLANG      : uv32 := x"9106CD4B";
  CONSTANT CART_CRC_INFOMAN       : uv32 := x"B5CB57CE";



  CONSTANT BBUS_RES2_LO   : natural := 16#0000#;
  CONSTANT BBUS_RES2_HI   : natural := 16#07FF#;
  CONSTANT BBUS_RAM_LO    : natural := 16#0C00#;
  CONSTANT BBUS_RAM_HI    : natural := 16#0FFF#;
  CONSTANT BBUS_CART_LO   : natural := 16#1000#;
  CONSTANT BBUS_CART_HI   : natural := 16#1FFF#;


  CONSTANT REG_RP_LO         : natural := 16#00#;
  CONSTANT REG_RP_HI_COLOR   : natural := 16#10#;
  CONSTANT REG_DX_INT_XCOPY  : natural := 16#20#;
  CONSTANT REG_DY            : natural := 16#30#;
  CONSTANT REG_X             : natural := 16#40#;
  CONSTANT REG_Y_LO_A        : natural := 16#50#;
  CONSTANT REG_Y_LO_B        : natural := 16#60#;
  CONSTANT REG_XY_HI_A       : natural := 16#70#;
  CONSTANT REG_XY_HI_B       : natural := 16#80#;

  CONSTANT REG_Y_INTERRUPT   : natural := 16#F0#;
  CONSTANT REG_FINAL_MOD     : natural := 16#F2#;
  CONSTANT REG_BACKGROUND    : natural := 16#F5#;
  CONSTANT REG_COMMAND       : natural := 16#F7#;

  CONSTANT REG_X_FREEZE      : natural := 16#F8#;
  CONSTANT REG_Y_FREEZE_LO   : natural := 16#F9#;
  CONSTANT REG_Y_FREEZE_HI   : natural := 16#FA#;
  CONSTANT REG_CURRENT_Y_LO  : natural := 16#FB#;

  CONSTANT CMD_X_ZM      : natural := 0;
  CONSTANT CMD_FRZ       : natural := 1;
  CONSTANT CMD_ENB       : natural := 2;
  CONSTANT CMD_INT       : natural := 3;
  CONSTANT CMD_KBD       : natural := 4;
  CONSTANT CMD_Y_ZM      : natural := 5;
  CONSTANT CMD_A_B       : natural := 6;
  CONSTANT CMD_YINT_HO   : natural := 7;


  TYPE bus_access_t IS (
    ACC_NONE,        -- idle or res1 (0000-07ff), the only zero-wait cpu region
    ACC_UV201_RD,
    ACC_UV201_WR,
    ACC_RAM_RD,
    ACC_RAM_WR,
    ACC_CART_RD,
    ACC_CART_WR,
    ACC_RES2,
    ACC_DMA0_RD,
    ACC_DMA1_RD
  );


  FUNCTION cpu_addr_fold(a : unsigned(13 DOWNTO 0)) RETURN unsigned;

  CONSTANT WAIT_SETUP_PENALTY   : natural := 1;
  CONSTANT WAIT_CPU_RDWR        : natural := 3;
  CONSTANT WAIT_DMA_BODY        : natural := 3;

  TYPE arr_uv8 IS ARRAY (natural RANGE <>) OF uv8;

END PACKAGE uv202_pack;

PACKAGE BODY uv202_pack IS

  -- a13 undecoded for uv201 and ram, mirrored at 2800-2fff
  -- cartridge expansion at 3000-3fff must not fold onto 1000-1fff
  FUNCTION cpu_addr_fold(a : unsigned(13 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    IF a >= to_unsigned(16#2800#, 14) AND a < to_unsigned(16#3000#, 14) THEN
      RETURN a - to_unsigned(16#2000#, 14);
    ELSE
      RETURN a;
    END IF;
  END FUNCTION;

END PACKAGE BODY uv202_pack;
