-------------------------------------------------------------------------------
-- bist_fsm.vhd
-- Entity: bist_fsm
--
-- Built-In Self-Test controller. Deliberately a DIFFERENT FSM shape from
-- booth_mult_fsm / restoring_div_fsm (which are 4-state, fixed-iteration-
-- count bit-serial machines): this is a 3-state Moore machine (ST_BIDLE ->
-- ST_BRUN -> ST_BDONE) driven by a vector-index counter walking a small
-- ROM of known-good (opcode, operand_a, operand_b, expected_result,
-- expected_result_ext) triples, so it doesn't resemble a scaled-down copy
-- of the mul/div FSM.
--
-- This entity does NOT contain a copy of the ALU -- it drives "gen_*"
-- stimulus signals and reads back "chk_*" response signals so it can test
-- the SAME hardware instance that's normally in use (real BIST philosophy:
-- exercise the actual functional unit, not a separate golden copy). That
-- also makes it unit-testable in isolation against a trivial mock responder
-- (see tb_bist_fsm.vhd) before being wired into alu_top's real datapath.
--
-- Auto-runs once after reset deasserts; bist_start also allows an on-demand
-- re-run later (e.g. triggered from a button/software register in the
-- final system). Test vectors cover every opcode category, including one
-- MUL overflow case and one DIV-by-zero case, and were taken directly from
-- the already-verified tb_combinational_alu / tb_booth_mult_fsm /
-- tb_restoring_div_fsm golden vectors.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity bist_fsm is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;                 -- async, active-high
        bist_start : in  std_logic;                  -- optional on-demand re-run

        -- stimulus driven onto the shared ALU datapath while BIST is active
        bist_active   : out std_logic;
        gen_opcode    : out opcode_t;
        gen_operand_a : out std_logic_vector(DATA_WIDTH-1 downto 0);
        gen_operand_b : out std_logic_vector(DATA_WIDTH-1 downto 0);
        gen_start     : out std_logic;

        -- response read back from the shared ALU datapath
        chk_result       : in std_logic_vector(DATA_WIDTH-1 downto 0);
        chk_result_ext    : in std_logic_vector(DATA_WIDTH-1 downto 0);
        chk_result_valid : in std_logic;

        bist_busy     : out std_logic;
        bist_done     : out std_logic;
        bist_pass     : out std_logic;
        bist_fail_idx : out std_logic_vector(3 downto 0)  -- index of first failing vector
    );
end entity bist_fsm;

architecture rtl of bist_fsm is

    type state_t is (ST_BIDLE, ST_BRUN, ST_BDONE);
    signal state, next_state : state_t;

    type bist_vec_t is record
        opcode : opcode_t;
        a      : std_logic_vector(DATA_WIDTH-1 downto 0);
        b      : std_logic_vector(DATA_WIDTH-1 downto 0);
        exp_r  : std_logic_vector(DATA_WIDTH-1 downto 0);
        exp_re : std_logic_vector(DATA_WIDTH-1 downto 0);
    end record;

    type bist_rom_t is array (natural range <>) of bist_vec_t;

    constant BIST_ROM : bist_rom_t := (
        ( OP_ADD, x"0005", x"0003", x"0008", x"0000" ),  -- 5+3=8
        ( OP_SUB, x"000A", x"0003", x"0007", x"0000" ),  -- 10-3=7
        ( OP_AND, x"F0F0", x"0FF0", x"00F0", x"0000" ),  -- AND
        ( OP_OR , x"F0F0", x"0F0F", x"FFFF", x"0000" ),  -- OR
        ( OP_XOR, x"FF00", x"0FF0", x"F0F0", x"0000" ),  -- XOR
        ( OP_NOT, x"0F0F", x"0000", x"F0F0", x"0000" ),  -- NOT
        ( OP_SHL, x"0001", x"0004", x"0010", x"0000" ),  -- SHL by 4
        ( OP_SAR, x"8000", x"0004", x"F800", x"0000" ),  -- SAR negative
        ( OP_ROL, x"8001", x"0001", x"0003", x"0000" ),  -- ROL by 1
        ( OP_MUL, x"0064", x"0064", x"2710", x"0000" ),  -- 100*100=10000
        ( OP_MUL, x"7FFF", x"7FFF", x"0001", x"3FFF" ),  -- 32767*32767 (overflow)
        ( OP_DIV, x"0064", x"0007", x"000E", x"0002" ),  -- 100/7=14 r2
        ( OP_DIV, x"1234", x"0000", x"0000", x"1234" )   -- divide by zero (remainder = dividend passthrough)
    );

    constant NUM_VECTORS : integer := BIST_ROM'length;

    signal vec_idx      : unsigned(3 downto 0);
    signal start_issued : std_logic;
    signal pass_reg      : std_logic;
    signal fail_idx_reg  : unsigned(3 downto 0);

begin

    -----------------------------------------------------------------------
    -- State register (async reset)
    -----------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            state <= ST_BIDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Next-state logic
    -----------------------------------------------------------------------
    process (state, bist_start, vec_idx)
    begin
        next_state <= state;
        case state is
            when ST_BIDLE =>
                -- auto-run once out of reset, or on-demand via bist_start
                next_state <= ST_BRUN;
            when ST_BRUN =>
                if vec_idx = NUM_VECTORS then
                    next_state <= ST_BDONE;
                end if;
            when ST_BDONE =>
                if bist_start = '1' then
                    next_state <= ST_BRUN;
                end if;
        end case;
    end process;

    -----------------------------------------------------------------------
    -- Stimulus generation (combinational mux off the current vector index)
    -----------------------------------------------------------------------
    process (state, vec_idx, start_issued)
        variable idx_i : integer;
    begin
        gen_opcode    <= OP_ADD;
        gen_operand_a <= (others => '0');
        gen_operand_b <= (others => '0');
        gen_start     <= '0';

        if state = ST_BRUN and vec_idx < NUM_VECTORS then
            idx_i := to_integer(vec_idx);
            gen_opcode    <= BIST_ROM(idx_i).opcode;
            gen_operand_a <= BIST_ROM(idx_i).a;
            gen_operand_b <= BIST_ROM(idx_i).b;
            if is_fsm_op(BIST_ROM(idx_i).opcode) and start_issued = '0' then
                gen_start <= '1';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Sequencing / compare / advance
    -----------------------------------------------------------------------
    process (clk, rst)
        variable idx_i : integer;
    begin
        if rst = '1' then
            vec_idx      <= (others => '0');
            start_issued <= '0';
            pass_reg     <= '1';
            fail_idx_reg <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                when ST_BIDLE =>
                    vec_idx      <= (others => '0');
                    start_issued <= '0';
                    pass_reg     <= '1';
                    fail_idx_reg <= (others => '0');

                when ST_BRUN =>
                    if vec_idx < NUM_VECTORS then
                        idx_i := to_integer(vec_idx);

                        -- latch that we've issued the single-cycle start pulse
                        -- for this vector, so it doesn't re-pulse every cycle
                        if is_fsm_op(BIST_ROM(idx_i).opcode) and start_issued = '0' then
                            start_issued <= '1';
                        end if;

                        if chk_result_valid = '1' then
                            if chk_result /= BIST_ROM(idx_i).exp_r or
                               chk_result_ext /= BIST_ROM(idx_i).exp_re then
                                if pass_reg = '1' then  -- keep first failure only
                                    fail_idx_reg <= vec_idx;
                                end if;
                                pass_reg <= '0';
                            end if;
                            vec_idx      <= vec_idx + 1;
                            start_issued <= '0';
                        end if;
                    end if;

                when ST_BDONE =>
                    if bist_start = '1' then
                        vec_idx      <= (others => '0');
                        start_issued <= '0';
                        pass_reg     <= '1';
                        fail_idx_reg <= (others => '0');
                    end if;
            end case;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------
    bist_active   <= '1' when state = ST_BRUN else '0';
    bist_busy     <= '1' when state = ST_BRUN else '0';
    bist_done     <= '1' when state = ST_BDONE else '0';
    bist_pass     <= pass_reg;
    bist_fail_idx <= std_logic_vector(fail_idx_reg);

end architecture rtl;
