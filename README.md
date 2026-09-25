# 16-bit ALU — VHDL Implementation
A 16-bit ALU built up in tiers: a combinational core, an FSM-controlled multiply/divide datapath, and a built-in self-test (BIST) layer, all verified in GHDL and synthesized on Xilinx ISE targeting an Artix-7 FPGA.
This repository contains source code, testbenches, and verification/synthesis results only. The written report and slide deck are maintained separately and are not included here.


---

## Design at a glance

The screenshots below come from the project's Xilinx ISE schematic viewer and ISim simulations. Open an image for a closer look at signals and labels.

### RTL architecture

![Top-level RTL schematic of the 16-bit ALU](results/schematics/alu_top/RTL/1.%20RTL%20top%20view.JPG)

*Top-level RTL view: the ALU interface and its main synthesized blocks.*

![Expanded RTL schematic showing the ALU's internal connections](results/schematics/alu_top/RTL/2.%20RTL%20middle%20view.JPG)

*Expanded RTL view: how the combinational path, iterative arithmetic, flags, and BIST logic connect. See the [full schematic set](results/schematics/alu_top/RTL/) for module-level views.*

### Simulation examples

![ISim waveform from the top-level ALU testbench](results/waveforms/alu_top/1.%20top%20alu%20part%201.JPG)

*Top-level simulation: inspect inputs, operation selection, outputs, and control timing. The [second waveform capture](results/waveforms/alu_top/2.%20top%20alu%20part%202.JPG) continues the trace.*

![ISim waveform from the Booth multiplier testbench](results/waveforms/alu_top/4.%20booth%20mult%20tb.JPG)

*Booth multiplier simulation: the iterative multiplication path is exercised by the signed test vectors. The [waveform collection](results/waveforms/alu_top/) also includes division, flags, combinational operations, and BIST.*

### Synthesis view and measured results

![Post-synthesis technology schematic of the ALU](results/schematics/alu_top/Technology/9.%20Inner%20view.JPG)

*Technology view: a closer view of the mapped hardware after synthesis; the [top-level technology view](results/schematics/alu_top/Technology/8.%20tech%20top.JPG) is available separately. This schematic illustrates structure, while the XST report supplies the resource and timing numbers.*

| Check | Reported result |
|---|---:|
| Self-checking GHDL assertions | 84/84 pass across six primary testbenches |
| ALU slice LUTs | 690 / 63,400 |
| ALU slice registers | 199 / 126,800 |
| XST estimated minimum period | 6.245 ns (160.12 MHz) |

These are the results recorded in [verification](results/testbench_results.md) and [synthesis](results/synthesis_results.md). The timing figure is an XST synthesis estimate for the specified Artix-7 target, not a measured clock rate on a physical board.

---

## Architecture

### Combinational core (`combinational_alu.vhd`)
ADD, SUB, AND, OR, XOR, NOT, logical/arithmetic shifts, and rotates — pure combinational logic, one cycle latency (i.e. zero extra cycles beyond the request).

### Tier 1 — FSM-controlled multiply/divide
- **`booth_mult_fsm.vhd`** — 16×16 → 32-bit **signed** multiplication using radix-4 (modified) Booth recoding. 4-state FSM (`ST_IDLE → ST_LOAD → ST_COMPUTE → ST_DONE`), 8 compute cycles (2 bits retired per cycle). 18-bit guard width on the accumulator/multiplicand to prevent overflow before the arithmetic right shift.
- **`restoring_div_fsm.vhd`** — 16/16-bit **unsigned** restoring division. Same 4-state FSM shape, 16 compute cycles (1 quotient bit per cycle). Divide-by-zero short-circuits straight from `LOAD` to `DONE` with `div_by_zero='1'`.
- **`flags_unit.vhd`** — one shared flags block serving both the combinational and FSM paths. Zero/Parity use a shared wide reduction tree regardless of which datapath produced the result; Carry/Overflow are opcode-selected (adder carry/signed-overflow for ADD/SUB, range-overflow for MUL, divide-by-zero for DIV).

### Tier 2 — BIST and hardening
- **`bist_fsm.vhd`** — an independent 3-state Moore FSM (`ST_BIDLE → ST_BRUN → ST_BDONE`), deliberately shaped differently from the MUL/DIV FSMs so it isn't a scaled-down copy. Auto-runs a ROM of known-good vectors on reset (covering every opcode, one MUL-overflow case, one DIV-by-zero case) and asserts pass/fail + first-failing-vector index. Drives the *same* combinational/FSM datapath instances used in normal operation rather than a separate golden copy.
- Clock-enable power gating, resource-shared adder/subtractor, and a registered output stage are part of the finalized Tier 2 architecture.

### Tier 3 (stretch, time-permitting)
Hamming SEC on the output result register; Gray-code FSM iteration counter.

### Top level (`alu_top.vhd`)
Wires the above together. Combinational ops resolve same-cycle (`result_valid='1'` immediately). MUL/DIV are started with a `start` pulse; `busy` goes high and `result_valid` pulses once the FSM finishes. `result_ext` carries the extension word (Booth `product_hi` / division `remainder`) for MUL/DIV, and is zero for combinational ops. While BIST is active, external `result_valid` is gated low so a caller can't mistake BIST-internal traffic for its own request.

### Algorithm comparison (`src/compare/`, added per professor feedback)
- **`shift_add_mult_fsm.vhd`** — conventional shift-and-add multiplier, same interface as `booth_mult_fsm.vhd`, 16 compute cycles (1 bit/cycle) vs. Booth's 8.
- **`non_restoring_div_fsm.vhd`** — non-restoring division, same interface as `restoring_div_fsm.vhd`, adds a final `ST_CORRECT` step versus restoring division's pure 4-state shape.

Both are tested against the **identical vectors** as their Tier 1 counterparts (`tb/compare/tb_shift_add_mult_fsm.vhd`, `tb/compare/tb_non_restoring_div_fsm.vhd`), each also synthesized standalone. See [`results/synthesis_results.md`](results/synthesis_results.md) for the resulting area/Fmax comparison.

---

## Repository layout

```
src/          7 synthesizable VHDL source files (Tier 1 + Tier 2 finalized design)
src/compare/  2 alternative-algorithm sources (shift-add multiplier, non-restoring divider)
tb/           6 self-checking testbenches
tb/compare/   2 testbenches for the comparison algorithms
results/      verification results, synthesis reports, RTL/Technology schematics, ISim waveforms
docs/         design notes, bugs found, and known limitations
```

## Toolchain

| Purpose | Tool |
|---|---|
| Simulation | GHDL 4.1.0 (mcode backend, `--std=93`) |
| Waveform viewing | Xilinx ISim / GTKWave |
| Synthesis | Xilinx ISE 14.7 / XST |
| Target device | xc7a100t-3csg324 (Artix-7) |

## Running the testbenches (GHDL)

```bash
cd src
ghdl -a --std=93 alu_pkg.vhd combinational_alu.vhd flags_unit.vhd \
        booth_mult_fsm.vhd restoring_div_fsm.vhd bist_fsm.vhd alu_top.vhd
cd ../tb
ghdl -a --std=93 tb_combinational_alu.vhd
ghdl -e --std=93 tb_combinational_alu
ghdl -r --std=93 tb_combinational_alu
# repeat -a/-e/-r for the other five testbenches
```

See [`results/testbench_results.md`](results/testbench_results.md) for expected output.

---

## Status

See [`results/testbench_results.md`](results/testbench_results.md) and [`results/synthesis_results.md`](results/synthesis_results.md) for full verification and synthesis numbers, and [`docs/findings.md`](docs/findings.md) for bugs found and design notes.

Real RTL/Technology schematic screenshots and ISim waveform captures (from the actual Xilinx ISE project) are in [`results/schematics/`](results/schematics/) and [`results/waveforms/`](results/waveforms/).
