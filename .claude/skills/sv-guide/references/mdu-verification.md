# MDU Verification — Booth-Wallace Multiplier, SRT4 Divider

Read this when working on the multiply/divide unit: a Booth-encoded Wallace-tree multiplier (`bwall_multiplier` / `units/multiplier`) and an SRT4 (radix-4 subtractive) divider (`units/divider`), or the shared MDU control wrapping them (`mdu.sv`). These units are multi-cycle and iterative internally even though the surrounding pipeline may treat the MDU as a single functional unit, which is the source of most of the bugs below.

## Why This Differs From Pipeline Verification

The 5-stage pipeline hazard/forwarding logic in `references/riscv-pipeline.md` assumes single-cycle EX. The MDU breaks that assumption: a multiply or divide takes multiple cycles internally, so the MDU needs its own busy/done handshake with the pipeline, and the arithmetic core itself (Booth-Wallace, SRT4) needs correctness verification independent of how it's wired into the pipeline. Treat these as two separate verification problems:

1. **Arithmetic correctness of the unit in isolation** — does the multiplier/divider produce the right bits for every input class, tested standalone via `bwall_multiplier_tb.sv` / `srt4_divider_tb.sv`.
2. **Handshake correctness with the pipeline** — does the MDU correctly stall/hold the pipeline while busy, and not corrupt or double-issue when a new operation starts before the old one's result is consumed — tested at the `datapath_tb.sv`/integration level, not standalone.

Bugs that pass (1) and fail (2), or vice versa, are common — keep the test plans separate even though both target the same unit.

## Booth-Wallace Multiplier

### Coding Patterns
- Booth recoding (radix-4 Booth is the common choice) operates on overlapping 3-bit windows of the multiplier; get the window indexing and the encode table (`-2, -1, 0, +1, +2` per Booth digit) into a single function or always_comb block with a `unique case`, not inlined repeatedly per partial product — a single bug in inline-duplicated encode logic is much harder to spot than one in a shared block.
- The Wallace tree reduction (carry-save adders compressing partial products) is naturally a `generate`-built structure — label every level (`gen_csa_level0`, `gen_csa_level1`, ...) per the general generate-block guidance, since debugging a wrong-bit-somewhere-in-the-tree problem without labeled hierarchy is extremely painful.
- The final carry-propagate addition (converting the last sum/carry pair out of the Wallace tree into a single binary result) is a normal binary adder — don't let the Booth/Wallace-specific logic leak into it; keep it a clean, separately-testable adder instance.
- If the multiplier is signed (most RV32M `mul`/`mulh` variants need both signed and unsigned/mixed forms), handle sign extension of the partial products explicitly per the general signed/unsigned guidance — Booth recoding already produces signed digits, and silently double-handling sign extension (once in Booth recoding, again at the top level) is a frequent source of off-by-one-bit errors specifically at the MSB.
- `mulh`/`mulhu`/`mulhsu` need the upper 32 bits of a 64-bit product, with different operand sign treatment for each. Verify all three are wired to the correct half of the same underlying full-width product, rather than three separately-coded paths that can drift out of sync.

### Edge Cases to Test
- `0 * X`, `X * 0`, `0 * 0`.
- `1 * X`, `X * 1` (degenerate Booth digit, often mishandled if the recoding table has an implicit "skip when all-zero window" shortcut).
- Most-negative operand (`32'h80000000` as a signed input) — squaring or multiplying this against itself is the classic signed-multiplier corner case, since its magnitude has no positive two's-complement counterpart.
- All-ones operand (`-1` signed / `0xFFFFFFFF` unsigned) against itself and against `0x80000000`.
- Maximum positive × maximum positive, to check the full-width product doesn't truncate silently.
- A few pseudo-random operand pairs cross-checked against a software reference (even `$signed(a) * $signed(b)` computed directly in the testbench as the golden model, since SystemVerilog's own `*` operator is a valid oracle for a *structural* implementation you're verifying bit-for-bit).

## SRT4 Divider

### Coding Patterns
- SRT4 is iterative: each cycle produces 2 quotient bits via a quotient-digit-selection (QDS) lookup on a truncated view of the partial remainder, then updates the partial remainder. Model this as a clean `always_ff` (remainder/quotient registers) plus `always_comb` (next-remainder computation and QDS lookup) two-process style, same discipline as the FSM coding guidance — don't fold the iteration into one block.
- The QDS table is usually implemented as a small lookup (often a ROM/case table indexed by a few truncated divisor and remainder bits). Encode it with `unique case` so an out-of-range index is caught by the simulator rather than silently returning a don't-care digit.
- A radix-4 step produces a quotient digit in a redundant signed-digit set (e.g. `{-2,-1,0,1,2}`); the on-the-fly conversion to a standard binary quotient at the end is a separate piece of logic from the iteration itself — verify it standalone with known redundant-digit sequences before trusting end-to-end divider results.
- Divider control (iteration counter, start/done) belongs in its own small FSM (state register + next-state per the general FSM guidance), not folded into the datapath registers — keep the "how many cycles have we done" question entirely separate from "what is the remainder right now."

### Edge Cases to Test
- **Division by zero** — RISC-V defines specific results for `div`/`divu`/`rem`/`remu` by zero (quotient = all-ones, remainder = dividend unchanged); this is an architectural requirement, not a "don't care," and is the single most commonly missed case in a from-scratch SRT4 implementation. Special-case it explicitly rather than expecting the SRT4 iteration to organically produce the architecturally-defined result — division by zero is not a normal SRT4 input and the iterative algorithm will not naturally converge to the RISC-V-mandated answer.
- **Overflow case**: most-negative dividend (`0x80000000`) divided by `-1` for signed `div` — RISC-V defines this to return the dividend itself (overflow), not a trap; verify your divider's signed-overflow special case matches this exactly, since the SRT4 core has no natural way to detect it.
- Dividend smaller than divisor (quotient = 0, remainder = dividend).
- Dividend exactly divisible (remainder = 0).
- Most-negative dividend or divisor in signed division generally, beyond the overflow case above — sign handling for SRT4 typically converts to unsigned magnitudes first and reapplies sign at the end; the most-negative value has no positive magnitude representation in the same bit width, so this conversion step needs explicit handling.
- Iteration-count boundary: divisor/dividend pairs that should finish in the minimum number of iterations vs. the maximum, to make sure the iteration counter's terminal condition is exactly right (off-by-one here either drops the last quotient digit or runs one extra garbage cycle).

## Standalone Unit Testbenches (`bwall_multiplier_tb.sv`, `srt4_divider_tb.sv`)

- Self-check against the operator-level golden model in the same testbench (`$signed(a)*$signed(b)` for the multiplier; for the divider, SystemVerilog's `/` and `%` operators on `logic` operands behave as unsigned division — for the signed RISC-V semantics, compute the golden quotient/remainder with explicit `$signed()` casts and apply the RISC-V divide-by-zero/overflow special cases in the testbench's reference model too, not just in the DUT).
- Sweep the documented edge cases above as directed vectors first; add constrained-random operand pairs after the directed list passes, with assertion-based self-checking so a regression run with thousands of random vectors still reports pass/fail without manual waveform inspection.
- For the divider specifically, since it's iterative, check not just the final quotient/remainder but that `done`/`busy` toggles on the correct cycle relative to the iteration count — an off-by-one in the done signal will look correct in isolation (final value is right) but will desync the MDU/pipeline handshake when integrated.

## Integration Testing (MDU ↔ Pipeline Handshake)

This is what `datapath_tb.sv` or a dedicated MDU-integration test should check, beyond what the standalone unit tests cover:
- Pipeline correctly stalls (per the stall-discipline guidance in `references/riscv-pipeline.md`) for the entire multi-cycle latency of a multiply/divide, and resumes on exactly the cycle `done` asserts — not one cycle early (sampling a not-yet-valid result) or late (an extra stall cycle that's easy to miss in a passing test but wastes performance).
- Back-to-back MDU operations (a second `mul`/`div` issued the cycle after the first completes) don't see stale `busy`/`done` state from the previous operation — verify the busy/done handshake fully resets between operations, not just on the very first operation after reset.
- A flush (branch misprediction or exception) arriving *while* the MDU is mid-operation correctly aborts/restarts the MDU's internal state rather than leaving it busy forever (which would deadlock the pipeline) or leaving stale partial state for the next operation to inherit.
