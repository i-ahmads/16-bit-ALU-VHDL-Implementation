# Synthesis Results

**Toolchain:** Xilinx ISE 14.7 / XST
**Target device:** xc7a100t-3csg324 (Artix-7), speed grade -3

Figures below are pulled directly from the real XST synthesis reports (`.syr` files), included as-is in [`synthesis_reports/`](synthesis_reports/) alongside the `.xst` synthesis scripts and HTML design summaries used to produce them. The VHDL synthesized here is code-identical to what's in `src/` (confirmed by diff — the only difference found was a cosmetic architecture-name change in `bist_fsm`, `behavioral` → `rtl`, with no functional effect).

## Device utilization — `alu_top` (Tier 1 + BIST, full design)

| Resource | Used |
|---|---:|
| Slice Registers | 199 / 126,800 |
| Slice LUTs | 690 / 63,400 |
| LUT Flip-Flop pairs used | 732 |
| Bonded IOBs | 85 / 210 |

**Timing:** minimum period 6.245 ns → **Fmax = 160.12 MHz**.

## Device utilization — algorithm comparison

| Resource | `booth_mult_fsm` (via `alu_top`) | `shift_add_mult_fsm` (standalone) | `restoring_div_fsm` (via `alu_top`) | `non_restoring_div_fsm` (standalone) |
|---|---:|---:|---:|---:|
| Slice Registers | *(shared in alu_top total above)* | 90 | *(shared in alu_top total above)* | 90 |
| Slice LUTs | *(shared in alu_top total above)* | 183 | *(shared in alu_top total above)* | 120 |
| Fmax | *(shared in alu_top total above)* | 211.44 MHz | *(shared in alu_top total above)* | 406.39 MHz |

> The Booth multiplier and restoring divider were only synthesized as part of the full `alu_top` design (their individual resource contribution isn't broken out separately in that report), while the two comparison alternatives were synthesized standalone — so the comparison here is most meaningful on **Fmax** and **relative area between the two comparison modules themselves**, not a direct apples-to-apples LUT count against `alu_top`'s shared total.

**Findings:** `non_restoring_div_fsm` synthesizes both smaller (120 vs 183 LUTs) and much faster (406 vs 211 MHz) than `shift_add_mult_fsm`, and dramatically faster than the full `alu_top` (160 MHz) — consistent with it being a narrower, standalone combinational-shift-and-subtract circuit without the shared flags/BIST/mux logic that dominates `alu_top`'s critical path.

## Raw report files

- [`synthesis_reports/alu_top.syr`](synthesis_reports/alu_top.syr) / `.xst` / `_summary.html` — full `alu_top` synthesis report, script, and Design Summary.
- [`synthesis_reports/shift_add_mult_fsm.syr`](synthesis_reports/shift_add_mult_fsm.syr) / `.xst` / `_summary.html` and [`non_restoring_div_fsm.syr`](synthesis_reports/non_restoring_div_fsm.syr) / `.xst` / `_summary.html` — standalone synthesis of the two comparison algorithms.
- [`schematics/alu_top/RTL/`](schematics/alu_top/RTL/) — RTL schematic viewer screenshots (top view, and each submodule: combinational ALU, Booth multiplier, restoring divider, flags unit, BIST FSM).
- [`schematics/alu_top/Technology/`](schematics/alu_top/Technology/) — post-synthesis technology (gate-level) schematic screenshots.
- [`schematics/compare/`](schematics/compare/) — RTL/Technology schematics for both comparison algorithms.
- [`waveforms/alu_top/`](waveforms/alu_top/) — ISim waveform screenshots, one set per testbench (top-level ALU, BIST, Booth multiplier, combinational ALU, flags unit, restoring divider).
- [`waveforms/compare/`](waveforms/compare/) — ISim waveform screenshots for both comparison algorithms, including per-signal close-ups (operands, product/quotient/remainder).

## Power

Not captured — an XPower Analyzer run wasn't part of this synthesis pass. Treat any power figure elsewhere as provisional until a real XPower run is done and dropped in here.
