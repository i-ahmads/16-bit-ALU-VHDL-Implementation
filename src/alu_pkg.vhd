-------------------------------------------------------------------------------
-- alu_pkg.vhd
-- Package: alu_pkg
-- Shared opcode constants and types for the 16-bit ALU project.
-- VHDL-93/2002 synthesizable subset. Target: Xilinx ISE/XST, verified in GHDL.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package alu_pkg is

    -- Data widths
    constant DATA_WIDTH : integer := 16;

    -- 4-bit opcode field (opcode(3:0))
    subtype opcode_t is std_logic_vector(3 downto 0);

    -- Combinational operations
    constant OP_ADD  : opcode_t := "0000";
    constant OP_SUB  : opcode_t := "0001";
    constant OP_AND  : opcode_t := "0010";
    constant OP_OR   : opcode_t := "0011";
    constant OP_XOR  : opcode_t := "0100";
    constant OP_NOT  : opcode_t := "0101";  -- unary, operand A only
    constant OP_SHL  : opcode_t := "0110";  -- logical shift left
    constant OP_SHR  : opcode_t := "0111";  -- logical shift right
    constant OP_SAR  : opcode_t := "1000";  -- arithmetic shift right
    constant OP_ROL  : opcode_t := "1001";  -- rotate left
    constant OP_ROR  : opcode_t := "1010";  -- rotate right

    -- FSM-controlled operations (Tier 1)
    constant OP_MUL  : opcode_t := "1011";  -- radix-4 Booth, signed
    constant OP_DIV  : opcode_t := "1100";  -- restoring division, unsigned

    -- "1101".."1111" reserved / unused

    -- Helper: is this opcode one that requires the FSM datapath?
    function is_fsm_op(op : opcode_t) return boolean;

end package alu_pkg;

package body alu_pkg is

    function is_fsm_op(op : opcode_t) return boolean is
    begin
        if (op = OP_MUL) or (op = OP_DIV) then
            return true;
        else
            return false;
        end if;
    end function is_fsm_op;

end package body alu_pkg;
