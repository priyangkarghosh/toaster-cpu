# Testbenching: ModelSim/QuestaSim under Quartus

Read this when writing or debugging a testbench for an RTL design (e.g. the RISC-V core) using Quartus' bundled ModelSim/QuestaSim flow. This covers directed self-checking SystemVerilog testbenches, not UVM — UVM is generally overkill for a single-core, single-author project, and Quartus/Questa starter editions often lack full UVM library support.

## Project Setup Basics

- Keep the testbench out of the synthesis fileset. In Quartus, only add DUT/RTL files to the project; compile the testbench separately into the simulation library (`vsim`/`vlog`), or use a separate `.qsf` simulation file list so synthesis never sees `initial`, `$display`, classes, or other testbench-only constructs.
- Use Quartus' "EDA Tool Settings" to point at ModelSim/Questa and generate the simulation script (`msim_setup.tcl` or similar) rather than hand-writing `vlog`/`vsim` invocations from scratch — it pre-populates the correct vendor simulation libraries (e.g., `altera_mf`, `lpm`, device-family primitives) that your RTL may instantiate indirectly through inferred RAMs/PLLs.
- If your design instantiates Quartus-inferred memory (block RAM) or PLL megafunctions, the post-synthesis gate-level netlist needs vendor simulation models on top of the RTL-level testbench — keep RTL-level (functional) and gate-level (post-fit) simulation as separate `vsim` configurations; don't try to share one testbench unmodified between them, since gate-level sim needs SDF timing and the vendor cell libraries.

## Directed Self-Checking Testbench Structure

A self-checking testbench beats one you watch a waveform for — write it to pass/fail on its own from the start.

- Structure: a clock/reset generator block, a stimulus (driver) process, a DUT instance, and a checker process — kept as separate `always`/`initial` blocks or separate tasks, not interleaved in one giant `initial` block.
- Drive stimulus through tasks with descriptive names (`apply_instruction(addr, data)`, `wait_for_retire()`) rather than raw `force`/timing-delay sequences repeated inline — this also makes directed-test files read like a test plan.
- Use a scoreboard pattern for a pipelined core: maintain a reference model (even a simple behavioral one, or a golden trace from a reference ISA simulator like Spike) and compare retired-instruction results (PC, destination register, written value) against it every cycle an instruction retires, rather than only checking final register-file state at the end. End-of-test-only checking finds *that* something is wrong but not *which instruction* caused it.
- Self-check with `assert` (immediate) inside the checker process, and have every assertion failure print enough context (PC, cycle count, expected vs actual) to debug from the log alone — assume you will be reading this log without the waveform open.
- Always include a watchdog timeout (`fork`/`join_any` with a cycle-count kill task, or a `disable fork` pattern) so a stalled or deadlocked DUT ends the simulation with a clear failure message instead of running forever in batch regression.

## Clock and Reset in the Testbench

- Generate the clock with a simple `forever #(PERIOD/2) clk = ~clk;` in an `initial` block; don't try to model clock jitter/duty cycle imperfection unless you're specifically testing for it — it adds noise to waveform debug for no benefit pre-silicon.
- Apply reset for several clock cycles, deasserting on a clock edge (synchronous deassertion in the testbench, mirroring the synchronizer-protected deassertion discipline from the RTL guidelines) so the DUT always starts from a clean, repeatable state across every test run, including in regression scripts that don't deal with `$random` seeds carefully.
- Seed `$random`/`$urandom` explicitly (don't let it default) and log the seed at the start of every random-stimulus run — an irreproducible random failure is close to useless for debugging a pipeline hazard bug.

## SVA Patterns for Pipeline Checking

These complement the directed scoreboard above — concurrent assertions catch protocol violations the scoreboard's end-result checking might miss.

```systemverilog
// No instruction retires with reg_write asserted into x0
property no_writeback_to_x0;
  @(posedge clk) disable iff (!rst_n)
  (wb_valid && wb_reg_write) |-> (wb_rd != 5'd0);
endproperty
assert property (no_writeback_to_x0);

// A stalled stage must not silently lose its instruction
property stall_holds_instruction;
  @(posedge clk) disable iff (!rst_n)
  (stage_stall) |=> ($stable(stage_instr));
endproperty
assert property (stall_holds_instruction);

// valid stays high until the consuming stage accepts it
property valid_until_accepted;
  @(posedge clk) disable iff (!rst_n)
  (valid && !accept) |=> valid;
endproperty
assert property (valid_until_accepted);
```

- Bind assertion modules into the DUT (`bind dut_module assertion_module ...`) rather than editing the RTL files to add assertions in-line — keeps them out of the synthesis fileset automatically and keeps the checker reusable across testbenches.
- Wrap assertion code with `` `ifdef SYNTHESIS`` guards as a second line of defense even when using bind files, per the main coding guidelines.

## Per-Instruction Functional Testing (e.g. `func_tb.sv`)

If you maintain a dedicated functional testbench whose job is "every instruction the ISA defines actually executes correctly" (as opposed to a directed hazard/pipeline test or a standalone unit test), structure it as a checklist-driven test rather than a handful of representative instructions:

- Maintain an explicit list of every opcode/instruction your core implements (base RV32I, plus M-extension `mul`/`mulh`/`mulhsu`/`mulhu`/`div`/`divu`/`rem`/`remu` if implemented) as data — a SystemVerilog array of instruction encodings plus expected results, or an external file the testbench reads — rather than as one-off hand-written test cases scattered through the file. This makes "did we cover every instruction" a question you can answer by inspection of the list, not by re-reading the whole testbench.
- For each instruction, test at least: a typical operand pair, the zero operand(s) case, and the operand-width boundary case (most-negative/most-positive signed value, all-ones unsigned) — the same boundary-case discipline as the MDU edge cases in `references/mdu-verification.md`, applied across the whole ISA rather than just the multiply/divide unit.
- Run each test instruction through the *actual pipeline* (fetch through writeback), not a bypassed/direct-execute path — the point of this test is to catch decode mistakes, hazard interactions, and forwarding bugs that a unit-level ALU test wouldn't see, so don't undermine that by injecting pre-decoded micro-ops directly into EX.
- Self-check against expected architectural state (destination register value, and for stores/loads, memory contents) after each instruction retires, with a clear "PASS: opcode X" / "FAIL: opcode X, expected Y got Z" log line per instruction — when you eventually add a new instruction or fix a decode bug, you want a one-line regression result per opcode, not a single pass/fail for the entire test.
- Consider cross-checking against a reference RISC-V ISA simulator (e.g. Spike, or `riscv-tests`/`riscv-arch-test` if you want external, pre-validated test vectors) once your own per-instruction list is solid — external suites are good for catching ISA-spec misunderstandings your own hand-written expected values might share with your implementation's misunderstanding of the same spec.



- Functional coverage (`covergroup`/`coverpoint`) is worth adding once directed tests stabilize, specifically over: opcode mix, hazard combinations actually exercised (load-use stall, back-to-back forwarding, branch-misprediction-during-stall), and reset-during-operation. You don't need full UVM to get coverage — a `covergroup` sampled from your existing checker process works fine standalone.
- For a single-core project, prioritize a hand-written directed test list that walks through every hazard/forwarding/flush combination in `references/riscv-pipeline.md` over chasing high random-coverage numbers — pipeline correctness bugs are usually combinational-corner-case bugs that targeted tests find faster than constrained-random.

## Debugging Sim/Synth Mismatch Specifically

If a test passes in ModelSim/Questa but fails on hardware (or in Quartus's post-fit gate-level sim):
1. Re-check the "Problematic Code Patterns" section of the main SKILL.md first — `full_case`, mixed blocking/non-blocking, and X-propagation differences are the most common root causes of "works in sim, fails on board."
2. Re-run the *same* functional testbench against the gate-level netlist with SDF timing if available — this isolates "RTL logic bug" from "timing/synthesis-introduced behavior difference."
3. Check whether any X-propagating signal (uninitialized register, unconnected port) is being read by an `if` before it's ever driven — simulation may take the `else` branch deterministically while synthesis optimizes the X away, producing genuinely different logic.
