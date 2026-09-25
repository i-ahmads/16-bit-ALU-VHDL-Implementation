-------------------------------------------------------------------------------
-- alu_top.vhd
-- Entity: alu_top
--
-- Top-level 16-bit ALU (Tier 1 + BIST from Tier 2): combinational core
-- (ADD/SUB/AND/OR/XOR/NOT/shifts/rotates) + FSM-controlled Booth radix-4
-- multiply and restoring divide + shared flags block + Built-In Self-Test.
--
-- Combinational ops: valid the same cycle, result_valid='1' always for them.
-- MUL/DIV: pulse 'start' with opcode set to OP_MUL/OP_DIV; busy goes high,
--          result_valid pulses high for one cycle once the FSM finishes.
--
-- result      : primary 16-bit result (comb result / Booth product_lo /
--               division quotient)
-- result_ext  : extension word, meaningful only for MUL (product_hi) and
--               DIV (remainder); driven to all-zero for combinational ops.
--
-- BIST: bist_fsm drives gen_opcode/gen_operand_a/gen_operand_b/gen_start
-- onto the SAME combinational_alu/booth_mult_fsm/restoring_div_fsm
-- instances used for normal operation (real BIST philosophy: exercise the
-- actual hardware, not a separate golden copy) via the eff_* mux below.
-- While bist_active='1': the external opcode/operand_a/operand_b/start
-- inputs are ignored, and the external-facing result_valid is gated low
-- (busy is NOT gated -- the ALU genuinely is busy) so an external caller
-- can't mistake BIST-internal traffic for its own request completing.
-- BIST auto-runs once out of reset; bist_start allows an on-demand re-run.
--
-- NOTE (Tier 2 to-do, not yet implemented here): the resource-sharing goal
-- of reusing one adder/subtractor across the combinational ADD/SUB path and
-- the FSM MUL/DIV accumulator, explicit clock-enable gating on the FSM
-- datapaths, and the final registered output stage are the next Tier 2
-- items, addressed after BIST is verified.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity alu_top is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        opcode        : in  opcode_t;
        operand_a     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        operand_b     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        start         : in  std_logic;  -- pulse: begin MUL/DIV (ignored by comb ops)

        result        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        result_ext    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        result_valid  : out std_logic;
        busy          : out std_logic;

        zero_flag     : out std_logic;
        carry_flag    : out std_logic;
        overflow_flag : out std_logic;
        parity_flag   : out std_logic;

        -- BIST
        bist_start    : in  std_logic;
        bist_busy     : out std_logic;
        bist_done     : out std_logic;
        bist_pass     : out std_logic;
        bist_fail_idx : out std_logic_vector(3 downto 0)
    );
end entity alu_top;

architecture struct of alu_top is

    signal comb_result    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal comb_carry_out : std_logic;

    signal mult_start      : std_logic;
    signal mult_product_hi : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mult_product_lo : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mult_range_ovf  : std_logic;
    signal mult_busy       : std_logic;
    signal mult_done       : std_logic;

    signal div_start       : std_logic;
    signal div_quotient    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal div_remainder   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal div_by_zero     : std_logic;
    signal div_busy        : std_logic;
    signal div_done        : std_logic;

    signal primary_result  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal extended_result : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal result_valid_int : std_logic;

    -- BIST generator/checker signals
    signal bist_active   : std_logic;
    signal gen_opcode    : opcode_t;
    signal gen_operand_a : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal gen_operand_b : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal gen_start     : std_logic;

    -- Effective signals actually driven into the shared datapath: external
    -- inputs when BIST is idle, BIST-generated stimulus when BIST is active
    signal eff_opcode    : opcode_t;
    signal eff_operand_a : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal eff_operand_b : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal eff_start     : std_logic;

begin

    eff_opcode    <= gen_opcode    when bist_active = '1' else opcode;
    eff_operand_a <= gen_operand_a when bist_active = '1' else operand_a;
    eff_operand_b <= gen_operand_b when bist_active = '1' else operand_b;
    eff_start     <= gen_start     when bist_active = '1' else start;

    -----------------------------------------------------------------------
    -- Combinational core
    -----------------------------------------------------------------------
    u_comb_alu : entity work.combinational_alu
        port map (
            operand_a => eff_operand_a,
            operand_b => eff_operand_b,
            opcode    => eff_opcode,
            result    => comb_result,
            carry_out => comb_carry_out
        );

    -----------------------------------------------------------------------
    -- FSM datapaths: only the FSM matching the current effective opcode
    -- is started
    -----------------------------------------------------------------------
    mult_start <= eff_start when eff_opcode = OP_MUL else '0';
    div_start  <= eff_start when eff_opcode = OP_DIV else '0';

    u_booth_mult : entity work.booth_mult_fsm
        port map (
            clk        => clk,
            rst        => rst,
            start      => mult_start,
            operand_a  => eff_operand_a,
            operand_b  => eff_operand_b,
            product_hi => mult_product_hi,
            product_lo => mult_product_lo,
            range_ovf  => mult_range_ovf,
            busy       => mult_busy,
            done       => mult_done
        );

    u_restoring_div : entity work.restoring_div_fsm
        port map (
            clk         => clk,
            rst         => rst,
            start       => div_start,
            operand_a   => eff_operand_a,
            operand_b   => eff_operand_b,
            quotient    => div_quotient,
            remainder   => div_remainder,
            div_by_zero => div_by_zero,
            busy        => div_busy,
            done        => div_done
        );

    -----------------------------------------------------------------------
    -- Output mux
    -----------------------------------------------------------------------
    process (eff_opcode, comb_result, mult_product_lo, mult_product_hi,
             div_quotient, div_remainder)
    begin
        case eff_opcode is
            when OP_MUL =>
                primary_result  <= mult_product_lo;
                extended_result <= mult_product_hi;
            when OP_DIV =>
                primary_result  <= div_quotient;
                extended_result <= div_remainder;
            when others =>
                primary_result  <= comb_result;
                extended_result <= (others => '0');
        end case;
    end process;

    result     <= primary_result;
    result_ext <= extended_result;

    busy <= mult_busy or div_busy or bist_active;

    result_valid_int <= '1' when (eff_opcode = OP_MUL and mult_done = '1') or
                                 (eff_opcode = OP_DIV and div_done = '1') or
                                 (not is_fsm_op(eff_opcode))
                        else '0';

    -- External-facing result_valid is gated low during BIST so a caller
    -- can't mistake BIST-internal traffic for its own request completing.
    result_valid <= result_valid_int when bist_active = '0' else '0';

    -----------------------------------------------------------------------
    -- Shared flags block
    -----------------------------------------------------------------------
    u_flags : entity work.flags_unit
        port map (
            opcode          => eff_opcode,
            operand_a       => eff_operand_a,
            operand_b       => eff_operand_b,
            adder_carry_out => comb_carry_out,
            primary_result  => primary_result,
            extended_result => extended_result,
            mult_range_ovf  => mult_range_ovf,
            div_by_zero     => div_by_zero,
            zero_flag       => zero_flag,
            carry_flag      => carry_flag,
            overflow_flag   => overflow_flag,
            parity_flag     => parity_flag
        );

    -----------------------------------------------------------------------
    -- BIST controller (shares the datapath above via the eff_* mux)
    -----------------------------------------------------------------------
    u_bist : entity work.bist_fsm
        port map (
            clk           => clk,
            rst           => rst,
            bist_start    => bist_start,
            bist_active   => bist_active,
            gen_opcode    => gen_opcode,
            gen_operand_a => gen_operand_a,
            gen_operand_b => gen_operand_b,
            gen_start     => gen_start,
            chk_result       => primary_result,
            chk_result_ext   => extended_result,
            chk_result_valid => result_valid_int,
            bist_busy     => bist_busy,
            bist_done     => bist_done,
            bist_pass     => bist_pass,
            bist_fail_idx => bist_fail_idx
        );

end architecture struct;
