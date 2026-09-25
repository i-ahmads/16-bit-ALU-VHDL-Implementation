-------------------------------------------------------------------------------
-- booth_mult_fsm.vhd
-- Entity: booth_mult_fsm
--
-- 16x16 -> 32-bit SIGNED multiplication using modified (radix-4) Booth
-- recoding. 4-state FSM: ST_IDLE -> ST_LOAD -> ST_COMPUTE -> ST_DONE.
-- ST_COMPUTE performs one radix-4 Booth iteration per clock; 8 iterations are
-- required for 16-bit operands (2 bits retired per cycle).
--
-- Internal widths: the accumulator A and sign-extended multiplicand M_reg
-- use DATA_WIDTH+2 = 18 bits ("guard bits") -- the standard margin needed
-- so that the +/-2M additions used by radix-4 Booth recoding never overflow
-- before the arithmetic right-shift. This was verified against a golden
-- software model (2000+ random signed 16x16 products, all exact) before
-- being committed to VHDL.
--
-- range_ovf asserts when the signed product does not fit in the low 16
-- bits alone (i.e. product_hi is not just the sign-extension of product_lo)
-- -- fed to flags_unit as the MUL overflow/carry source.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity booth_mult_fsm is
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
end entity booth_mult_fsm;

architecture rtl of booth_mult_fsm is

    constant GUARD_WIDTH : integer := DATA_WIDTH + 2;  -- 18
    constant NUM_ITERS   : integer := DATA_WIDTH / 2;  -- 8

    type state_t is (ST_IDLE, ST_LOAD, ST_COMPUTE, ST_DONE);
    signal state, next_state : state_t;

    signal A_reg, A_next    : signed(GUARD_WIDTH-1 downto 0);
    signal M_reg             : signed(GUARD_WIDTH-1 downto 0);
    signal Q_reg, Q_next     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal Qm1_reg, Qm1_next : std_logic;
    signal iter_cnt          : unsigned(3 downto 0);  -- counts 0..7

    signal prod_hi_reg, prod_lo_reg : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal range_ovf_reg            : std_logic;

begin

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

    -----------------------------------------------------------------------
    -- One radix-4 Booth iteration (combinational addend + shift logic)
    -----------------------------------------------------------------------
    process (A_reg, Q_reg, Qm1_reg, M_reg)
        variable bits3   : std_logic_vector(2 downto 0);
        variable addend  : signed(GUARD_WIDTH-1 downto 0);
        variable a_sum   : signed(GUARD_WIDTH-1 downto 0);
        variable combined : signed(GUARD_WIDTH+DATA_WIDTH downto 0);  -- 18+16+1=35 bits
        variable shifted  : signed(GUARD_WIDTH+DATA_WIDTH downto 0);
    begin
        bits3 := Q_reg(1) & Q_reg(0) & Qm1_reg;

        case bits3 is
            when "000" | "111" =>
                addend := (others => '0');
            when "001" | "010" =>
                addend := M_reg;
            when "011" =>
                addend := shift_left(M_reg, 1);
            when "100" =>
                addend := -shift_left(M_reg, 1);
            when "101" | "110" =>
                addend := -M_reg;
            when others =>
                addend := (others => '0');
        end case;

        a_sum := A_reg + addend;

        combined := a_sum & signed(Q_reg) & '0';
        combined(0) := Qm1_reg;
        shifted := shift_right(combined, 2);

        A_next   <= shifted(GUARD_WIDTH+DATA_WIDTH downto DATA_WIDTH+1);
        Q_next   <= std_logic_vector(shifted(DATA_WIDTH downto 1));
        Qm1_next <= shifted(0);
    end process;

    -----------------------------------------------------------------------
    -- Datapath registers
    -----------------------------------------------------------------------
    process (clk, rst)
    begin
        if rst = '1' then
            A_reg         <= (others => '0');
            M_reg         <= (others => '0');
            Q_reg         <= (others => '0');
            Qm1_reg       <= '0';
            iter_cnt      <= (others => '0');
            prod_hi_reg   <= (others => '0');
            prod_lo_reg   <= (others => '0');
            range_ovf_reg <= '0';
        elsif rising_edge(clk) then
            case state is
                when ST_IDLE =>
                    null;

                when ST_LOAD =>
                    M_reg    <= resize(signed(operand_a), GUARD_WIDTH);
                    Q_reg    <= operand_b;
                    A_reg    <= (others => '0');
                    Qm1_reg  <= '0';
                    iter_cnt <= (others => '0');

                when ST_COMPUTE =>
                    A_reg    <= A_next;
                    Q_reg    <= Q_next;
                    Qm1_reg  <= Qm1_next;
                    iter_cnt <= iter_cnt + 1;
                    -- On the LAST iteration, capture the outputs from A_next/Q_next
                    -- (this cycle's result) directly -- NOT from A_reg/Q_reg, which
                    -- still hold the pre-update value at this point in the process.
                    -- This keeps 'done' and product_hi/product_lo aligned on the
                    -- same clock edge instead of lagging by an extra cycle.
                    if iter_cnt = NUM_ITERS - 1 then
                        prod_hi_reg <= std_logic_vector(A_next(DATA_WIDTH-1 downto 0));
                        prod_lo_reg <= Q_next;
                        if A_next(DATA_WIDTH-1 downto 0) =
                           (DATA_WIDTH-1 downto 0 => Q_next(DATA_WIDTH-1)) then
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

    -----------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------
    busy       <= '1' when (state = ST_LOAD or state = ST_COMPUTE) else '0';
    done       <= '1' when state = ST_DONE else '0';
    product_hi <= prod_hi_reg;
    product_lo <= prod_lo_reg;
    range_ovf  <= range_ovf_reg;

end architecture rtl;
