-------------------------------------------------------------------------------
-- tb_flags_unit.vhd
-- Self-checking testbench for flags_unit (shared Zero/Carry/Overflow/Parity).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity tb_flags_unit is
end entity tb_flags_unit;

architecture sim of tb_flags_unit is

    signal opcode          : opcode_t;
    signal operand_a       : std_logic_vector(15 downto 0);
    signal operand_b       : std_logic_vector(15 downto 0);
    signal adder_carry_out : std_logic;
    signal primary_result  : std_logic_vector(15 downto 0);
    signal extended_result : std_logic_vector(15 downto 0) := (others => '0');
    signal mult_range_ovf  : std_logic := '0';
    signal div_by_zero     : std_logic := '0';

    signal zero_flag, carry_flag, overflow_flag, parity_flag : std_logic;

    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

    procedure check_bit(
        signal   got  : in std_logic;
        constant exp  : in std_logic;
        constant msg  : in string;
        signal   pass_c : inout integer;
        signal   fail_c : inout integer
    ) is
    begin
        if got = exp then
            pass_c <= pass_c + 1;
        else
            fail_c <= fail_c + 1;
            report "FAIL: " & msg & "  got=" & std_logic'image(got) &
                   " expected=" & std_logic'image(exp) severity error;
        end if;
    end procedure;

begin

    dut : entity work.flags_unit
        port map (
            opcode          => opcode,
            operand_a       => operand_a,
            operand_b       => operand_b,
            adder_carry_out => adder_carry_out,
            primary_result  => primary_result,
            extended_result => extended_result,
            mult_range_ovf  => mult_range_ovf,
            div_by_zero     => div_by_zero,
            zero_flag       => zero_flag,
            carry_flag      => carry_flag,
            overflow_flag   => overflow_flag,
            parity_flag     => parity_flag
        );

    stim : process
    begin
        -- Zero flag: result all-zero -> zero_flag=1
        opcode <= OP_ADD; operand_a <= x"0005"; operand_b <= x"FFFB";
        primary_result <= x"0000"; adder_carry_out <= '1'; extended_result <= x"0000";
        wait for 10 ns;
        check_bit(zero_flag, '1', "Zero flag on zero result", pass_count, fail_count);

        -- Zero flag must consider extended_result too (32-bit MUL case)
        opcode <= OP_MUL; primary_result <= x"0000"; extended_result <= x"0001";
        mult_range_ovf <= '0'; wait for 10 ns;
        check_bit(zero_flag, '0', "Zero flag false when extended_result nonzero (MUL)", pass_count, fail_count);

        -- Parity: 0x0003 = 2 set bits -> even parity -> parity_flag=1
        opcode <= OP_AND; primary_result <= x"0003"; extended_result <= x"0000"; wait for 10 ns;
        check_bit(parity_flag, '1', "Parity even (2 bits set)", pass_count, fail_count);

        -- Parity: 0x0007 = 3 set bits -> odd -> parity_flag=0
        primary_result <= x"0007"; wait for 10 ns;
        check_bit(parity_flag, '0', "Parity odd (3 bits set)", pass_count, fail_count);

        -- ADD overflow: 0x7FFF + 0x0001 = 0x8000 (pos+pos=neg -> overflow=1)
        opcode <= OP_ADD; operand_a <= x"7FFF"; operand_b <= x"0001";
        primary_result <= x"8000"; adder_carry_out <= '0'; wait for 10 ns;
        check_bit(overflow_flag, '1', "ADD signed overflow pos+pos=neg", pass_count, fail_count);
        check_bit(carry_flag, '0', "ADD carry passthrough", pass_count, fail_count);

        -- ADD no overflow: 0x0001 + 0x0001 = 0x0002
        operand_a <= x"0001"; operand_b <= x"0001"; primary_result <= x"0002"; wait for 10 ns;
        check_bit(overflow_flag, '0', "ADD no overflow", pass_count, fail_count);

        -- SUB overflow: 0x8000 - 0x0001 = 0x7FFF (neg-pos=pos -> overflow=1)
        opcode <= OP_SUB; operand_a <= x"8000"; operand_b <= x"0001";
        primary_result <= x"7FFF"; wait for 10 ns;
        check_bit(overflow_flag, '1', "SUB signed overflow", pass_count, fail_count);

        -- MUL range overflow passthrough
        opcode <= OP_MUL; mult_range_ovf <= '1'; primary_result <= x"1234"; extended_result <= x"0001"; wait for 10 ns;
        check_bit(overflow_flag, '1', "MUL range overflow passthrough", pass_count, fail_count);
        check_bit(carry_flag, '1', "MUL carry mirrors range overflow", pass_count, fail_count);

        -- DIV by zero passthrough
        opcode <= OP_DIV; div_by_zero <= '1'; mult_range_ovf <= '0'; wait for 10 ns;
        check_bit(overflow_flag, '1', "DIV by zero -> overflow", pass_count, fail_count);
        check_bit(carry_flag, '1', "DIV by zero -> carry", pass_count, fail_count);

        -- Logic op: no carry/overflow regardless of operands
        opcode <= OP_XOR; div_by_zero <= '0'; primary_result <= x"00F0"; wait for 10 ns;
        check_bit(carry_flag, '0', "XOR carry always 0", pass_count, fail_count);
        check_bit(overflow_flag, '0', "XOR overflow always 0", pass_count, fail_count);

        wait for 10 ns;
        report "=================================================";
        report "flags_unit TB complete. PASS=" &
               integer'image(pass_count) & " FAIL=" & integer'image(fail_count);
        report "=================================================";
        if fail_count = 0 then
            report "*** ALL TESTS PASSED ***";
        else
            report "*** TESTS FAILED ***" severity error;
        end if;

        wait;
    end process;

end architecture sim;
