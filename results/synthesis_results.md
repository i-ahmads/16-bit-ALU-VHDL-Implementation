# Synthesis Results

**Toolchain:** Xilinx ISE 14.7 / XST
**Target device:** xc7a100t-3csg324 (Artix-7)

> These figures come from an XST synthesis run of the finalized Tier 1 + Tier 2 (BIST) architecture. They are real reported device-utilization numbers, not estimates — GHDL/simulation-only verification (see `testbench_results.md`) does not by itself produce these; they require the actual Xilinx toolchain, which isn't available in this repository's CI environment, so they're recorded here as a point-in-time synthesis snapshot rather than something regenerated automatically on every commit.

## Device utilization (`alu_top`, full design)

| Resource | Used |
|---|---:|
| Slice registers | 199 |
| LUTs | 690 |
| Bonded IOBs | 85 |

## Power

Power numbers (XPower Analyzer, before/after the Tier 2 clock-enable gating and resource-shared adder/subtractor changes) are **not yet included here** — they need to be re-verified against a real XPower Analyzer run on the current architecture rather than asserted from memory. Treat any power claim elsewhere as provisional until that run is done and the real numbers are dropped in here.

## Reproducing this synthesis

1. Open Xilinx ISE 14.7, create a new project targeting `xc7a100t-3csg324`.
2. Add all files under `src/` (in the order: `alu_pkg.vhd`, `combinational_alu.vhd`, `flags_unit.vhd`, `booth_mult_fsm.vhd`, `restoring_div_fsm.vhd`, `bist_fsm.vhd`, `alu_top.vhd`).
3. Set `alu_top` as the top-level entity.
4. Run "Synthesize - XST", then check the Design Summary for slice register / LUT / IOB counts, and (optionally) run XPower Analyzer for power estimates.
