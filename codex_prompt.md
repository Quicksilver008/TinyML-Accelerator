# Codex Handoff Prompt (Compaction-Safe)

Last updated: 2026-03-05

This file is the single source of truth to resume work after context compaction.

## Copy-Paste Prompt For Next Codex Session

```text
Read codex_prompt.md fully and continue from the current repository state without restarting.

Mandatory first actions:
1) Show `git branch --show-current` and `git status --short`.
2) Re-run `.\integration\pcpi_demo\scripts\run_pcpi_regression.ps1`.
3) Re-run `.\integration\pcpi_demo\scripts\run_pcpi_handoff.ps1`.
4) Confirm whether all regression + handoff checks still pass and report summary lines.

Then continue from "Immediate Next Work (Do In Order)" in codex_prompt.md.
Do not change arithmetic semantics: use RTL-exact Q5.10 wrap behavior.
Keep all flows script-driven and reproducible.
Update codex_prompt.md again at the end with what changed.
```

## Project Intent

Build a TinyML-oriented matrix accelerator flow on RISC-V (final target: Pynq-Z2), with simulation-first credibility now and hardware integration after.

## Current Repo Snapshot

- Repository root: `TinyML-Accelerator`
- Active working branch: `omar`
- Important note: there are uncommitted local changes in docs and `integration/` content in this workspace.

## What Is Implemented And Verified

### A) Vendor setup

1. Vendored `RISC-V/` from `https://github.com/srpoyrek/RISC-V` (as vendor copy, no nested `.git`).
2. Vendored `picorv32/` from `https://github.com/YosysHQ/picorv32`.

### B) Mid-sem standalone accelerator simulation

`midsem_sim/` includes RTL + TB + scripts and passes baseline tests.

### C) PicoRV32 + PCPI integration demo

Directory: `integration/pcpi_demo`

Implemented:
1. PCPI wrapper: `rtl/pcpi_tinyml_accel.v`
2. CPU integration TB: `tb/tb_picorv32_pcpi_tinyml.v`
3. Firmware flow: `firmware/firmware.S`, `firmware/sections.lds`, `firmware/Makefile`
4. Smoke script: `scripts/run_pcpi_demo.ps1`

Behavior:
1. Custom instruction over PCPI.
2. `rs1/rs2` interpreted as A/B base pointers.
3. Wrapper reads A/B from memory, runs accelerator, writes C to `0x200`.
4. TB checks both returned `c00` and full C buffer.

### D) Firmware-driven matrix input path

No matrix hardcoding in TB for functional vectors.
Firmware provides A and B (`a_init`, `b_init`) and copies to RAM before custom op.

### E) 8-case scripted regression suite (new)

Added:
1. Case manifest: `integration/pcpi_demo/tests/cases.json`
2. Generator: `integration/pcpi_demo/tests/gen_case_firmware.py`
3. Regression runner: `integration/pcpi_demo/scripts/run_pcpi_regression.ps1`
4. TB case label plusarg support: `+CASE_NAME=<name>`

Regression semantics:
1. signed16 multiply
2. arithmetic right shift by 10
3. signed32 accumulation
4. final compare on wrapped low16, sign-extended to 32-bit

Case set:
1. `identity_x_sequence`
2. `zero_x_random`
3. `random_x_zero`
4. `neg_identity`
5. `mixed_sign_small`
6. `near_wrap_positive`
7. `rand_seed_42`
8. `rand_seed_1234`

Last verified result:
1. `run_pcpi_regression.ps1` executed all 8 cases.
2. Summary showed `Pass: 8`, `Fail: 0`.

### F) Mixed-instruction handoff validation (new)

Added:
1. Firmware: `integration/pcpi_demo/firmware/firmware_handoff.S`
2. Testbench: `integration/pcpi_demo/tb/tb_picorv32_pcpi_handoff.v`
3. Runner: `integration/pcpi_demo/scripts/run_pcpi_handoff.ps1`
4. Results note: `integration/pcpi_demo/HANDOFF_TEST_RESULTS.md`

What this validates:
1. CPU executes custom instruction #1.
2. CPU executes regular instructions (`lw`, `sw`, `addi`) in between custom ops.
3. CPU executes custom instruction #2.
4. PCPI handshake correctness for both custom ops (`wait -> ready/wr`).
5. Accelerator memory writeback count is correct for two matrix outputs.

Latest observed pass metrics from handoff run:
1. First result sentinel: `0x00000400`
2. Regular marker write: `0x0000047b`
3. Second result sentinel: `0xfffffc00`
4. `custom_issue_count=2`
5. `ready_count=2`
6. `wr_count=2`
7. `handshake_ok_count=2`
8. `c_store_count=32`

## Toolchain Status

### Windows native

- `riscv64-unknown-elf-gcc` not available natively in this machine environment.

### WSL fallback (validated)

- Installed and working in WSL:
  - `riscv64-unknown-elf-gcc`
  - `binutils-riscv64-unknown-elf`
  - `make`
- Firmware builds in WSL via:
  - `make clean all PYTHON=python3`

Regression script automatically uses:
1. native toolchain if available
2. otherwise WSL fallback
3. fails clearly if neither path is available

## Commands That Should Work Now

From repo root (`TinyML-Accelerator`):

1. Smoke demo:
```powershell
.\integration\pcpi_demo\scripts\run_pcpi_demo.ps1
```

2. Full 8-case regression:
```powershell
.\integration\pcpi_demo\scripts\run_pcpi_regression.ps1
```

3. Generate one specific firmware case manually:
```powershell
python .\integration\pcpi_demo\tests\gen_case_firmware.py --cases .\integration\pcpi_demo\tests\cases.json --case identity_x_sequence --firmware-out .\integration\pcpi_demo\firmware\firmware.S --meta-out .\integration\pcpi_demo\results\cases\identity_x_sequence.expected.json
```

4. Rebuild firmware in WSL manually:
```powershell
wsl bash -lc "cd '/mnt/c/Users/moham/OneDrive/Desktop/Major Project/TinyML-Accelerator/integration/pcpi_demo/firmware' && make clean all PYTHON=python3"
```

## Generated Evidence Files

1. `integration/pcpi_demo/results/cases/*.log`
2. `integration/pcpi_demo/results/pcpi_regression_summary.md`
3. `integration/pcpi_demo/results/pcpi_regression_summary.json`

Note: summary and per-case expected JSON are currently ignored via `.gitignore`.

## Important Operational Notes

1. `run_pcpi_regression.ps1` rewrites `firmware/firmware.S` and `firmware/firmware.hex` for each case.
2. After regression, firmware ends on the last case unless explicitly reset.
3. In this workspace, firmware was reset to `identity_x_sequence` after regression for predictable smoke behavior.
4. TB now prints `TB_INFO case=...` using optional plusarg; functional behavior unchanged.

## Immediate Next Work (Do In Order)

1. Stabilize commit boundaries:
   - Separate commits for:
     - regression infrastructure
     - docs updates
     - any unrelated existing changes
2. Add a C firmware variant for PCPI demo:
   - keep current assembly path
   - add optional C-based test program with explicit custom instruction macro
3. Add CI-style local checker script:
   - one command that runs smoke + regression and exits non-zero on any failure
4. Start architecture-ready integration prep:
   - define memory-mapped/control contract for future SoC/FPGA top-level
   - keep arithmetic and instruction encoding unchanged

## Not In Scope Yet

1. Full board deployment on Pynq-Z2
2. ARM vs accelerator measured board timings
3. Replacing arithmetic behavior with saturation

## Definition Of Done For Next Milestone

1. Regression flow remains green (`8/8 pass`) after any new changes.
2. C firmware variant added and runnable (without breaking assembly flow).
3. One-command verification script added and documented.
4. `README.md` and this file updated with exact commands and observed outputs.
