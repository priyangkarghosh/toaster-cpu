---
name: modelsim-run
description: Compile and run a SystemVerilog testbench in this Quartus 18.1 Lite + ModelSim Starter project, capture the transcript, and report pass/fail. Use whenever the user asks to run, simulate, exercise, or verify a `*_tb.sv` file in this repo — e.g. "run the csr testbench", "sim csr_tb", "does the divider TB still pass", "run my latest TB and tell me what broke". Also use after authoring a new TB and you want to self-verify before reporting back.
---

# Run a SystemVerilog Testbench in ModelSim

This skill captures the working CLI invocation for `vsim` against this project. ModelSim-Intel FPGA Starter Edition 10.5b is on the user's PATH (`vsim`, `vlog`, `vlib`). Quartus is 18.1 Lite, SV dialect SYSTEMVERILOG_2005.

## Procedure

### 1. Identify the TB and its dependencies

Read the TB file. Note:
- The top module name (matches the file's `module xxx_tb;`).
- Every `import pkg::*;` — collect those packages.
- Every module instantiated (the DUTs).
- Any modules those DUTs depend on (one level of digging is usually enough; the user will tell you if there's more).

Compile order matters: **packages first, then leaf modules, then modules that instantiate them, TB last.** ModelSim does not auto-resolve order across `vlog` arguments — they are compiled left-to-right.

A common gotcha: package files end in `_pkg.sv` (e.g. `riscv_pkg.sv`, `unit_pkg.sv`) and MUST precede any file that imports them.

### 2. Prep the work library

The project already has `simulation/modelsim/` with a `modelsim.ini`. Reuse it. Recreate the work lib to avoid stale-cache mismatches:

```powershell
if (Test-Path simulation\modelsim\work) { Remove-Item -Recurse -Force simulation\modelsim\work }
vlib simulation\modelsim\work
```

### 3. Compile

```powershell
$proj = (Get-Location).Path -replace '\\','/'
vlog -sv -work simulation/modelsim/work `
    "$proj/src/<pkg>.sv" `
    "$proj/src/<dut>.sv" `
    "$proj/testbenches/<tb>.sv" 2>&1 | Out-String
```

Pipe stderr+stdout together (`2>&1 | Out-String`) so PowerShell shows compiler errors inline. The `-sv` flag forces SystemVerilog parsing.

A clean compile ends with `Errors: 0, Warnings: 0`. Stop and fix any errors before running — silent compile failures cause `vsim` to report a load error that is much less useful than the `vlog` diagnostic.

### 4. Run

```powershell
vsim -c -lib simulation/modelsim/work <tb_module_name> -do "run -all; quit -f" 2>&1 | Out-String
```

- `-c` runs console mode (no GUI). Required when invoking from this harness.
- `-lib` points at the work library you built in step 2.
- `-do "run -all; quit -f"` executes the entire `initial` block and exits. Without `quit -f`, ModelSim hangs at the `$stop` waiting for an interactive prompt.

### 5. Triage the output

The TB transcript is the entire stdout of step 4. Walk through it looking for:
- `# FAIL ...` lines (case-sensitive; this repo's TBs use `PASS`/`FAIL` prefixes).
- `# ** Error:` from ModelSim itself (load error, X-propagation, divide-by-zero, etc.).
- The summary line (`ALL TESTS PASSED` or `*** FAILURES DETECTED ***`) — this comes from the TB's own bookkeeping, not the simulator.
- `WATCHDOG: ... hung` — the TB self-aborted because something stalled. Almost always a missed handshake (`done` never asserts) or a forgotten `csr_en` deassertion that wedges a state machine.

When reporting back to the user, summarize: number of PASS, list each FAIL with the case name, note any non-test errors.

## Conventions specific to this repo

- TBs live in `testbenches/`, source in `src/` and subdirs.
- Packages: `src/riscv_pkg.sv` (decoded opcode types, pipeline structs) and `src/units/unit_pkg.sv` (MDU/ALU enums). Most TBs need at least `riscv_pkg`.
- The Quartus-generated `simulation/toaster-cpu_run_msim_rtl_verilog.do.bak*` files show *how Quartus nativelink invokes vsim* for the project as a whole — useful as a reference for the giant lib list (`-L altera_ver`, etc.), but for unit TBs **don't add those `-L` flags** unless the TB instantiates an Altera megafunction. Plain RTL TBs work with the bare `vsim -c -lib ...` command above.
- The repo has bak files in `simulation/` — those are Quartus's auto-saved scripts, don't edit or delete them.

## When the user asks to open the GUI instead

Drop `-c` and `-do "run -all; quit -f"`:

```powershell
vsim -lib simulation/modelsim/work <tb_module_name>
```

But default to console mode — it's faster, captures cleanly into the transcript, and doesn't fight the harness.

## When the TB needs files

Some TBs read memory init files via `$readmemh`/`$readmemb`. Those paths are evaluated relative to the simulator's working directory, which is the directory `vsim` was launched from. If a TB uses relative paths like `"test.txt"`, `cd` into the directory that holds the file (often the repo root or `simulation/`) before running, or pre-stage the file there.
