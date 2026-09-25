-------------------------------------------------------------------------------
-- tb_combinational_alu.vhd
-- Self-checking testbench for combinational_alu.
-- Applies known operand/opcode pairs, compares against hand-computed
-- expected values, and asserts. Reports PASS/FAIL count at the end.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity tb_combinational_alu is
end entity tb_combinational_alu;

architecture sim of tb_combinational_alu is

    signal operand_a : std_logic_vector(15 downto 0);
    signal operand_b : std_logic_vector(15 downto 0);
    signal opcode    : opcode_t;
    signal result    : std_logic_vector(15 downto 0);
    signal carry_out : std_logic;

    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

    -- Local hex formatter (avoids relying on VHDL-2008-only to_hstring,
    -- keeps this TB analyzable under the same --std as the synthesizable RTL)
    function slv_to_hex(v : std_logic_vector) return string is
        constant hexchars : string(1 to 16) := "0123456789ABCDEF";
        variable result_str : string(1 to (v'length+3)/4);
        variable nibble : std_logic_vector(3 downto 0);
        variable padded : std_logic_vector(((v'length+3)/4)*4 - 1 downto 0) := (others => '0');
    begin
        padded(v'length-1 downto 0) := v;
        for i in result_str'range loop
            nibble := padded((result_str'length-i+1)*4 - 1 downto (result_str'length-i)*4);
            result_str(i) := hexchars(to_integer(unsigned(nibble)) + 1);
        end loop;
        return result_str;
    end function;

    procedure check(
        signal   result_sig : in std_logic_vector(15 downto 0);
        signal   carry_sig  : in std_logic;
        constant exp_result : in std_logic_vector(15 downto 0);
        constant exp_carry  : in std_logic;
        constant check_carry: in boolean;
        constant msg        : in string;
        signal   pass_c     : inout integer;
        signal   fail_c     : inout integer
    ) is
    begin
        if result_sig = exp_result and (not check_carry or carry_sig = exp_carry) then
            pass_c <= pass_c + 1;
        else
            fail_c <= fail_c + 1;
            report "FAIL: " & msg &
                   "  got result=0x" & slv_to_hex(result_sig) &
                   " carry=" & std_logic'image(carry_sig) &
                   "  expected result=0x" & slv_to_hex(exp_result) &
                   " carry=" & std_logic'image(exp_carry)
                severity error;
        end if;
    end procedure;

begin

    dut : entity work.combinational_alu
        port map (
            operand_a => operand_a,
            operand_b => operand_b,
            opcode    => opcode,
            result    => result,
            carry_out => carry_out
        );

    stim : process
    begin
        -- ADD: 5 + 3 = 8, no carry
        operand_a <= x"0005"; operand_b <= x"0003"; opcode <= OP_ADD; wait for 10 ns;
        check(result, carry_out, x"0008", '0', true, "ADD 5+3", pass_count, fail_count);

        -- ADD with carry out: 0xFFFF + 0x0001 = 0x0000, carry=1
        operand_a <= x"FFFF"; operand_b <= x"0001"; opcode <= OP_ADD; wait for 10 ns;
        check(result, carry_out, x"0000", '1', true, "ADD overflow wrap", pass_count, fail_count);

        -- SUB: 10 - 3 = 7, no borrow -> carry_out = 1
        operand_a <= x"000A"; operand_b <= x"0003"; opcode <= OP_SUB; wait for 10 ns;
        check(result, carry_out, x"0007", '1', true, "SUB 10-3", pass_count, fail_count);

        -- SUB with borrow: 3 - 10 = -7 (0xFFF9), borrow -> carry_out = 0
        operand_a <= x"0003"; operand_b <= x"000A"; opcode <= OP_SUB; wait for 10 ns;
        check(result, carry_out, x"FFF9", '0', true, "SUB borrow 3-10", pass_count, fail_count);

        -- AND
        operand_a <= x"F0F0"; operand_b <= x"0FF0"; opcode <= OP_AND; wait for 10 ns;
        check(result, carry_out, x"00F0", '0', false, "AND", pass_count, fail_count);

        -- OR
        operand_a <= x"F0F0"; operand_b <= x"0F0F"; opcode <= OP_OR; wait for 10 ns;
        check(result, carry_out, x"FFFF", '0', false, "OR", pass_count, fail_count);

        -- XOR
        operand_a <= x"FF00"; operand_b <= x"0FF0"; opcode <= OP_XOR; wait for 10 ns;
        check(result, carry_out, x"F0F0", '0', false, "XOR", pass_count, fail_count);

        -- NOT (unary, operand_a only)
        operand_a <= x"0F0F"; operand_b <= x"0000"; opcode <= OP_NOT; wait for 10 ns;
        check(result, carry_out, x"F0F0", '0', false, "NOT", pass_count, fail_count);

        -- SHL: 0x0001 << 4 = 0x0010  (shift amount from operand_b(3:0))
        operand_a <= x"0001"; operand_b <= x"0004"; opcode <= OP_SHL; wait for 10 ns;
        check(result, carry_out, x"0010", '0', false, "SHL by 4", pass_count, fail_count);

        -- SHR (logical): 0x8000 >> 4 = 0x0800
        operand_a <= x"8000"; operand_b <= x"0004"; opcode <= OP_SHR; wait for 10 ns;
        check(result, carry_out, x"0800", '0', false, "SHR by 4", pass_count, fail_count);

        -- SAR (arithmetic): 0x8000 (negative) >> 4 = 0xF800 (sign-extended)
        operand_a <= x"8000"; operand_b <= x"0004"; opcode <= OP_SAR; wait for 10 ns;
        check(result, carry_out, x"F800", '0', false, "SAR by 4 (negative)", pass_count, fail_count);

        -- SAR on positive number: 0x4000 >> 4 = 0x0400
        operand_a <= x"4000"; operand_b <= x"0004"; opcode <= OP_SAR; wait for 10 ns;
        check(result, carry_out, x"0400", '0', false, "SAR by 4 (positive)", pass_count, fail_count);

        -- ROL: 0x8001 rotate left by 1 = 0x0003
        operand_a <= x"8001"; operand_b <= x"0001"; opcode <= OP_ROL; wait for 10 ns;
        check(result, carry_out, x"0003", '0', false, "ROL by 1", pass_count, fail_count);

        -- ROR: 0x0003 rotate right by 1 = 0x8001
        operand_a <= x"0003"; operand_b <= x"0001"; opcode <= OP_ROR; wait for 10 ns;
        check(result, carry_out, x"8001", '0', false, "ROR by 1", pass_count, fail_count);

        -- shift by 0 should be identity
        operand_a <= x"1234"; operand_b <= x"0000"; opcode <= OP_SHL; wait for 10 ns;
        check(result, carry_out, x"1234", '0', false, "SHL by 0 (identity)", pass_count, fail_count);

        wait for 10 ns;
        report "=================================================";
        report "combinational_alu TB complete. PASS=" &
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
