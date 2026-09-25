-------------------------------------------------------------------------------
-- restoring_div_fsm.vhd
-- Entity: restoring_div_fsm
--
-- 16/16-bit UNSIGNED restoring division. 4-state FSM: IDLE -> LOAD -> COMPUTE
-- -> DONE. COMPUTE performs one restoring-division iteration per clock;
-- 16 iterations are required for 16-bit operands (one quotient bit per cycle).
--
-- operand_a = dividend, operand_b = divisor.
-- If operand_b = 0 at LOAD time, the FSM skips COMPUTE entirely and goes
-- straight to DONE with div_by_zero='1' (quotient/remainder undefined --
-- consumers must check div_by_zero before trusting the result).
--
-- Signed division is NOT implemented here (Tier 1 scope is unsigned only,
-- per the finalized architecture); sign handling would be a Tier-2/3
-- extension (convert to magnitude, divide, reapply sign) -- left as future
-- work rather than implemented, to avoid scope creep on Tier 1.
--
-- Algorithm verified against a Python golden model (3000+ random unsigned
-- 16/16 divisions, all exact) before being committed to VHDL.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity restoring_div_fsm is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;                     -- async, active-high
        start       : in  std_logic;
        operand_a   : in  std_logic_vector(DATA_WIDTH-1 downto 0);  -- dividend
        operand_b   : in  std_logic_vector(DATA_WIDTH-1 downto 0);  -- divisor
        quotient    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        remainder   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        div_by_zero : out std_logic;
        busy        : out std_logic;
        done        : out std_logic
    );
end entity restoring_div_fsm;

architecture rtl of restoring_div_fsm is

    type state_t is (ST_IDLE, ST_LOAD, ST_COMPUTE, ST_DONE);
    signal state, next_state : state_t;

    signal R_reg   : unsigned(DATA_WIDTH downto 0);   -- 17 bits (guard bit)
    signal Q_reg   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal D_reg   : unsigned(DATA_WIDTH-1 downto 0);
    signal iter_cnt : unsigned(4 downto 0);            -- counts 0..15

    signal R_reg_next : unsigned(DATA_WIDTH downto 0);
    signal Q_reg_next : std_logic_vector(DATA_WIDTH-1 downto 0);

    signal quotient_reg    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal remainder_reg   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal div_by_zero_reg : std_logic;

    signal divisor_is_zero : std_logic;

begin

    divisor_is_zero <= '1' when operand_b = (DATA_WIDTH-1 downto 0 => '0') else '0';

    -----------------------------------------------------------------------
    -- State register (async reset)
    -----------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            state <= ST_IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Next-state logic
    -----------------------------------------------------------------------
    process (state, start, iter_cnt, divisor_is_zero)
    begin
        next_state <= state;
        case state is
            when ST_IDLE =>
                if start = '1' then
                    next_state <= ST_LOAD;
                end if;
            when ST_LOAD =>
                if divisor_is_zero = '1' then
                    next_state <= ST_DONE;       -- short-circuit: skip COMPUTE
                else
                    next_state <= ST_COMPUTE;
                end if;
            when ST_COMPUTE =>
                if iter_cnt = DATA_WIDTH - 1 then
                    next_state <= ST_DONE;
                end if;
            when ST_DONE =>
                next_state <= ST_IDLE;
        end case;
    end process;

    -----------------------------------------------------------------------
    -- One restoring-division iteration (combinational shift + subtract)
    -----------------------------------------------------------------------
    process (R_reg, Q_reg, D_reg)
        variable r_shifted : unsigned(DATA_WIDTH downto 0);
        variable q_shifted : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable r_sub     : unsigned(DATA_WIDTH downto 0);
    begin
        -- shift {R,Q} left by 1: R's new LSB is Q's old MSB; Q's new LSB is
        -- a placeholder ('0') that gets overwritten with the quotient bit below.
        -- (Built via explicit slicing/concatenation rather than the sll/srl
        -- operators, which VHDL-93 only defines for BIT_VECTOR, not
        -- STD_LOGIC_VECTOR/unsigned -- this keeps the design portable.)
        r_shifted := R_reg(DATA_WIDTH-1 downto 0) & Q_reg(DATA_WIDTH-1);
        q_shifted := Q_reg(DATA_WIDTH-2 downto 0) & '0';

        -- trial subtract: R - D  (guard bit catches the borrow)
        r_sub := r_shifted - ('0' & D_reg);

        if r_sub(DATA_WIDTH) = '1' then
            -- negative result -> restore: keep r_shifted, quotient bit = 0
            R_reg_next   <= r_shifted;
            Q_reg_next   <= q_shifted(DATA_WIDTH-1 downto 1) & '0';
        else
            R_reg_next   <= r_sub;
            Q_reg_next   <= q_shifted(DATA_WIDTH-1 downto 1) & '1';
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Datapath registers
    -----------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            R_reg           <= (others => '0');
            Q_reg            <= (others => '0');
            D_reg            <= (others => '0');
            iter_cnt         <= (others => '0');
            quotient_reg     <= (others => '0');
            remainder_reg    <= (others => '0');
            div_by_zero_reg  <= '0';
        elsif rising_edge(clk) then
            case state is
                when ST_IDLE =>
                    null;

                when ST_LOAD =>
                    R_reg    <= (others => '0');
                    Q_reg    <= operand_a;
                    D_reg    <= unsigned(operand_b);
                    iter_cnt <= (others => '0');
                    if divisor_is_zero = '1' then
                        div_by_zero_reg <= '1';
                        quotient_reg    <= (others => '0');
                        remainder_reg   <= operand_a;   -- dividend passthrough
                    else
                        div_by_zero_reg <= '0';
                    end if;

                when ST_COMPUTE =>
                    R_reg    <= R_reg_next;
                    Q_reg    <= Q_reg_next;
                    iter_cnt <= iter_cnt + 1;
                    if iter_cnt = DATA_WIDTH - 1 then
                        quotient_reg  <= Q_reg_next;
                        remainder_reg <= std_logic_vector(R_reg_next(DATA_WIDTH-1 downto 0));
                    end if;

                when ST_DONE =>
                    null;  -- outputs already valid from LOAD (div-by-zero) or last COMPUTE cycle
            end case;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------
    busy        <= '1' when (state = ST_LOAD or state = ST_COMPUTE) else '0';
    done        <= '1' when state = ST_DONE else '0';
    quotient    <= quotient_reg;
    remainder   <= remainder_reg;
    div_by_zero <= div_by_zero_reg;

end architecture rtl;
