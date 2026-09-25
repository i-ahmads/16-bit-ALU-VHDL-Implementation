-------------------------------------------------------------------------------
-- tb_restoring_div_fsm.vhd
-- Self-checking testbench for restoring_div_fsm.
-- Test vectors cross-checked against a Python golden model (3000+ random
-- unsigned 16/16 divisions, all exact) before being embedded here.
-- Also covers the divide-by-zero short-circuit path.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity tb_restoring_div_fsm is
end entity tb_restoring_div_fsm;

architecture sim of tb_restoring_div_fsm is

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal start       : std_logic := '0';
    signal operand_a   : std_logic_vector(15 downto 0) := (others => '0');
    signal operand_b   : std_logic_vector(15 downto 0) := (others => '0');
    signal quotient    : std_logic_vector(15 downto 0);
    signal remainder   : std_logic_vector(15 downto 0);
    signal div_by_zero : std_logic;
    signal busy        : std_logic;
    signal done        : std_logic;

    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;
    signal sim_finished : boolean := false;

    type vec_t is record
        dividend : std_logic_vector(15 downto 0);
        divisor  : std_logic_vector(15 downto 0);
        exp_q    : std_logic_vector(15 downto 0);
        exp_r    : std_logic_vector(15 downto 0);
        exp_dz   : std_logic;
    end record;

    type vec_array_t is array (natural range <>) of vec_t;

    constant TESTS : vec_array_t := (
        ( x"0000", x"0001", x"0000", x"0000", '0' ), -- 0/1
        ( x"0001", x"0001", x"0001", x"0000", '0' ), -- 1/1
        ( x"000A", x"0003", x"0003", x"0001", '0' ), -- 10/3
        ( x"0064", x"0007", x"000E", x"0002", '0' ), -- 100/7
        ( x"FFFF", x"0001", x"FFFF", x"0000", '0' ), -- 65535/1
        ( x"FFFF", x"FFFF", x"0001", x"0000", '0' ), -- 65535/65535
        ( x"0005", x"000A", x"0000", x"0005", '0' ), -- 5/10
        ( x"0000", x"0005", x"0000", x"0000", '0' ), -- 0/5
        ( x"0001", x"FFFF", x"0000", x"0001", '0' ), -- 1/65535
        ( x"8000", x"0002", x"4000", x"0000", '0' ), -- 32768/2
        ( x"3039", x"0059", x"008A", x"003F", '0' ), -- 12345/89
        ( x"EA60", x"0007", x"217B", x"0003", '0' ), -- 60000/7
        ( x"03E7", x"0025", x"001B", x"0000", '0' ), -- 999/37
        ( x"8000", x"8000", x"0001", x"0000", '0' ), -- 32768/32768
        ( x"FFFF", x"0002", x"7FFF", x"0001", '0' ), -- 65535/2
        ( x"03E8", x"0003", x"014D", x"0001", '0' ), -- 1000/3
        ( x"1234", x"0000", x"0000", x"0000", '1' )  -- divide by zero
    );

begin

    dut : entity work.restoring_div_fsm
        port map (
            clk         => clk,
            rst         => rst,
            start       => start,
            operand_a   => operand_a,
            operand_b   => operand_b,
            quotient    => quotient,
            remainder   => remainder,
            div_by_zero => div_by_zero,
            busy        => busy,
            done        => done
        );

    clk_gen : process
    begin
        while not sim_finished loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim : process
        variable cycles : integer;
    begin
        rst <= '1';
        wait for 20 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        for i in TESTS'range loop
            operand_a <= TESTS(i).dividend;
            operand_b <= TESTS(i).divisor;
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            cycles := 0;
            while done = '0' and cycles < 30 loop
                wait until rising_edge(clk);
                cycles := cycles + 1;
            end loop;

            if done /= '1' then
                fail_count <= fail_count + 1;
                report "FAIL: watchdog timeout for test " & integer'image(i) severity error;
            else
                if div_by_zero = TESTS(i).exp_dz and
                   (TESTS(i).exp_dz = '1' or
                    (quotient = TESTS(i).exp_q and remainder = TESTS(i).exp_r)) then
                    pass_count <= pass_count + 1;
                else
                    fail_count <= fail_count + 1;
                    report "FAIL: test " & integer'image(i) &
                           "  got q=" & integer'image(to_integer(unsigned(quotient))) &
                           " r=" & integer'image(to_integer(unsigned(remainder))) &
                           " dz=" & std_logic'image(div_by_zero) &
                           "  expected q=" & integer'image(to_integer(unsigned(TESTS(i).exp_q))) &
                           " r=" & integer'image(to_integer(unsigned(TESTS(i).exp_r))) &
                           " dz=" & std_logic'image(TESTS(i).exp_dz)
                        severity error;
                end if;
            end if;

            wait until rising_edge(clk);
        end loop;

        wait for 20 ns;
        report "=================================================";
        report "restoring_div_fsm TB complete. PASS=" &
               integer'image(pass_count) & " FAIL=" & integer'image(fail_count);
        report "=================================================";
        if fail_count = 0 then
            report "*** ALL TESTS PASSED ***";
        else
            report "*** TESTS FAILED ***" severity error;
        end if;

        sim_finished <= true;
        wait;
    end process;

end architecture sim;
