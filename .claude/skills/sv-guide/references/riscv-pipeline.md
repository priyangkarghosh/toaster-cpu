# RISC-V Pipelined Core — Coding Patterns

Read this when working on a pipelined (e.g. classic 5-stage IF/ID/EX/MEM/WB) RISC-V core: hazard handling, forwarding, CSR/exception logic, and the bugs most specific to this design shape. The general SystemVerilog rules in the main SKILL.md still apply on top of everything here.

## Pipeline Register Discipline

- Give every inter-stage register bundle a packed struct type, defined in a shared package: `if_id_t`, `id_ex_t`, `ex_mem_t`, `mem_wb_t`. Bundling the PC, instruction, control signals, and operands into one struct per stage boundary avoids the bit-slicing errors that come from dozens of loose stage-delay registers.
- Every stage register is `always_ff`, non-blocking, with a *single* clear reset/bubble value (typically all-zero, decoding to a NOP). Don't reset some fields and leave others X — a partially-reset bubble can look like a valid instruction with garbage operands and pass silently through later stages.
- Decide once whether stalls are modeled as "hold the register" (clock-enable on the stage register) or "force a bubble" (mux a NOP into the register input) and apply that choice uniformly. Mixing the two styles across stages is a common source of duplicated or dropped instructions under back-to-back stalls.

## Hazard Detection and Forwarding

- Compute hazard/forward signals combinationally in the same stage that needs to *consume* the forwarded value (typically ID or EX), not in the stage that produces it. Forwarding logic that lives in the producing stage tends to grow hidden one-cycle lag bugs.
- Forwarding muxes are pure combinational selects on rs1/rs2 addresses against later-stage destination registers — write them with `unique case` or a `priority if` chain ordered from *most recent* producer to *oldest*, so the closest in-flight result wins when multiple stages could forward the same register.
- Always special-case `rd == 0` (architectural x0) in hazard detection — comparisons that forward into or hazard-check against x0 writes are a frequent off-by-one source of spurious stalls, since x0 writes are real instructions but must never observe as a hazard.
- Load-use hazards (a load's result needed by the immediately following instruction) generally cannot be solved by forwarding alone — you need a one-cycle stall (bubble in EX) because the loaded value isn't available until MEM. Don't try to forward a not-yet-valid MEM-stage load result; gate the forward path on a registered "load in flight" signal and stall instead.

## Branch/Jump Resolution and Flushing

- Decide explicitly which stage resolves branches (ID with a static/early predictor, or EX after the ALU/comparator) and squash (flush) every stage *between* fetch and the resolving stage on a misprediction — flushing too few stages leaves a stale instruction live; flushing too many discards work you didn't need to discard.
- A flush and a stall can be requested in the same cycle (e.g., a load-use stall in EX while a branch resolves in EX too) — define and document priority between them explicitly; don't let it fall out implicitly from `if`/`else if` ordering that nobody wrote down.
- Flush by forcing a bubble into the stage register's *input* (so the flushed instruction's bubble is what gets clocked in), not by gating the clock or suppressing the write — gating clocks combinationally is already disallowed by the general guidelines and is doubly dangerous here since it can desync the PC and instruction paths.

## CSRs, Exceptions, and Traps

- Model the CSR file as its own module with a clean read/write port pair, decoded from the `funct3`/CSR-address fields in EX or a dedicated CSR-access stage — don't scatter individual CSR registers (e.g. `mstatus`, `mcause`, `mepc`) as loose signals through the datapath.
- Exceptions can be detected in *any* stage (illegal instruction in decode, misaligned address in mem, ecall/ebreak in execute). Carry an `exception_valid` + `exception_cause` field through the pipeline struct from the stage that detects it, and only commit/act on it once it reaches a single designated stage (commonly WB or a dedicated trap stage) — this guarantees in-order exception handling even though detection is distributed.
- When an exception commits, flush everything younger in the pipeline (same mechanism as a branch misprediction) and load the PC from the trap vector; save the faulting PC into `mepc` and the cause into `mcause` in the same cycle.
- `unique case` on `mcause`/trap-cause encoding so an unhandled or reserved cause value is caught by the simulator instead of silently falling through.

## Common Pipeline-Specific Bugs to Check For

- **Stale control signals surviving a flush**: a flushed bubble must zero out write-enables (`reg_write`, `mem_write`) as well as the opcode — a bubble with a garbage instruction field but a stale `reg_write=1` will corrupt the register file.
- **PC/instruction desync**: anywhere the PC register and the instruction register for the same stage are updated by *different* enable/stall conditions, they can drift apart over a stall. Drive both from the same stage-register struct, updated by the same enable.
- **Double counting on stalls**: performance counters (retired-instruction count, cycle count) incremented in a stage that can be held by a stall will overcount unless gated by the same valid/enable signal that gates the stage register itself.
- **Forwarding into x0 or across a flushed bubble**: validate the *valid* bit of the producing stage's struct, not just that the destination register field happens to match — a flushed bubble can still have a leftover `rd` field if you didn't fully clear it (see the reset-discipline note above).

## Package Organization for a RISC-V Core

Suggested split, all under one `riscv_pkg`:
- Opcode/funct3/funct7 encodings as `localparam logic [N:0]`.
- CSR addresses as `localparam logic [11:0]`.
- The inter-stage struct typedefs (`if_id_t`, `id_ex_t`, `ex_mem_t`, `mem_wb_t`).
- ALU operation enum, forwarding-source enum (e.g. `FWD_NONE`, `FWD_EX_MEM`, `FWD_MEM_WB`).

Keeping these in one package (imported explicitly per-symbol per the main guidelines, not via wildcard) means the datapath, hazard unit, and testbench can all share the same encodings without redefinition drift.
