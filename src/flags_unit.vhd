-------------------------------------------------------------------------------
-- flags_unit.vhd
-- Entity: flags_unit
--
-- SHARED status-flag block. One instance serves BOTH the combinational path
-- (ADD/SUB/AND/OR/XOR/NOT/shifts/rotates) and the FSM path (MUL/DIV):
--   - Zero and Parity are computed generically from whichever result is
--     currently muxed onto primary_result/extended_result (wide reduction
--     trees that are identical regardless of which datapath produced the
--     result -- this is the actual resource-sharing rationale, not just
--     re-using an adder).
--   - Carry and Overflow have operation-specific meaning, so this block
--     selects the correct source internally based on opcode:
--       ADD/SUB : carry_out / signed-overflow from the adder
--       MUL     : "does the signed product exceed 16 bits" from Booth FSM
--       DIV     : divide-by-zero indicator from the restoring-division FSM
--       others  : '0'
--
-- primary_result   : 16-bit value the current operation's result sits on
--                     (comb result / Booth product_lo / division quotient)
-- extended_result  : upper 16 bits when the true result is wider than 16
--                     bits (Booth product_hi / division remainder). Tied to
--                     all-zero by the caller for ops where it doesn't apply,
--                     so it has no effect on the Zero flag in that case.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity flags_unit is
    port (
        opcode          : in  opcode_t;
        operand_a       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        operand_b       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        adder_carry_out : in  std_logic;  -- from combinational_alu, valid for ADD/SUB
        primary_result  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        extended_result : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        mult_range_ovf  : in  std_logic;  -- from booth_mult_fsm
        div_by_zero     : in  std_logic;  -- from restoring_div_fsm

        zero_flag       : out std_logic;
        carry_flag      : out std_logic;
        overflow_flag   : out std_logic;
        parity_flag     : out std_logic
    );
end entity flags_unit;

architecture rtl of flags_unit is
begin

    -- Zero flag: shared wide reduction tree, covers both 16-bit results
    -- (extended_result = 0 for those) and 32-bit-wide MUL/DIV results.
    zero_flag <= '1' when (primary_result = (primary_result'range => '0')) and
                          (extended_result = (extended_result'range => '0'))
                 else '0';

    -- Parity flag: even parity of primary_result (1 = even number of 1 bits),
    -- shared reduction tree regardless of which datapath produced the result.
    process (primary_result)
        variable p : std_logic;
    begin
        p := '0';
        for i in primary_result'range loop
            p := p xor primary_result(i);
        end loop;
        parity_flag <= not p;  -- '1' => even parity
    end process;

    -- Carry / Overflow: operation-specific source, selected by opcode.
    process (opcode, operand_a, operand_b, primary_result, adder_carry_out,
             mult_range_ovf, div_by_zero)
    begin
        carry_flag    <= '0';
        overflow_flag <= '0';

        case opcode is
            when OP_ADD =>
                carry_flag    <= adder_carry_out;
                overflow_flag <= (operand_a(15) xnor operand_b(15)) and
                                  (primary_result(15) xor operand_a(15));

            when OP_SUB =>
                carry_flag    <= adder_carry_out;  -- '1' = no borrow
                overflow_flag <= (operand_a(15) xor operand_b(15)) and
                                  (primary_result(15) xor operand_a(15));

            when OP_MUL =>
                carry_flag    <= mult_range_ovf;
                overflow_flag <= mult_range_ovf;

            when OP_DIV =>
                carry_flag    <= div_by_zero;
                overflow_flag <= div_by_zero;

            when others =>
                carry_flag    <= '0';
                overflow_flag <= '0';
        end case;
    end process;

end architecture rtl;
