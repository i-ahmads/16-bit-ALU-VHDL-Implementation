-- Self-checking testbench for shift_add_mult_fsm.
-- IDENTICAL TESTS array to tb_booth_mult_fsm.vhd (same operands, same
-- expected products, same expected range_ovf flags) so the two multiplier
-- architectures are exercised with exactly the same input/output pairs, as
-- requested in course feedback. The only addition versus tb_booth_mult_fsm
-- is a per-vector clock-cycle counter, printed for every test, used to
-- build the comparative latency table in the report/slides.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity tb_shift_add_mult_fsm is
end entity tb_shift_add_mult_fsm;

architecture sim of tb_shift_add_mult_fsm is

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal start      : std_logic := '0';
    signal operand_a  : std_logic_vector(15 downto 0) := (others => '0');
    signal operand_b  : std_logic_vector(15 downto 0) := (others => '0');
    signal product_hi : std_logic_vector(15 downto 0);
    signal product_lo : std_logic_vector(15 downto 0);
    signal range_ovf  : std_logic;
    signal busy       : std_logic;
    signal done       : std_logic;

    signal pass_count : integer := 0;
    signal fail_count : integer := 0;
    signal sim_finished : boolean := false;

    type vec_t is record
        a   : std_logic_vector(15 downto 0);
        b   : std_logic_vector(15 downto 0);
        hi  : std_logic_vector(15 downto 0);
        lo  : std_logic_vector(15 downto 0);
        ovf : std_logic;
    end record;

    type vec_array_t is array (natural range <>) of vec_t;

    -- Identical to tb_booth_mult_fsm.vhd's TESTS array.
    constant TESTS : vec_array_t := (
        ( x"0000", x"0000", x"0000", x"0000", '0' ), -- 0 * 0 = 0
        ( x"0001", x"0001", x"0000", x"0001", '0' ), -- 1 * 1 = 1
        ( x"0005", x"0003", x"0000", x"000F", '0' ), -- 5 * 3 = 15
        ( x"FFFB", x"0003", x"FFFF", x"FFF1", '0' ), -- -5 * 3 = -15
        ( x"0005", x"FFFD", x"FFFF", x"FFF1", '0' ), -- 5 * -3 = -15
        ( x"FFFB", x"FFFD", x"0000", x"000F", '0' ), -- -5 * -3 = 15
        ( x"0064", x"0064", x"0000", x"2710", '0' ), -- 100 * 100 = 10000
        ( x"FF9C", x"0064", x"FFFF", x"D8F0", '0' ), -- -100 * 100 = -10000
        ( x"7FFF", x"7FFF", x"3FFF", x"0001", '1' ), -- 32767 * 32767
        ( x"8000", x"8000", x"4000", x"0000", '1' ), -- -32768 * -32768
        ( x"7FFF", x"8000", x"C000", x"8000", '1' ), -- 32767 * -32768
        ( x"8000", x"7FFF", x"C000", x"8000", '1' ), -- -32768 * 32767
        ( x"0001", x"FFFF", x"FFFF", x"FFFF", '0' ), -- 1 * -1 = -1
        ( x"FFFF", x"0001", x"FFFF", x"FFFF", '0' ), -- -1 * 1 = -1
        ( x"00FF", x"00FF", x"0000", x"FE01", '1' ), -- 255 * 255
        ( x"FFFF", x"FFFF", x"0000", x"0001", '0' ), -- -1 * -1 = 1
        ( x"4000", x"0004", x"0001", x"0000", '1' ), -- 16384 * 4
        ( x"0002", x"4000", x"0000", x"8000", '1' ), -- 2 * 16384
        ( x"8000", x"0001", x"FFFF", x"8000", '0' ), -- -32768 * 1
        ( x"7FFF", x"0001", x"0000", x"7FFF", '0' ), -- 32767 * 1
        ( x"3039", x"E57B", x"FB01", x"2863", '1' ), -- 12345 * -6789
        ( x"00C8", x"012C", x"0000", x"EA60", '1' )  -- 200 * 300
    );

begin

    dut : entity work.shift_add_mult_fsm
        port map (
            clk        => clk,
            rst        => rst,
            start      => start,
            operand_a  => operand_a,
            operand_b  => operand_b,
            product_hi => product_hi,
            product_lo => product_lo,
            range_ovf  => range_ovf,
            busy       => busy,
            done       => done
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
            operand_a <= TESTS(i).a;
            operand_b <= TESTS(i).b;
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            cycles := 0;
            while done = '0' and cycles < 40 loop
                wait until rising_edge(clk);
                cycles := cycles + 1;
            end loop;

            if done /= '1' then
                fail_count <= fail_count + 1;
                report "FAIL: watchdog timeout, done never asserted for test " &
                       integer'image(i) severity error;
            else
                if product_hi = TESTS(i).hi and product_lo = TESTS(i).lo and
                   range_ovf = TESTS(i).ovf then
                    pass_count <= pass_count + 1;
                    report "PASS: test " & integer'image(i) &
                           "  cycles=" & integer'image(cycles);
                else
                    fail_count <= fail_count + 1;
                    report "FAIL: test " & integer'image(i) &
                           "  got hi=" & integer'image(to_integer(unsigned(product_hi))) &
                           " lo=" & integer'image(to_integer(unsigned(product_lo))) &
                           " ovf=" & std_logic'image(range_ovf) &
                           "  expected hi=" & integer'image(to_integer(unsigned(TESTS(i).hi))) &
                           " lo=" & integer'image(to_integer(unsigned(TESTS(i).lo))) &
                           " ovf=" & std_logic'image(TESTS(i).ovf)
                        severity error;
                end if;
            end if;

            wait until rising_edge(clk);
        end loop;

        wait for 20 ns;
        report "=================================================";
        report "shift_add_mult_fsm TB complete. PASS=" &
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
