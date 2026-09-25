-- CONVENTIONAL (alternative) 16/16-bit UNSIGNED divider, built for direct,
-- apples-to-apples comparison against restoring_div_fsm (the chosen design).
-- Same port interface, same DATA_WIDTH, same divide-by-zero short-circuit
-- behaviour, same golden-model-cross-checked test vectors as
-- restoring_div_fsm -- the ONLY thing that changes is the division
-- algorithm itself:
--
--   restoring_div_fsm      : every iteration computes a trial subtraction
--                             and a 2:1 mux (restore / keep) -- ALWAYS a
--                             subtract, exactly 16 iterations, no
--                             data-dependent tail step. Deterministic
--                             17-cycle latency (1 LOAD + 16 COMPUTE) for
--                             every input.
--   non_restoring_div_fsm  : each iteration does ONE add-or-subtract,
--                             chosen by the SIGN of the previous remainder
--                             (needs a full add/sub unit, not just a
--                             subtractor), and needs a data-dependent
--                             FINAL CORRECTION add whenever the last
--                             remainder is negative. Latency is therefore
--                             17 cycles (1 LOAD + 16 COMPUTE) when no
--                             correction is needed, or 18 cycles
--                             (1 LOAD + 16 COMPUTE + 1 CORRECT) when it is
--                             -- a genuine, input-dependent timing
--                             difference that restoring division does not
--                             have.
--
-- Algorithm (per iteration i = 0..15), remainder kept as a signed register
-- so the "was the previous remainder negative" test is a single sign-bit
-- read:
--   R <= (R << 1) | msb(Q)
--   if R(sign) = '0' then R <= R - D  else  R <= R + D
--   quotient bit = NOT R_new(sign);  shift that bit into Q
-- After 16 iterations, if R is negative, R <= R + D (one-time correction);
-- Q is already the final quotient (no adjustment needed for unsigned
-- non-restoring division).
--
-- Verified against the same Python golden model used for restoring_div_fsm
-- (3000+ random unsigned 16/16 divisions, all exact) before being
-- committed to VHDL.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity non_restoring_div_fsm is
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
end entity non_restoring_div_fsm;

architecture rtl of non_restoring_div_fsm is

    type state_t is (ST_IDLE, ST_LOAD, ST_COMPUTE, ST_CORRECT, ST_DONE);
    signal state, next_state : state_t;

    signal R_reg   : signed(DATA_WIDTH downto 0);      -- 17-bit signed remainder
    signal Q_reg   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal D_reg   : unsigned(DATA_WIDTH-1 downto 0);
    signal iter_cnt : unsigned(4 downto 0);             -- counts 0..15

    signal R_reg_next : signed(DATA_WIDTH downto 0);
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
    -- NOTE the data-dependent branch out of the last COMPUTE cycle: this is
    -- the one structural difference from every other FSM in this project
    -- (all of which have a fixed, input-independent cycle count).
    -----------------------------------------------------------------------
    process (state, start, iter_cnt, divisor_is_zero, R_reg_next)
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
                    if R_reg_next(DATA_WIDTH) = '1' then
                        next_state <= ST_CORRECT;   -- final remainder negative: one more cycle
                    else
                        next_state <= ST_DONE;
                    end if;
                end if;
            when ST_CORRECT =>
                next_state <= ST_DONE;
            when ST_DONE =>
                next_state <= ST_IDLE;
        end case;
    end process;
    -- One non-restoring iteration: shift, then ADD or SUBTRACT depending on
    -- the SIGN of the previous remainder (restoring_div_fsm always
    -- subtracts and instead muxes the result afterward).
    process (R_reg, Q_reg, D_reg)
        variable r_shifted : signed(DATA_WIDTH downto 0);
        variable q_shifted : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable r_result  : signed(DATA_WIDTH downto 0);
        variable qbit      : std_logic;
    begin
        r_shifted := signed(std_logic_vector(R_reg(DATA_WIDTH-1 downto 0)) & Q_reg(DATA_WIDTH-1));

        if R_reg(DATA_WIDTH) = '0' then
            r_result := r_shifted - signed('0' & D_reg);   -- prev >= 0: subtract
        else
            r_result := r_shifted + signed('0' & D_reg);   -- prev <  0: add
        end if;

        if r_result(DATA_WIDTH) = '0' then
            qbit := '1';
        else
            qbit := '0';
        end if;

        q_shifted := Q_reg(DATA_WIDTH-2 downto 0) & qbit;

        R_reg_next <= r_result;
        Q_reg_next <= q_shifted;
    end process;

    -- Datapath registers
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
                        quotient_reg <= Q_reg_next;
                        -- tentative remainder; corrected in ST_CORRECT if
                        -- R_reg_next turned out negative
                        remainder_reg <= std_logic_vector(R_reg_next(DATA_WIDTH-1 downto 0));
                    end if;

                when ST_CORRECT =>
                    -- one-time restore: add the divisor back once
                    remainder_reg <= std_logic_vector(unsigned(remainder_reg) + D_reg);

                when ST_DONE =>
                    null;  -- outputs already valid from LOAD (div-by-zero),
                           -- last ST_COMPUTE cycle, or ST_CORRECT
            end case;
        end if;
    end process;

    -- Outputs
    busy        <= '1' when (state = ST_LOAD or state = ST_COMPUTE or state = ST_CORRECT) else '0';
    done        <= '1' when state = ST_DONE else '0';
    quotient    <= quotient_reg;
    remainder   <= remainder_reg;
    div_by_zero <= div_by_zero_reg;

end architecture rtl;
