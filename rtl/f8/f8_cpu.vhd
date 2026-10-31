--------------------------------------------------------------------------------
-- Fairchild F8 F3850 CPU
--------------------------------------------------------------------------------
-- DO 8/2020
--------------------------------------------------------------------------------
-- SPDX-License-Identifier: MIT
--------------------------------------------------------------------------------
-- With help from MAME F8 model

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.f8_pack.ALL;

ENTITY f8_cpu IS
  PORT (
    dr     : IN  uv8;
    dw     : OUT uv8; -- data write / address
    dv     : OUT std_logic;
    
    romc   : OUT uv5;
    tick   : OUT std_logic;  -- 1/4 or 1/6 cycle
    phase  : OUT uint4;

    po_a_n : OUT uv8;
    pi_a_n : IN  uv8;
    po_b_n : OUT uv8;
    pi_b_n : IN  uv8;
    port1_wr : OUT std_logic;
    
    clk      : IN std_logic;
    ce       : IN std_logic;
    reset_na : IN std_logic;
    power_cycle : IN std_logic := '0';
    clock_seed_we : IN std_logic := '0';
    clock_seed_addr : IN unsigned(5 DOWNTO 0) := (OTHERS => '0');
    clock_seed_data : IN uv8 := (OTHERS => '0');

    intreq   : IN std_logic;
    acco     : OUT uv8;
    visaro   : OUT uv6;
    iozcso   : OUT uv5
    );
END ENTITY;

ARCHITECTURE rtl OF f8_cpu IS

  FUNCTION int_inhibited(op : uv8) RETURN boolean IS
  BEGIN
    RETURN op = x"0C" OR op = x"1B" OR op = x"1C" OR op = x"1D" OR
           op = x"27" OR op = x"28" OR op = x"29" OR
           (op >= x"B4" AND op <= x"BF");
  END FUNCTION;

  SIGNAL phase_l : uint4;
  SIGNAL interrupt_accept : std_logic;
  SIGNAL interrupt_cycle : std_logic := '0';

  SIGNAL madrs : uint11; -- 256 * 8 = 2048 microcode entries
  SIGNAL opcode : uv8;
  SIGNAL mop : type_microcode;
  SIGNAL acc : uv8;
  SIGNAL visar : uv6;
  ALIAS visarl : uv3 IS visar(2 DOWNTO 0);
  
  SIGNAL rs,rd : uint6;
  SIGNAL scratch_regs : arr_uv8(0 TO 63);
  SIGNAL sreg_ra,sreg_wa : uint6;
  SIGNAL sreg_rd,sreg_wd : uv8;
  SIGNAL sreg_wr : std_logic;
  SIGNAL clear_active : std_logic := '0';
  SIGNAL clear_addr : uint6 := 0;
  
  SIGNAL iozcs : uv5;
  
  SIGNAL op : enum_op;
  
  SIGNAL alu : uv8;
  SIGNAL test,bcc,testp,bccp,dstm : std_logic;

  SIGNAL txt : string(1 TO 12);
  
BEGIN

  phase<=phase_l;
  
  interrupt_accept <= '1' WHEN phase_l=1 AND mop.romc=ROMC_00 AND
                      intreq='1' AND iozcs(4)='1' AND NOT int_inhibited(opcode)
                      ELSE '0';

  romc<=ROMC_10 WHEN interrupt_accept='1' OR interrupt_cycle='1' ELSE
        ROMC_01 WHEN (bcc='1' AND test='1') OR
         (opcode=x"8F" AND visarl/=7 AND mop.romc=ROMC_03) ELSE
        ROMC_03 WHEN (bcc='1' AND test='0') OR
         (opcode=x"8F" AND visarl=7 AND mop.romc=ROMC_03) ELSE
         mop.romc;
  
  sreg_ra<=mop.rs WHEN mop.rs<16 ELSE
           mop.rd WHEN mop.rd<16 ELSE
           to_integer(visar);
  
  sreg_rd<=scratch_regs(sreg_ra) WHEN rising_edge(clk);

  PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF power_cycle='1' THEN
        clear_active <= '1';
        clear_addr <= 0;
      ELSIF clear_active='1' THEN
        scratch_regs(clear_addr) <= (OTHERS => '0');
        IF clear_addr=63 THEN
          clear_active <= '0';
        ELSE
          clear_addr <= clear_addr + 1;
        END IF;
      ELSIF reset_na='1' AND clock_seed_we='1' THEN
        IF clock_seed_addr=22 THEN
          -- Bit 6 enables the independently configured alarm.
          scratch_regs(22) <= clock_seed_data OR (scratch_regs(22) AND x"40");
        ELSE
          scratch_regs(to_integer(clock_seed_addr)) <= clock_seed_data;
        END IF;
      ELSIF reset_na='1' AND sreg_wr='1' THEN
        scratch_regs(sreg_wa)<=sreg_wd;
      END IF;
    END IF;
  END PROCESS;
  
  PROCESS(clk,reset_na) IS
    VARIABLE len_v : enum_len;
    VARIABLE rs1_v,rs2_v,rd_v : uv8;
    VARIABLE dstm_v,test_v : std_logic;
    VARIABLE iozcs_v : uv5;
  BEGIN  
    IF rising_edge(clk) THEN
      port1_wr <= '0';
      -- reset must work with ce low
      IF reset_na='0' THEN
        IF power_cycle='1' THEN
          acc <= (OTHERS => '0');
          visar <= (OTHERS => '0');
        END IF;
        opcode<=OP_RESET;
        txt<=OPTXT(to_integer(OP_RESET));
        madrs<=to_integer(OP_RESET)*8;
        mop<=MICROCODE(to_integer(OP_RESET)*8);
        phase_l<=0;
        interrupt_cycle<='0';
        iozcs<="00000";
        po_a_n<=x"FF";
        po_b_n<=x"FF";
        sreg_wr<='0';
        dv<='0';
        test<='0';
        testp<='0';
        bcc<='0';
        bccp<='0';
        dstm<='0';
      ELSIF ce='1' THEN
        mop<=MICROCODE(madrs);
        sreg_wr<='0';
        
        len_v:=mop.len;
        -- br7 lengthens only the operand cycle
        IF (bcc='1' AND test='1') OR
           (opcode=x"8F" AND visarl/=7 AND mop.romc=ROMC_03) THEN
          len_v:=L;
        ELSIF (bcc='1' AND test='0') OR
              (opcode=x"8F" AND visarl=7 AND mop.romc=ROMC_03) THEN
          len_v:=S;
        ELSE
          len_v:=mop.len;
        END IF;
        
        IF phase_l=7 AND len_v=S THEN
          phase_l<=0;
        ELSIF phase_l=11 AND len_v=L THEN
          phase_l<=0;
        ELSE
          phase_l<=phase_l+1;
        END IF;
        
        CASE phase_l IS
          WHEN 0 =>
            test<=testp;
            bcc<=bccp;
            interrupt_cycle <= '0';
            
          WHEN 1 =>
            -- replace fetch before bus read starts
            interrupt_cycle <= interrupt_accept;
          WHEN 2 =>
            NULL;
            
          WHEN 3 | 7 =>
            -- dc0 reads consume dr after the phase-6 bus latch
            IF (phase_l=3 AND mop.romc/=ROMC_02) OR
               (phase_l=7 AND mop.romc=ROMC_02) THEN
            CASE mop.rd IS
              WHEN RACC => rs1_v:=acc;
              WHEN R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 |
                   R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15 =>
                rs1_v:=sreg_rd;
              WHEN RISAR | RISARP | RISARM =>
                rs1_v:=sreg_rd;
              WHEN DATA =>
                rs1_v:=dr;
              WHEN OTHERS =>
                rs1_v:=acc;
            END CASE;
            CASE mop.rs IS
              WHEN PORT0 => rs2_v:=NOT pi_a_n;
              WHEN PORT1 => rs2_v:=NOT pi_b_n;
              WHEN RACC =>  rs2_v:=acc;
              WHEN R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 |
                   R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15 =>
                rs2_v:=sreg_rd;
              WHEN RISAR | RISARP | RISARM =>
                rs2_v:=sreg_rd;
              WHEN WREG =>
                rs2_v:="000" & iozcs;
              WHEN ISAR =>
                rs2_v:="00" & visar;
              WHEN DATA =>
                rs2_v:=dr;
              WHEN OTHERS =>
                rs2_v:=acc;
            END CASE;
            
            aluop(mop.op,opcode,rs1_v,rs2_v,iozcs,rd_v,dstm_v,iozcs_v,test_v);
            dstm<=dstm_v;
            iozcs<=iozcs_v;
            alu<=rd_v;
            testp<=test_v;
            bccp <=to_std_logic(mop.op=OP_TST8 OR mop.op=OP_TST9);
            END IF;
            
          WHEN 4 | 8 =>
            IF (phase_l=4 AND mop.romc/=ROMC_02) OR
               (phase_l=8 AND mop.romc=ROMC_02) THEN
            dv<='0';
            IF dstm='1' THEN
              CASE mop.rd IS
                WHEN RACC   => acc<=alu;
                WHEN PORT0  => po_a_n<= NOT alu;
                WHEN PORT1  =>
                  po_b_n<= NOT alu;
                  port1_wr <= '1';
                WHEN WREG   => iozcs<=alu(4 DOWNTO 0);
                WHEN ISARU  => visar(5 DOWNTO 3)<=alu(2 DOWNTO 0);
                WHEN ISARL  => visar(2 DOWNTO 0)<=alu(2 DOWNTO 0);
                WHEN ISAR   => visar<=alu(5 DOWNTO 0);
                WHEN R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 |
                     R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15 =>
                  sreg_wd<=alu;
                  sreg_wa<=mop.rd;
                  sreg_wr<='1';
                WHEN RISAR | RISARP | RISARM =>
                  sreg_wd<=alu;
                  sreg_wa<=to_integer(visar);
                  sreg_wr<='1';
                WHEN DATA =>
                  dw<=alu;
                  dv<='1';
                WHEN OTHERS => NULL;
              END CASE;
            END IF;
            END IF;
            
          WHEN 5 =>
            IF mop.rs=RISARP OR mop.rd=RISARP THEN
              visar(2 DOWNTO 0)<=visar(2 DOWNTO 0)+1;
            END IF;
            IF mop.rs=RISARM OR mop.rd=RISARM THEN
              visar(2 DOWNTO 0)<=visar(2 DOWNTO 0)-1;
            END IF;
            
          WHEN 11 =>
            IF len_v=L THEN
              IF mop.romc=ROMC_00 THEN
                IF interrupt_cycle='1' THEN
                  opcode<=OP_INTERRUPT;
                  txt<=OPTXT(to_integer(OP_INTERRUPT));
                  madrs<=to_integer(OP_INTERRUPT)*8;
                ELSE
                  opcode<=dr;
                  txt<=OPTXT(to_integer(dr));
                  madrs<=to_integer(dr)*8;
                END IF;
              ELSE
                madrs<=madrs+1;
              END IF;
            END IF;
            
          WHEN OTHERS =>
            NULL;

        END CASE;

        IF phase_l=7 AND len_v=S THEN
          IF mop.romc=ROMC_00 THEN
            IF interrupt_cycle='1' THEN
              opcode<=OP_INTERRUPT;
              txt<=OPTXT(to_integer(OP_INTERRUPT));
              madrs<=to_integer(OP_INTERRUPT)*8;
            ELSE
              opcode<=dr;
              txt<=OPTXT(to_integer(dr));
              madrs<=to_integer(dr)*8;
            END IF;
          ELSE
            madrs<=madrs+1;
          END IF;
        END IF;
        
        IF mop.romc=ROMC_13 AND phase_l=6 THEN
          iozcs(4)<='0';
        END IF;

        
      END IF;

    END IF;
  END PROCESS;

  acco<=acc;
  visaro<=visar;
  iozcso<=iozcs;
  
END ARCHITECTURE rtl;

