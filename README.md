# TinyML-Accelerator

TinyML-Accelerator is a major project focused on building a TinyML accelerator on top of a RISC-V based hardware platform.

## Current Repository Layout

- `RISC-V/`: Vendored Verilog implementation of a 5-stage pipelined RV32I core and related modules.
- `picorv32/`: Vendored PicoRV32 core from YosysHQ.
- `midsem_sim/`: Self-contained systolic-array simulation flow for mid-sem evaluation.
- `integration/pcpi_demo/`: First PicoRV32+PCPI+accelerator integration demo.
- `README.md`: Top-level project documentation.

## Vendored RISC-V Core

This repository currently includes the upstream core as a vendor copy (not a submodule):

- Upstream: `https://github.com/srpoyrek/RISC-V`
- Imported on: `2026-02-28`
- Import metadata: `RISC-V/VENDORING.md`

The `RISC-V/` folder is tracked directly by this repo, and `RISC-V/.git` is intentionally removed.

## Upstream Core Summary

Based on the upstream README, the core includes:

- 5-stage pipelined RISC-V architecture (RV32I)
- Verilog HDL implementation
- Modules such as control unit, hazard detection, forwarding, ALU, and memory-related blocks
- Testbench-based verification (ModelSim-oriented upstream setup)

## Next Development Focus

- Show simulation-first progress in mid-sem using `midsem_sim`.
- Stabilize accelerator + custom instruction interface in simulation before FPGA deployment.
- Transition from analytic speedup estimates to measured board timings (ARM and `mcycle`).

## Core Integration Status

- Accelerator is currently validated in standalone RTL simulation (`midsem_sim`).
- PicoRV32 is vendored and available in-repo (`picorv32/`).
- A first CPU integration milestone is implemented in simulation via PCPI (`integration/pcpi_demo`).
- Custom instruction path is tested with machine-code loaded directly in testbench memory.
- PCPI demo now uses matrix base pointers (rs1/rs2), reads A/B from memory, and writes C buffer back to memory.
- Firmware scaffold is added (`firmware.S`, linker script, Makefile, hex generation path) with fallback hex support when toolchain is unavailable.
- Full board deployment is still pending.

## Planned Core Integration Path

1. Add a proven integration-ready RV32 core (recommended: PicoRV32).
2. Wrap the accelerator with a coprocessor/custom-op interface (`start`, `busy`, `done`).
3. Add decode/handshake logic so a custom instruction triggers matrix multiply.
4. Build CPU+accelerator simulation testbench and verify correctness plus stall behavior.
5. Replace analytic speedup estimates with measured cycle counts (`mcycle` / ARM timing).
6. Move to Vivado/Pynq-Z2 hardware integration after simulation sign-off.

## Midsem Simulation Quick Start

Run from repository root:

```powershell
.\midsem_sim\scripts\run_midsem_sim.ps1
```

Generated artifacts:

- `midsem_sim/results/sim_output.log`
- `midsem_sim/results/MIDSEM_RESULTS.md`

## PCPI Integration Demo Quick Start

Run from repository root:

```powershell
.\integration\pcpi_demo\scripts\run_pcpi_demo.ps1
```

Generated artifacts:

- `integration/pcpi_demo/results/pcpi_demo.log`
- `integration/pcpi_demo/results/pcpi_demo_wave.vcd`

## PCPI 8-Case Regression Quick Start

Run from repository root:

```powershell
.\integration\pcpi_demo\scripts\run_pcpi_regression.ps1
```

Generated artifacts:

- `integration/pcpi_demo/results/cases/*.log`
- `integration/pcpi_demo/results/pcpi_regression_summary.md`
- `integration/pcpi_demo/results/pcpi_regression_summary.json`

## PCPI Handoff Validation Quick Start

Run from repository root:

```powershell
.\integration\pcpi_demo\scripts\run_pcpi_handoff.ps1
```

Generated artifacts:

- `integration/pcpi_demo/results/pcpi_handoff.log`
- `integration/pcpi_demo/results/pcpi_handoff_wave.vcd`
- `integration/pcpi_demo/results/pcpi_handoff_summary.md`
