-------------------------------------------------------------------------------
-- tb_bist_fsm.vhd
-- Standalone unit test for bist_fsm's CONTROL LOGIC (sequencing, start-pulse
-- discipline, pass/fail latching, fail-index capture, re-trigger), using a
-- mock ALU responder instead of the real datapath. This is the only place
-- we can cleanly exercise the FAIL-detection path: once bist_fsm is wired
-- to the real (already-verified-correct) ALU it will only ever see PASS,
-- so the fail-path logic would otherwise go untested.
--
-- The mock: for combinational-type opcodes it answers immediately with the
-- known-correct value (or a deliberately WRONG value for one designated
-- vector, VEC_TO_CORRUPT); for FSM-type opcodes (MUL/DIV) it waits for a
-- one-cycle gen_start pulse and then answers after a fixed simulated
-- latency, so the test also checks that bist_fsm correctly waits rather
-- than assuming immediate completion, and that gen_start pulses exactly
-- once per vector (a stuck-high start would re-trigger the mock's latency
-- counter and this test would catch that via a hang/mismatch).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity tb_bist_fsm is
end entity tb_bist_fsm;

architecture sim of tb_bist_fsm is

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal bist_start : std_logic := '0';

    signal bist_active   : std_logic;
    signal gen_opcode    : opcode_t;
    signal gen_operand_a : std_logic_vector(15 downto 0);
    signal gen_operand_b : std_logic_vector(15 downto 0);
    signal gen_start     : std_logic;

    signal chk_result       : std_logic_vector(15 downto 0);
    signal chk_result_ext   : std_logic_vector(15 downto 0);
    signal chk_result_valid : std_logic;

    signal bist_busy     : std_logic;
    signal bist_done     : std_logic;
    signal bist_pass     : std_logic;
    signal bist_fail_idx : std_logic_vector(3 downto 0);

    signal pass_count   : integer := 0;
    signal fail_count   : integer := 0;
    signal sim_finished : boolean := false;

    -- local copy of the same vector table embedded in bist_fsm, used by the
    -- mock to know what "correct" looks like for whichever vector is being
    -- requested (matched by opcode+operands rather than by a shared index,
    -- so this test doesn't depend on knowing bist_fsm's internal timing)
    type mock_vec_t is record
        opcode : opcode_t;
        a      : std_logic_vector(15 downto 0);
        b      : std_logic_vector(15 downto 0);
        exp_r  : std_logic_vector(15 downto 0);
        exp_re : std_logic_vector(15 downto 0);
    end record;
    type mock_rom_t is array (natural range <>) of mock_vec_t;

    constant MOCK_ROM : mock_rom_t := (
        ( OP_ADD, x"0005", x"0003", x"0008", x"0000" ),
        ( OP_SUB, x"000A", x"0003", x"0007", x"0000" ),
        ( OP_AND, x"F0F0", x"0FF0", x"00F0", x"0000" ),
        ( OP_OR , x"F0F0", x"0F0F", x"FFFF", x"0000" ),
        ( OP_XOR, x"FF00", x"0FF0", x"F0F0", x"0000" ),
        ( OP_NOT, x"0F0F", x"0000", x"F0F0", x"0000" ),
        ( OP_SHL, x"0001", x"0004", x"0010", x"0000" ),
        ( OP_SAR, x"8000", x"0004", x"F800", x"0000" ),
        ( OP_ROL, x"8001", x"0001", x"0003", x"0000" ),
        ( OP_MUL, x"0064", x"0064", x"2710", x"0000" ),
        ( OP_MUL, x"7FFF", x"7FFF", x"0001", x"3FFF" ),
        ( OP_DIV, x"0064", x"0007", x"000E", x"0002" ),
        ( OP_DIV, x"1234", x"0000", x"0000", x"1234" )
    );

    constant VEC_TO_CORRUPT : integer := 4;  -- XOR vector (index 4) -- deliberately wrong answer
    constant FSM_LATENCY    : integer := 6;  -- simulated multi-cycle latency for MUL/DIV in the mock

    signal mock_running : std_logic := '0';
    signal mock_cnt      : integer := 0;
    signal fsm_valid_pulse : std_logic := '0';
    signal start_seen_count : integer := 0;  -- counts how many times gen_start pulses (sanity check)

begin

    dut : entity work.bist_fsm
        port map (
            clk           => clk,
            rst           => rst,
            bist_start    => bist_start,
            bist_active   => bist_active,
            gen_opcode    => gen_opcode,
            gen_operand_a => gen_operand_a,
            gen_operand_b => gen_operand_b,
            gen_start     => gen_start,
            chk_result       => chk_result,
            chk_result_ext   => chk_result_ext,
            chk_result_valid => chk_result_valid,
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

    -----------------------------------------------------------------------
    -- Mock ALU responder
    -----------------------------------------------------------------------
    mock_resp : process (gen_opcode, gen_operand_a, gen_operand_b)
        variable match_r  : std_logic_vector(15 downto 0);
        variable match_re : std_logic_vector(15 downto 0);
        variable found     : boolean;
    begin
        match_r  := (others => '0');
        match_re := (others => '0');
        found := false;
        for i in MOCK_ROM'range loop
            if (not found) and MOCK_ROM(i).opcode = gen_opcode and
               MOCK_ROM(i).a = gen_operand_a and MOCK_ROM(i).b = gen_operand_b then
                if i = VEC_TO_CORRUPT then
                    match_r  := not MOCK_ROM(i).exp_r;   -- deliberately wrong
                    match_re := MOCK_ROM(i).exp_re;
                else
                    match_r  := MOCK_ROM(i).exp_r;
                    match_re := MOCK_ROM(i).exp_re;
                end if;
                found := true;
            end if;
        end loop;
        chk_result    <= match_r;
        chk_result_ext <= match_re;
    end process;

    mock_timing : process (clk, rst)
    begin
        if rst = '1' then
            mock_running <= '0';
            mock_cnt <= 0;
            start_seen_count <= 0;
        elsif rising_edge(clk) then
            if is_fsm_op(gen_opcode) then
                if gen_start = '1' and mock_running = '0' then
                    mock_running     <= '1';
                    mock_cnt         <= 0;
                    start_seen_count <= start_seen_count + 1;
                elsif mock_running = '1' then
                    if mock_cnt = FSM_LATENCY - 1 then
                        fsm_valid_pulse <= '1';
                        mock_running    <= '0';
                    else
                        mock_cnt <= mock_cnt + 1;
                        fsm_valid_pulse <= '0';
                    end if;
                else
                    fsm_valid_pulse <= '0';
                end if;
            else
                mock_running    <= '0';  -- not running an FSM op right now
                fsm_valid_pulse <= '0';
            end if;
        end if;
    end process;

    -- comb_valid mirrors the real alu_top's PURELY COMBINATIONAL result_valid
    -- (zero-lag w.r.t. gen_opcode) -- the mock must match this or it can
    -- create false races at comb->FSM transition boundaries that don't
    -- exist in the real hardware.
    chk_result_valid <= '1' when not is_fsm_op(gen_opcode) else fsm_valid_pulse;

    -----------------------------------------------------------------------
    -- Test sequence
    -----------------------------------------------------------------------
    stim : process
        variable cycles : integer;
    begin
        rst <= '1';
        wait for 20 ns;
        wait until rising_edge(clk);
        rst <= '0';

        -- BIST auto-runs out of reset; wait (with watchdog) for bist_done
        cycles := 0;
        while bist_done = '0' and cycles < 200 loop
            wait until rising_edge(clk);
            cycles := cycles + 1;
        end loop;

        if bist_done /= '1' then
            fail_count <= fail_count + 1;
            report "FAIL: watchdog timeout, bist_done never asserted" severity error;
        else
            pass_count <= pass_count + 1;
            report "bist_done asserted after " & integer'image(cycles) & " cycles";
        end if;

        wait for 1 ns;
        if bist_pass = '0' then
            pass_count <= pass_count + 1;
        else
            fail_count <= fail_count + 1;
            report "FAIL: expected bist_pass=0 (fault injected at vector " &
                   integer'image(VEC_TO_CORRUPT) & ")" severity error;
        end if;

        wait for 1 ns;
        if bist_fail_idx = std_logic_vector(to_unsigned(VEC_TO_CORRUPT, 4)) then
            pass_count <= pass_count + 1;
        else
            fail_count <= fail_count + 1;
            report "FAIL: bist_fail_idx=" & integer'image(to_integer(unsigned(bist_fail_idx))) &
                   " expected=" & integer'image(VEC_TO_CORRUPT) severity error;
        end if;

        -- sanity: exactly 4 FSM-type vectors (2 MUL + 2 DIV) in the ROM,
        -- so gen_start should have pulsed exactly 4 times
        wait for 1 ns;
        if start_seen_count = 4 then
            pass_count <= pass_count + 1;
        else
            fail_count <= fail_count + 1;
            report "FAIL: gen_start pulse count=" & integer'image(start_seen_count) &
                   " expected=4" severity error;
        end if;

        -- re-trigger via bist_start and confirm it runs again
        bist_start <= '1';
        wait until rising_edge(clk);
        bist_start <= '0';
        wait for 1 ns;
        if bist_busy = '1' then
            pass_count <= pass_count + 1;
        else
            fail_count <= fail_count + 1;
            report "FAIL: bist_busy did not reassert after bist_start re-trigger" severity error;
        end if;

        cycles := 0;
        while bist_done = '0' and cycles < 200 loop
            wait until rising_edge(clk);
            cycles := cycles + 1;
        end loop;
        if bist_done = '1' then
            pass_count <= pass_count + 1;
        else
            fail_count <= fail_count + 1;
            report "FAIL: bist_done never reasserted after re-trigger" severity error;
        end if;

        wait for 20 ns;
        report "=================================================";
        report "bist_fsm unit TB complete. PASS=" &
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
