-------------------------------------------------------------------------------
-- combinational_alu.vhd
-- Entity: combinational_alu
--
-- Purely combinational 16-bit ALU core. Handles ADD, SUB, AND, OR, XOR, NOT,
-- and shift/rotate operations. MUL and DIV are NOT handled here -- they are
-- routed to the FSM datapath (booth_mult_fsm / restoring_div_fsm) by alu_top.
--
-- carry_out is only meaningful for OP_ADD and OP_SUB (no-borrow convention
-- for subtraction: carry_out='1' means A >= B, i.e. no borrow occurred).
-- For all other opcodes carry_out is driven to '0'.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity combinational_alu is
    port (
        operand_a : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        operand_b : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        opcode    : in  opcode_t;
        result    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        carry_out : out std_logic
    );
end entity combinational_alu;

architecture rtl of combinational_alu is
begin

    process (operand_a, operand_b, opcode)
        variable add_ext   : unsigned(DATA_WIDTH downto 0);  -- 17-bit, for add/sub carry
        variable shamt     : integer range 0 to DATA_WIDTH-1;
        variable a_u, b_u  : unsigned(DATA_WIDTH-1 downto 0);
        variable a_s       : signed(DATA_WIDTH-1 downto 0);
        variable res_v     : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable cout_v    : std_logic;
    begin
        a_u    := unsigned(operand_a);
        b_u    := unsigned(operand_b);
        a_s    := signed(operand_a);
        shamt  := to_integer(unsigned(operand_b(3 downto 0)));  -- 0..15 shift amount
        res_v  := (others => '0');
        cout_v := '0';

        case opcode is
            when OP_ADD =>
                add_ext := ('0' & a_u) + ('0' & b_u);
                res_v   := std_logic_vector(add_ext(DATA_WIDTH-1 downto 0));
                cout_v  := add_ext(DATA_WIDTH);

            when OP_SUB =>
                -- A - B via two's complement: A + (NOT B) + 1
                add_ext := ('0' & a_u) + ('0' & unsigned(not operand_b)) + 1;
                res_v   := std_logic_vector(add_ext(DATA_WIDTH-1 downto 0));
                cout_v  := add_ext(DATA_WIDTH);  -- '1' = no borrow (A>=B), '0' = borrow

            when OP_AND =>
                res_v := operand_a and operand_b;

            when OP_OR =>
                res_v := operand_a or operand_b;

            when OP_XOR =>
                res_v := operand_a xor operand_b;

            when OP_NOT =>
                res_v := not operand_a;  -- unary, operand_b unused

            when OP_SHL =>
                res_v := std_logic_vector(shift_left(a_u, shamt));

            when OP_SHR =>
                res_v := std_logic_vector(shift_right(a_u, shamt));

            when OP_SAR =>
                res_v := std_logic_vector(shift_right(a_s, shamt));

            when OP_ROL =>
                res_v := std_logic_vector(rotate_left(a_u, shamt));

            when OP_ROR =>
                res_v := std_logic_vector(rotate_right(a_u, shamt));

            when others =>
                -- OP_MUL / OP_DIV / reserved: not handled combinationally
                res_v  := (others => '0');
                cout_v := '0';
        end case;

        result    <= res_v;
        carry_out <= cout_v;
    end process;

end architecture rtl;
