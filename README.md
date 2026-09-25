# 16-bit ALU — VHDL Implementation

**Course:** EEE413/ECE413 Digital System Design, BRAC University
**Group:** Group 4, Section 02
**Members:** Sujana Haque (22221007), Intisar Ahmed (22221111), Tanvir Jubaer (22321052), Satirtha Saha (22321058), Mahdi Abrar Yousuf (22321069)

A 16-bit ALU built up in tiers: a combinational core, an FSM-controlled multiply/divide datapath, and a built-in self-test (BIST) layer, all verified in GHDL and synthesized on Xilinx ISE targeting an Artix-7 FPGA.

This repository contains source code, testbenches, and verification/synthesis results only. The written report and slide deck are maintained separately and are not included here.

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

---

## Repository layout

```
src/     7 synthesizable VHDL source files
tb/      6 self-checking testbenches
results/ verification and synthesis results (this is the "findings" section)
docs/    design notes, bugs found, and known limitations
```

## Toolchain

| Purpose | Tool |
|---|---|
| Simulation | GHDL 4.1.0 (mcode backend, `--std=93`) |
| Waveform viewing | GTKWave |
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
