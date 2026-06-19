---
name: sv-guide
description: SystemVerilog RTL coding guidelines, plus RISC-V pipelined-core-specific patterns, multiplier/divider (MDU) verification, and Quartus/ModelSim testbenching guidance. Use whenever writing, reviewing, or debugging SystemVerilog — module/FSM/RAM coding style, sim/synth mismatch bugs (blocking vs non-blocking, latches, full_case, X-propagation, CDC), anything involving a RISC-V pipeline (hazards, forwarding, CSRs, exceptions), a Booth-Wallace multiplier or SRT4 divider, or a ModelSim/Questa testbench under Quartus. Trigger this for code review of .sv/.v files, RTL bug triage ("why does sim differ from hardware/synthesis"), pipeline hazard bugs, MDU correctness bugs, and testbench authoring/debugging — even if the user doesn't say "style guide" explicitly.
---

# SystemVerilog Design Guidelines (RISC-V Core Focus)

This skill encodes coding conventions for synthesizable SystemVerilog, with a second layer for pipelined RISC-V cores and Quartus/ModelSim testbenching. Apply the rules below to any RTL you write or review. Read the reference files when the task matches their topic — don't load them speculatively.

## How to use this skill

1. Apply the core coding rules below to every block of RTL you write or review — these are general-purpose and always relevant.
2. If the task touches a RISC-V pipeline (hazards, forwarding, stalls, CSRs, exceptions, branch resolution) → read `references/riscv-pipeline.md`.
3. If the task touches the multiplier or divider unit (Booth-Wallace multiplier, SRT4 divider, or any other iterative/multi-cycle arithmetic unit) → read `references/mdu-verification.md`.
4. If the task involves writing or debugging a testbench, especially under ModelSim/Questa + Quartus → read `references/testbenching.md`.
5. When reviewing existing code, scan it against the "Problematic Code Patterns" section first — those are the bugs most likely to cause silent sim/synth mismatch, which is the hardest class of bug to catch by inspection alone.

---

## 1. Types and Declarations

- Prefer `logic` over `reg`/`wire` in all new code. Reserve `wire` for true multi-driver nets (tri-state buses, wired-or).
- Use ANSI-style port declarations (ports declared inline in the module header), not legacy non-ANSI two-section style.
- Use sized, based literals: `8'd0`, `1'b1`, `16'hFF` — never bare `0`, `1`, `255` for anything that matters to width or sign.
- Use `localparam` for constants instead of magic numbers.
- Add explicit types to parameters to avoid lint warnings: `parameter integer X = 1`, `parameter [15:0] X = 16'd1`, `localparam logic [4:0] STATE_IDLE = 5'd0`.
- For integer parameters used as booleans, compare explicitly: `if (PARAM != 0)` not `if (PARAM)`; `(PARAM == 0)` not `!PARAM`.
- For truncation to a narrower width, size explicitly: `VALUE[N:0]` or `N'(VALUE)` — never rely on implicit truncation.

## 2. Assignments and Processes

- `<=` (non-blocking) in `always_ff` / `always @(posedge clk)` for all registered outputs.
- `=` (blocking) only in `always_comb`, `initial`, or for true local temporaries inside a sequential block (a variable that is fully computed and consumed within the same always_ff invocation, never read across clock edges).
- Never mix blocking and non-blocking assignment to the *same variable*, even in different blocks.
- Use `always_ff` for registered logic, `always_comb` for combinational logic. Avoid bare `always @(*)` — see Tool Pitfalls.
- In `always_comb`, every assigned variable must be assigned on every path (no implicit latches).
- Don't read a signal on the RHS in a combinational process before it's been assigned on the LHS in that same process — this implies a latch or a feedback loop, not a wire.

## 3. Module Port Ordering

- Consistent order: clocks, resets, control/config inputs, data inputs, data outputs, status outputs.
- One signal/port per line.

## 4. Problematic Code Patterns (Avoid These)

### Race Conditions and Sim/Synth Mismatch
- **Never use blocking (`=`) in sequential blocks.** Order-dependent simulation results, possible sim/synth mismatch. Always `<=` for registered outputs.
- **Never drive the same variable from more than one `always` block.** Undefined, tool-dependent behavior.
- **Never use `#0` delays** to paper over races — they add nondeterminism and hide the real bug.
- **Accumulation operators** (`+=`, `++`) are blocking; in sequential logic, expand them: `cnt <= cnt + 1'b1`, not `cnt += 1`.

### full_case / parallel_case
- **Avoid the synthesis directives `full_case` and `parallel_case`** (as `// synthesis full_case` pragma comments). They're comments to the simulator but commands to synthesis — classic sim/synth mismatch source. Use `unique case` / `priority case` instead; these are real language constructs with matching sim and synth semantics.

### Latches
- Incomplete `if`/`case` in `always_comb` infers a latch. Assign every output on every path, or add `default:`.
- A `default:` branch alone doesn't guarantee latch-free logic — every variable must still be covered inside every branch, including the default.

### Multiple Drivers and Combinational Loops
- Never drive one signal from multiple `always_comb` blocks. A `generate`-for that creates one `always_comb` per iteration, all driving the same signal, is illegal — put the loop body *inside* one `always_comb`.
- Don't give `always_comb` outputs initial values — an initializer is an implicit second driver.
- Avoid combinational feedback (a signal feeding back to its own combinational input with no register in the loop) — causes oscillation/non-convergence and tool warnings.

### Signed/Unsigned and Width
- If any operand in an expression is unsigned, the whole expression is evaluated unsigned and sign-extension silently fails. Use `$signed()` / `$unsigned()` explicitly, or match operand types.
- Size explicitly (`VALUE[N:0]` or `N'(VALUE)`) at width boundaries and read synthesis "signed-to-unsigned"/width-mismatch warnings — they are usually real bugs, not noise.

### Mixed Sequential and Combinational
- Blocking and non-blocking assignment to the same variable in one block is a synthesis error in most tools. Pick one style per variable, for its whole lifetime.
- Non-blocking assignment inside `always_comb` is wrong — it uses the *old* value (one-cycle lag) rather than updating immediately. Non-blocking belongs only in `always_ff`.

### X-Propagation
- `if (x_signal)` takes the `else` branch in simulation when `x_signal` is X, but synthesis treats X as don't-care. This is a major, hard-to-catch sim/synth mismatch source, especially on uninitialized registers and unconnected inputs.
- Use four-state types (`logic`) in simulation. Two-state types (`bit`, `int`) silently mask X bugs by initializing to 0.
- If your tool supports an X-propagation simulation mode (Xcelium `xprop`, VCS `xprop`), turn it on for regression — it catches reset-sequencing and uninitialized-register bugs that a clean compile won't.

### Tool Pitfalls
- Use `always_comb`, not `always @(*)` — some tools mishandle wildcard sensitivity lists, especially with function calls inside the block.
- Avoid arrayed interfaces in ports (ISim/Vivado). Avoid functions/tasks inside interfaces (VCS). Avoid interfaces as top-level ports (flattening during synthesis causes port-name mismatch against the RTL).
- Avoid generic names like `length`, `size`, `out`, `in` — they can collide with built-in system function/task names or vendor IP signal names.

## 5. Case Statements

- Always terminate a `case` with `default:`, or use `unique case`/`priority case` to get the same latch protection from the language itself.
- `unique case`: asserts all cases are mutually exclusive *and* exhaustive — simulator issues a runtime warning if two branches match or none do.
- `priority case`: asserts exhaustive coverage but allows overlapping conditions (first match wins, like a priority encoder).

## 6. Enumerated Types and Typedefs

- `typedef enum logic [N:0] { ... }` for FSM states and mode selectors — the explicit width avoids width-mismatch lint warnings at every point of use.
- `typedef struct packed { ... }` for bundled signals (e.g. a control-word, an instruction-decode bundle) instead of manual bit-slicing.
- Put shared typedefs in a package, not in a header included everywhere.

## 7. Packages

- Use packages for shared types, parameters, constants (opcode encodings, CSR addresses, pipeline-stage widths, etc. — see the RISC-V reference for what belongs here on a core).
- Prefer explicit `pkg::symbol` references over wildcard `import pkg::*`, which can silently shadow local names as the package grows.

## 8. FSM Coding Style

- Two-process style: one `always_ff` for the state register, one `always_comb` for next-state + output logic. Don't merge them — mixing state update and next-state computation in one `always_ff` makes outputs registered when you may want them combinational (Moore vs Mealy gets muddled).
- Declare states with `typedef enum logic [N:0]` and explicit width.
- In the next-state `always_comb`, set a default next-state (typically "stay in current state") *before* the `case`, so every state you forget to handle explicitly still has a defined transition.
- Use `unique case` on the state variable so the simulator flags any reachable-but-unhandled state at runtime rather than silently latching.

## 9. Clock, Reset, and CDC

- Naming: `clk`, `rst_n` (active-low async) or `arst_n` if you need to distinguish async from a separate sync reset elsewhere in the same design. Pick one reset polarity/style for the whole core and document it once, not per-module — a pipelined core with mixed reset styles across stages is a common source of X-on-reset bugs (see `references/riscv-pipeline.md`).
- Never gate a clock with hand-written combinational logic. Use a vendor clock-gating cell, or in FPGA flows, a clock-enable on the register instead of gating the clock net itself.
- **Never sample an asynchronous input directly.** Use a 2-stage (minimum) synchronizer in the receiving clock domain. A single flop is a metastability risk.
- **Multi-bit CDC:** don't pass several correlated bits through independent single-bit synchronizers — they can resolve on different cycles and the receiver sees a value that never existed on the sending side. Use gray coding for counters, or a full handshake/FIFO scheme for buses.
- **Async reset deassertion is the dangerous edge, not assertion.** Assert the reset asynchronously, but synchronize its *release* (assert async, deassert sync) through a small synchronizer chain so every flop in the domain comes out of reset on the same clock edge.
- Document every CDC boundary in the design and which synchronizer scheme protects it — this is the first thing a verification engineer (or future you) needs when debugging an intermittent failure.

## 10. Assertions (SVA)

- Immediate assertions (`assert(expr)`) for procedural sanity checks (e.g., "this case should be unreachable").
- Concurrent assertions (`assert property (...)`) for protocol/timing checks that span multiple cycles (e.g., "valid must stay high until ready").
- Guard synthesis-only builds with `` `ifdef SYNTHESIS`` around assertion code, or keep assertions in a separate bind file, so they never reach the synthesis netlist.
- See `references/testbenching.md` for SVA patterns specific to pipeline checking (no dropped instructions, stall correctness, etc.).

## 11. Memory / RAM Inference

- Write single-port and dual-port RAM using your vendor's recommended template (Quartus has specific inferable patterns for M9K/M20K/etc.) so synthesis maps to block RAM rather than registers.
- Don't reset memory arrays — a reset on the array prevents block RAM inference on most FPGA families and silently falls back to register-based memory (huge area surprise).
- Add `(* ramstyle = "..." *)` (Quartus attribute name; `ram_style` is the Xilinx spelling) when the tool needs an explicit hint to pick block RAM over registers.

## 12. Generate Blocks

- Always label generate blocks: `gen_slice : for (genvar g = 0; ...)`. Unlabeled generates produce unreadable hierarchical instance names and make waveform debug much harder.
- Remember generate scope: a variable declared inside a generate block is per-instance, not shared across iterations.

## 13. Synthesis-Safe Coding

- `initial` blocks are ignored by ASIC synthesis entirely. FPGA tools may use them for RAM initialization, but never rely on an `initial` block for register reset values — use an explicit reset.
- Never use `force`/`release`, `deassign`, or procedural continuous `assign` in synthesizable code — testbench-only constructs.
- Avoid `real`, `time`, `string`, and other non-synthesizable types in RTL; confine them to the testbench.

## 14. Instances and Interfaces

- In generate blocks, prefix indexed instances `u_` or `i_`: `u_slice_i[g]`.
- Use `modport` in interfaces to give DUT and testbench distinct, restricted views of the same signal bundle.

## 15. Files and Formatting

- Spaces, not tabs.
- One declaration per line.
- One module per file; file name matches module name.

---

## Reference Files

- `references/riscv-pipeline.md` — hazard/forwarding/stall coding patterns, CSR and exception/trap handling idioms, and the bugs specific to 5-stage (or similar) pipelined cores.
- `references/mdu-verification.md` — coding and verification patterns specific to a multi-cycle multiplier/divider unit (Booth-Wallace multiplier, SRT4 divider): control FSM pitfalls, edge cases, and directed test patterns.
- `references/testbenching.md` — directed SystemVerilog testbenches for ModelSim/QuestaSim under Quartus, self-checking patterns, instruction-level (per-opcode) functional coverage, and lightweight SVA-based checking that doesn't require a full UVM environment.