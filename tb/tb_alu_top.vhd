-------------------------------------------------------------------------------
-- tb_alu_top.vhd
-- Integration testbench for alu_top: exercises opcode decode/routing, the
-- output mux (comb vs Booth-MUL vs restoring-DIV), the start/busy/done
-- handshake for FSM ops, and the shared flags block end-to-end.
-- The FSM datapaths themselves are already exhaustively verified in
-- tb_booth_mult_fsm and tb_restoring_div_fsm; this TB focuses on
-- integration/routing correctness, not re-deriving arithmetic correctness.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity tb_alu_top is
end entity tb_alu_top;

architecture sim of tb_alu_top is

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal opcode        : opcode_t := OP_ADD;
    signal operand_a     : std_logic_vector(15 downto 0) := (others => '0');
    signal operand_b     : std_logic_vector(15 downto 0) := (others => '0');
    signal start         : std_logic := '0';
    signal result        : std_logic_vector(15 downto 0);
    signal result_ext    : std_logic_vector(15 downto 0);
    signal result_valid  : std_logic;
    signal busy          : std_logic;
    signal zero_flag, carry_flag, overflow_flag, parity_flag : std_logic;

    signal bist_start    : std_logic := '0';
    signal bist_busy     : std_logic;
    signal bist_done     : std_logic;
    signal bist_pass     : std_logic;
    signal bist_fail_idx : std_logic_vector(3 downto 0);

    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;
    signal sim_finished : boolean := false;

    procedure check_slv(
        signal   got  : in std_logic_vector;
        constant exp  : in std_logic_vector;
        constant msg  : in string;
        signal   pass_c : inout integer;
        signal   fail_c : inout integer
    ) is
    begin
        if got = exp then
            pass_c <= pass_c + 1;
        else
            fail_c <= fail_c + 1;
            report "FAIL: " & msg &
                   "  got=" & integer'image(to_integer(unsigned(got))) &
                   " expected=" & integer'image(to_integer(unsigned(exp)))
                severity error;
        end if;
    end procedure;

    procedure check_bit(
        signal   got  : in std_logic;
        constant exp  : in std_logic;
        constant msg  : in string;
        signal   pass_c : inout integer;
        signal   fail_c : inout integer
    ) is
    begin
        if got = exp then
            pass_c <= pass_c + 1;
        else
            fail_c <= fail_c + 1;
            report "FAIL: " & msg & "  got=" & std_logic'image(got) &
                   " expected=" & std_logic'image(exp) severity error;
        end if;
    end procedure;

begin

    dut : entity work.alu_top
        port map (
            clk           => clk,
            rst           => rst,
            opcode        => opcode,
            operand_a     => operand_a,
            operand_b     => operand_b,
            start         => start,
            result        => result,
            result_ext    => result_ext,
            result_valid  => result_valid,
            busy          => busy,
            zero_flag     => zero_flag,
            carry_flag    => carry_flag,
            overflow_flag => overflow_flag,
            parity_flag   => parity_flag,
            bist_start    => bist_start,
            bist_busy     => bist_busy,
            bist_done     => bist_done,
            bist_pass     => bist_pass,
            bist_fail_idx => bist_fail_idx
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

        -----------------------------------------------------------------
        -- BIST auto-runs out of reset; wait for it and confirm it PASSES
        -- against the real (already individually-verified) hardware.
        -----------------------------------------------------------------
        cycles := 0;
        while bist_done = '0' and cycles < 300 loop
            wait until rising_edge(clk);
            cycles := cycles + 1;
        end loop;
        check_bit(bist_done, '1', "BIST auto-run completes out of reset", pass_count, fail_count);
        wait for 1 ns;
        report "DEBUG: bist_pass=" & std_logic'image(bist_pass) &
               " bist_fail_idx=" & integer'image(to_integer(unsigned(bist_fail_idx)));
        check_bit(bist_pass, '1', "BIST passes against real hardware", pass_count, fail_count);
        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- Combinational ops: result must be valid the same cycle, no FSM
        -----------------------------------------------------------------
        opcode <= OP_ADD; operand_a <= x"0005"; operand_b <= x"0003";
        wait for 1 ns;
        check_slv(result, x"0008", "ADD routed through comb path", pass_count, fail_count);
        check_bit(result_valid, '1', "ADD result_valid immediate", pass_count, fail_count);
        check_bit(busy, '0', "ADD busy stays low", pass_count, fail_count);
        check_slv(result_ext, x"0000", "ADD result_ext is zero", pass_count, fail_count);

        opcode <= OP_SUB; operand_a <= x"0005"; operand_b <= x"0005";
        wait for 1 ns;
        check_slv(result, x"0000", "SUB 5-5", pass_count, fail_count);
        check_bit(zero_flag, '1', "SUB zero flag", pass_count, fail_count);

        opcode <= OP_AND; operand_a <= x"F0F0"; operand_b <= x"0FF0";
        wait for 1 ns;
        check_slv(result, x"00F0", "AND routed through comb path", pass_count, fail_count);

        opcode <= OP_SHL; operand_a <= x"0001"; operand_b <= x"0004";
        wait for 1 ns;
        check_slv(result, x"0010", "SHL routed through comb path", pass_count, fail_count);

        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- MUL: 100 * 100 = 10000, fits in 16 bits (no range overflow)
        -----------------------------------------------------------------
        opcode <= OP_MUL; operand_a <= x"0064"; operand_b <= x"0064";
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait for 1 ns;  -- let combinational busy settle after the state register update
        check_bit(busy, '1', "MUL busy asserted after start", pass_count, fail_count);

        cycles := 0;
        while result_valid = '0' and cycles < 30 loop
            wait until rising_edge(clk);
            cycles := cycles + 1;
        end loop;
        check_bit(result_valid, '1', "MUL result_valid eventually asserts", pass_count, fail_count);
        check_slv(result, x"2710", "MUL 100*100 primary result", pass_count, fail_count);
        check_slv(result_ext, x"0000", "MUL 100*100 extended result (no overflow)", pass_count, fail_count);
        check_bit(overflow_flag, '0', "MUL 100*100 no range overflow flag", pass_count, fail_count);
        wait until rising_edge(clk);
        check_bit(busy, '0', "MUL busy drops after done", pass_count, fail_count);

        -----------------------------------------------------------------
        -- MUL: 32767 * 32767 -- exceeds 16 bits, overflow_flag must assert
        -----------------------------------------------------------------
        opcode <= OP_MUL; operand_a <= x"7FFF"; operand_b <= x"7FFF";
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        cycles := 0;
        while result_valid = '0' and cycles < 30 loop
            wait until rising_edge(clk);
            cycles := cycles + 1;
        end loop;
        check_slv(result, x"0001", "MUL 32767*32767 primary (low word)", pass_count, fail_count);
        check_slv(result_ext, x"3FFF", "MUL 32767*32767 extended (high word)", pass_count, fail_count);
        check_bit(overflow_flag, '1', "MUL 32767*32767 range overflow flag", pass_count, fail_count);
        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- DIV: 100 / 7 = 14 remainder 2
        -----------------------------------------------------------------
        opcode <= OP_DIV; operand_a <= x"0064"; operand_b <= x"0007";
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait for 1 ns;  -- let combinational busy settle after the state register update
        check_bit(busy, '1', "DIV busy asserted after start", pass_count, fail_count);

        cycles := 0;
        while result_valid = '0' and cycles < 30 loop
            wait until rising_edge(clk);
            cycles := cycles + 1;
        end loop;
        check_slv(result, x"000E", "DIV 100/7 quotient", pass_count, fail_count);
        check_slv(result_ext, x"0002", "DIV 100/7 remainder", pass_count, fail_count);
        check_bit(overflow_flag, '0', "DIV 100/7 no div-by-zero flag", pass_count, fail_count);
        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- DIV by zero: overflow_flag/carry_flag must assert via div_by_zero
        -----------------------------------------------------------------
        opcode <= OP_DIV; operand_a <= x"1234"; operand_b <= x"0000";
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        cycles := 0;
        while result_valid = '0' and cycles < 30 loop
            wait until rising_edge(clk);
            cycles := cycles + 1;
        end loop;
        check_bit(overflow_flag, '1', "DIV by zero -> overflow flag", pass_count, fail_count);
        check_bit(carry_flag, '1', "DIV by zero -> carry flag", pass_count, fail_count);
        wait until rising_edge(clk);

        -----------------------------------------------------------------
        -- Back to a combinational op right after an FSM op: no cross-talk
        -----------------------------------------------------------------
        opcode <= OP_XOR; operand_a <= x"AAAA"; operand_b <= x"5555";
        wait for 1 ns;
        check_slv(result, x"FFFF", "XOR immediately after DIV, no cross-talk", pass_count, fail_count);
        check_bit(busy, '0', "busy clear after returning to comb op", pass_count, fail_count);

        wait for 20 ns;
        report "=================================================";
        report "alu_top integration TB complete. PASS=" &
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
