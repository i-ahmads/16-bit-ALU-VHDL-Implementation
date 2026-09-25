-- CONVENTIONAL (baseline) 16x16 SIGNED multiplier, built for direct,
-- apples-to-apples comparison against booth_mult_fsm (the chosen design).
--
-- Same port interface, same DATA_WIDTH, same 4-state IDLE->LOAD->COMPUTE->DONE
-- FSMD template, same golden-model-cross-checked test vectors as
-- booth_mult_fsm -- the ONLY thing that changes is the multiplication
-- algorithm itself:
--
--   booth_mult_fsm      : radix-4 Booth recoding, operates directly on the
--                          two's-complement operands, 2 multiplier bits
--                          retired per cycle -> 8 iterations for 16 bits.
--   shift_add_mult_fsm  : classical shift-and-add, operates on SIGN-MAGNITUDE
--                          operands (explicit sign extraction + two's-
--                          complement negate pre-stage, and a conditional
--                          final negate post-stage), 1 multiplier bit
--                          retired per cycle -> 16 iterations for 16 bits.
--
-- Algorithm (per iteration i = 0..15):
--   if Q(0) = '1' then A <= A + |operand_a|  end if
--   {A,Q} <= {A,Q} >> 1   (logical, since operands are now unsigned magnitudes)
-- After 16 iterations, {A,Q} is the 32-bit UNSIGNED magnitude product; the
-- final signed product is obtained by negating that magnitude iff the
-- operand signs differed (sign_a xor sign_b), exactly mirroring how
-- booth_mult_fsm derives product_hi/product_lo/range_ovf from its own
-- 34-bit accumulate-then-shift result, so the two designs are compared on
-- equal footing.
--
-- Verified against the same Python golden model used for booth_mult_fsm
-- (2000+ random signed 16x16 products, all exact) before being committed
-- to VHDL.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity shift_add_mult_fsm is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;                     -- async, active-high
        start      : in  std_logic;                      -- pulse/level: begin op while in ST_IDLE
        operand_a  : in  std_logic_vector(DATA_WIDTH-1 downto 0);  -- multiplicand
        operand_b  : in  std_logic_vector(DATA_WIDTH-1 downto 0);  -- multiplier
        product_hi : out std_logic_vector(DATA_WIDTH-1 downto 0);
        product_lo : out std_logic_vector(DATA_WIDTH-1 downto 0);
        range_ovf  : out std_logic;
        busy       : out std_logic;
        done       : out std_logic
    );
end entity shift_add_mult_fsm;

architecture rtl of shift_add_mult_fsm is

    constant ACC_WIDTH : integer := DATA_WIDTH + 1;   -- 17, catches add carry-out
    constant NUM_ITERS  : integer := DATA_WIDTH;       -- 16 (1 bit/cycle, vs Booth's 8)

    type state_t is (ST_IDLE, ST_LOAD, ST_COMPUTE, ST_DONE);
    signal state, next_state : state_t;

    signal A_reg, A_next : unsigned(ACC_WIDTH-1 downto 0);
    signal Q_reg, Q_next : unsigned(DATA_WIDTH-1 downto 0);
    signal mag_a_reg      : unsigned(DATA_WIDTH-1 downto 0);
    signal sign_a_reg, sign_b_reg : std_logic;
    signal iter_cnt        : unsigned(4 downto 0);      -- counts 0..15

    signal prod_hi_reg, prod_lo_reg : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal range_ovf_reg            : std_logic;

begin

    -- State register (async reset)
    process (clk, rst)
    begin
        if rst = '1' then
            state <= ST_IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    -- Next-state logic
    process (state, start, iter_cnt)
    begin
        next_state <= state;
        case state is
            when ST_IDLE =>
                if start = '1' then
                    next_state <= ST_LOAD;
                end if;
            when ST_LOAD =>
                next_state <= ST_COMPUTE;
            when ST_COMPUTE =>
                if iter_cnt = NUM_ITERS - 1 then
                    next_state <= ST_DONE;
                end if;
            when ST_DONE =>
                next_state <= ST_IDLE;
        end case;
    end process;

    -- One shift-and-add iteration (combinational add + shift-right-by-1)
    process (A_reg, Q_reg, mag_a_reg)
        variable a_sum    : unsigned(ACC_WIDTH-1 downto 0);
        variable combined : unsigned(ACC_WIDTH+DATA_WIDTH-1 downto 0);  -- 17+16=33 bits
        variable shifted  : unsigned(ACC_WIDTH+DATA_WIDTH-1 downto 0);
    begin
        if Q_reg(0) = '1' then
            a_sum := A_reg + resize(mag_a_reg, ACC_WIDTH);
        else
            a_sum := A_reg;
        end if;

        combined := a_sum & Q_reg;
        shifted  := '0' & combined(ACC_WIDTH+DATA_WIDTH-1 downto 1);  -- logical SR1

        A_next <= shifted(ACC_WIDTH+DATA_WIDTH-1 downto DATA_WIDTH);
        Q_next <= shifted(DATA_WIDTH-1 downto 0);
    end process;
    -- Datapath registers
    process (clk, rst)
        variable mag_b_v      : unsigned(DATA_WIDTH-1 downto 0);
        variable combined_mag : std_logic_vector(2*DATA_WIDTH-1 downto 0);
        variable final_prod   : std_logic_vector(2*DATA_WIDTH-1 downto 0);
    begin
        if rst = '1' then
            A_reg         <= (others => '0');
            Q_reg         <= (others => '0');
            mag_a_reg     <= (others => '0');
            sign_a_reg    <= '0';
            sign_b_reg    <= '0';
            iter_cnt      <= (others => '0');
            prod_hi_reg   <= (others => '0');
            prod_lo_reg   <= (others => '0');
            range_ovf_reg <= '0';
        elsif rising_edge(clk) then
            case state is
                when ST_IDLE =>
                    null;

                when ST_LOAD =>
                    -- explicit sign-extraction + two's-complement magnitude
                    -- pre-stage: this whole block is hardware booth_mult_fsm
                    -- does not need, since Booth operates on the signed
                    -- operand directly.
                    sign_a_reg <= operand_a(DATA_WIDTH-1);
                    sign_b_reg <= operand_b(DATA_WIDTH-1);

                    if operand_a(DATA_WIDTH-1) = '1' then
                        mag_a_reg <= unsigned(not operand_a) + 1;
                    else
                        mag_a_reg <= unsigned(operand_a);
                    end if;

                    if operand_b(DATA_WIDTH-1) = '1' then
                        mag_b_v := unsigned(not operand_b) + 1;
                    else
                        mag_b_v := unsigned(operand_b);
                    end if;

                    A_reg    <= (others => '0');
                    Q_reg    <= mag_b_v;
                    iter_cnt <= (others => '0');

                when ST_COMPUTE =>
                    A_reg    <= A_next;
                    Q_reg    <= Q_next;
                    iter_cnt <= iter_cnt + 1;
                    -- On the LAST iteration, derive the signed product from
                    -- A_next/Q_next (this cycle's update) directly, keeping
                    -- 'done' and product_hi/product_lo aligned on the same
                    -- clock edge, exactly as booth_mult_fsm does.
                    if iter_cnt = NUM_ITERS - 1 then
                        combined_mag := std_logic_vector(A_next(DATA_WIDTH-1 downto 0)) &
                                        std_logic_vector(Q_next);
                        if (sign_a_reg xor sign_b_reg) = '1' then
                            final_prod := std_logic_vector(-signed(combined_mag));
                        else
                            final_prod := combined_mag;
                        end if;

                        prod_hi_reg <= final_prod(2*DATA_WIDTH-1 downto DATA_WIDTH);
                        prod_lo_reg <= final_prod(DATA_WIDTH-1 downto 0);

                        if final_prod(2*DATA_WIDTH-1 downto DATA_WIDTH) =
                           (DATA_WIDTH-1 downto 0 => final_prod(DATA_WIDTH-1)) then
                            range_ovf_reg <= '0';
                        else
                            range_ovf_reg <= '1';
                        end if;
                    end if;

                when ST_DONE =>
                    null;  -- outputs already valid from the last ST_COMPUTE cycle
            end case;
        end if;
    end process;
    -- Outputs
    busy       <= '1' when (state = ST_LOAD or state = ST_COMPUTE) else '0';
    done       <= '1' when state = ST_DONE else '0';
    product_hi <= prod_hi_reg;
    product_lo <= prod_lo_reg;
    range_ovf  <= range_ovf_reg;

end architecture rtl;
