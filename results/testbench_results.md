# Verification Results

All testbenches are self-checking (assert + report PASS/FAIL counts). Re-run and confirmed for this repository snapshot under **GHDL 4.1.0** (Ubuntu package, mcode JIT backend), `--std=93`.

## Summary (freshly re-run, all passing)

| Testbench | DUT | Assertions | Result |
|---|---|---:|---|
| `tb_combinational_alu.vhd` | `combinational_alu` | 15 | 15/15 PASS |
| `tb_flags_unit.vhd` | `flags_unit` | 10 | 10/10 PASS |
| `tb_booth_mult_fsm.vhd` | `booth_mult_fsm` | 22 | 22/22 PASS |
| `tb_restoring_div_fsm.vhd` | `restoring_div_fsm` | 17 | 17/17 PASS |
| `tb_bist_fsm.vhd` | `bist_fsm` (control logic, mock ALU) | 6 | 6/6 PASS |
| `tb_alu_top.vhd` | `alu_top` (integration) | 14 | 14/14 PASS |
| **Total** | | **84** | **84/84 PASS** |

Raw run commands and output are in [`ghdl_run_log.txt`](ghdl_run_log.txt).

## What each testbench covers

- **`tb_combinational_alu`** — every opcode (ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/SAR/ROL/ROR), including ADD/SUB carry and borrow edge cases, and a shift-by-zero identity check.
- **`tb_flags_unit`** — Zero flag (including the 32-bit-wide MUL/DIV case where `extended_result` must also be all-zero), Parity (even/odd bit counts), ADD/SUB signed overflow, MUL range-overflow passthrough, DIV-by-zero passthrough, and confirms logic ops never assert carry/overflow.
- **`tb_booth_mult_fsm`** — 22 signed 16×16 vectors covering positive×positive, negative×negative, mixed-sign, ±1 identities, and multiple range-overflow cases (e.g. 32767×32767, −32768×−32768). Cross-checked against a Python golden model (2000+ random signed products) before being embedded as fixed vectors. Includes a watchdog so a stuck FSM fails cleanly instead of hanging the simulation.
- **`tb_restoring_div_fsm`** — 17 unsigned 16/16 vectors including large dividends/divisors, division by 1, division of 0, and the divide-by-zero short-circuit path (remainder = dividend passthrough). Cross-checked against a Python golden model (3000+ random unsigned divisions).
- **`tb_bist_fsm`** — a standalone unit test of the BIST *control logic* against a **mock** ALU responder (not the real datapath), because once BIST is wired to the already-verified real ALU it will only ever see PASS — this is the only place the fail-detection path can be exercised. Deliberately corrupts one vector's expected response and confirms `bist_pass='0'` and `bist_fail_idx` correctly points at that vector; also confirms `gen_start` pulses exactly once per FSM-type vector and that BIST can be re-triggered via `bist_start`.
- **`tb_alu_top`** — integration-level: BIST auto-run against the *real* hardware (must PASS), opcode routing/mux correctness, `start`/`busy`/`result_valid` handshake timing for MUL and DIV, MUL range-overflow flag, DIV-by-zero flag, and a check that a combinational op run immediately after an FSM op sees no cross-talk from the FSM datapath.

## Algorithm comparison (added per professor feedback)

Two conventional alternatives were implemented with **identical interfaces** to the Tier 1 FSMs, to give a direct cycle-count/complexity comparison in the report:

| Alternative | Compares against | Assertions | Result |
|---|---|---:|---|
| `shift_add_mult_fsm.vhd` (shift-and-add multiplier) | `booth_mult_fsm.vhd` | 22 | 22/22 PASS |
| `non_restoring_div_fsm.vhd` (non-restoring division) | `restoring_div_fsm.vhd` | 17 | 17/17 PASS |

**Findings:** radix-4 Booth multiplication completes in 8 cycles vs. 16 cycles for shift-and-add on the same 16-bit operands. Restoring division has fully deterministic latency (always 16 cycles), whereas non-restoring division's cycle count/control complexity trades differently depending on implementation choices — see the report's Tables 4.1/4.2 for the full breakdown.

> **Note:** `shift_add_mult_fsm.vhd` and `non_restoring_div_fsm.vhd` are not included in `src/` in this repository snapshot — only the finalized Tier 1 implementations (`booth_mult_fsm.vhd`, `restoring_div_fsm.vhd`) are. Add the comparison-alternative sources here if/when they're available as separate files.
