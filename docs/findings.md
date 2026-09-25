# Design Notes, Findings, and Known Limitations

## Bugs found during simulation (not just code review)

- **BIST ROM divide-by-zero expected value.** An early version of the BIST vector ROM had the wrong expected remainder for the divide-by-zero test vector. Caught only because `tb_bist_fsm` runs the control-logic FSM against a mock responder that can be made to disagree with the ROM — a pure code review would not have surfaced it.
- **ISim-specific overflow-flag bug.** In ISim (not GHDL), the overflow flag stuck high due to a dynamic aggregate comparison. Fixed by switching that comparison to an integer comparison. This is one of the reasons both GHDL and ISim are used in verification — some bugs only show up in one simulator.

## Key design decisions

- **Shared flags block.** `flags_unit` is instantiated once and serves both the combinational path and the FSM (MUL/DIV) path. Zero/Parity are computed from a single wide reduction tree regardless of which datapath produced the result; Carry/Overflow are opcode-selected internally. This was a deliberate resource-sharing choice, not just convenience.
- **BIST is a genuinely different FSM shape.** `bist_fsm` (3-state Moore machine, ROM-vector-indexed) was deliberately built as a different shape from the 4-state `booth_mult_fsm` / `restoring_div_fsm` (fixed-iteration-count, bit-serial) so it doesn't read as a scaled-down copy of the same FSM pattern reused three times.
- **BIST exercises the real datapath.** `bist_fsm` drives `gen_*` stimulus onto the *same* `combinational_alu` / `booth_mult_fsm` / `restoring_div_fsm` instances used for normal operation (via the `eff_*` mux in `alu_top`), rather than a separate golden copy — that's the actual BIST philosophy being tested, not just a name.
- **Guard bits in Booth multiplication.** The accumulator and sign-extended multiplicand use `DATA_WIDTH+2 = 18` bits so the ±2M additions used in radix-4 recoding never overflow before the arithmetic right shift.
- **Restoring division's divide-by-zero short-circuit.** If the divisor is zero at `LOAD` time, the FSM skips `COMPUTE` entirely and goes straight to `DONE` with `div_by_zero='1'`; quotient/remainder are explicitly undefined in that case and downstream consumers must check the flag.

## Explicitly out of scope

- Signed division (Tier 1 is unsigned-only division by design; would need a magnitude-convert/divide/reapply-sign extension).
- Reversible logic, QCA, full ECC beyond Hamming SEC, Vedic multiplier — considered and deliberately excluded from this project's scope.
- Any RISC-V infrastructure — this is a standalone ALU project, kept independent in both implementation and citation sourcing from the separate RISC-V pipeline project.

## Verified against golden models before being committed to VHDL

- Booth multiplier: cross-checked against a Python golden model over 2000+ random signed 16×16 products, all exact.
- Restoring divider: cross-checked against a Python golden model over 3000+ random unsigned 16/16 divisions, all exact.

## On the horizon / not yet in this repository

- Tier 3 stretch goals (Hamming SEC on the output register, Gray-code FSM iteration counter) — implemented only if time permits.
- `shift_add_mult_fsm.vhd` and `non_restoring_div_fsm.vhd` — conventional-algorithm comparison alternatives built per professor feedback (22/22 and 17/17 passing respectively against the same vector sets as their Tier 1 counterparts). Not included in `src/` in this snapshot; add them here if/when their source is available separately from the report.
- XPower Analyzer before/after power numbers for the Tier 2 gating changes — to be measured, not asserted.
