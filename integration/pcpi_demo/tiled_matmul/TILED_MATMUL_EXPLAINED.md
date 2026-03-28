# Tiled NxN Matmul Explained

This note explains how the additive tiled matrix-multiplication layer works, how live real inputs are supported, and what each file in the tiled flow is responsible for.

## Big Picture

The hardware is still only a `4x4` matrix accelerator.

The new tiled flow adds a software layer that:
1. accepts a larger square `NxN` matrix problem,
2. breaks it into logical `4x4` tiles,
3. feeds those tiles to the existing accelerator,
4. accumulates partial sums in software,
5. writes the final `NxN` result matrix back to memory.

So the larger-matrix support is **not** a hardware change. It is a software orchestration layer on top of the current PCPI custom instruction flow.

## Why The First Version Did Not Look Tabulated

The first tiled compare runner was per-case only.

That meant:
1. each run produced one summary markdown/json pair,
2. but there was no aggregate benchmark table across all tiled cases,
3. and there was no live real-input wrapper yet.

That is why the results did not initially look like the earlier 4x4 benchmark presentation.

This branch now adds:
1. live real-input conversion for square `NxN`,
2. a dedicated live 3-way compare runner,
3. a benchmark summary runner that tabulates all tiled cases into one table.

Benchmark outputs now land at:
1. `integration/pcpi_demo/results/tiled_matmul/tiled_benchmark_summary.md`
2. `integration/pcpi_demo/results/tiled_matmul/tiled_benchmark_summary.json`

## How The Tiled Accelerator Path Works

For a square matrix multiply `C = A x B`, the tiled accelerator path does:

1. choose one output tile position `(row0, col0)`,
2. initialize a software `4x4` accumulator tile to zero,
3. iterate `k0` across the shared dimension in steps of 4,
4. pack one `4x4` tile from full `A` at `(row0, k0)`,
5. pack one `4x4` tile from full `B` at `(k0, col0)`,
6. zero-pad any out-of-range elements when `N` is not a multiple of 4,
7. write those tiles into the fixed accelerator staging buffers,
8. invoke the existing custom instruction once,
9. read back the `4x4` result tile from the fixed C staging buffer,
10. accumulate that tile into the software tile accumulator,
11. after all `k0` tiles are processed, write the final tile accumulator into the full `NxN` output matrix.

## Why Software Accumulation Is Needed

The current accelerator computes:
1. one `4x4 x 4x4 -> 4x4` output tile,
2. with no input C tile for fused accumulation.

So for larger `NxN` multiplication, partial results across the tile-`k` dimension must be added in software.

## Why The Tiled Firmware Is Linked At `0x4000`

The wrapper RTL still uses fixed staging-buffer addresses:
1. tile A at `0x100`,
2. tile B at `0x140`,
3. tile C at `0x200`.

When the tiled firmware grew larger than the old 4x4 smoke firmware, its program text overlapped those staging-buffer addresses.

That caused the firmware to overwrite its own instructions.

The fix is:
1. keep the hardware contract unchanged,
2. move the tiled firmware text to a safe high address (`0x4000`),
3. keep the stack high (`0x7ff0`),
4. let the new tiled TBs boot from `0x4000`.

That is why the tiled flow has its own:
1. linker script,
2. firmware build directory,
3. dedicated testbenches.

## Live Real-Input Flow

Live real-valued square matrices are supported through:

1. `integration/pcpi_demo/tiled_matmul/tests/live_real_input.json`
2. `integration/pcpi_demo/tiled_matmul/tests/real_to_q5_10_tiled_case.py`
3. `integration/pcpi_demo/scripts/run_tiled_live_cycle_compare.ps1`

The flow is:

1. edit `live_real_input.json`,
2. provide `dim`,
3. provide either flat `a_real` / `b_real` arrays or nested `a_real_square` / `b_real_square`,
4. the converter rounds each real value using:
   - `q5_10 = round(real * 1024)`
5. the converter validates signed16 range,
6. it writes a generated case into `live_eval_cases.json`,
7. the live runner then runs:
   - accelerator tiled path,
   - software no-MUL path,
   - software MUL-enabled path.

Latest verified live run:

| Case | Dim | Accel Cycles | SW no-MUL Cycles | SW MUL Cycles | SW no-MUL / Accel | SW MUL / Accel |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `live_eval_tiled` | 8 | 22159 | 182478 | 56161 | 8.2349x | 2.5345x |

## Benchmark Table Flow

Benchmark tabulation is now handled by:

1. `integration/pcpi_demo/scripts/run_tiled_benchmark.ps1`

What it does:

1. iterates the tiled case manifest,
2. runs per-case compare if needed,
3. reuses existing per-case summaries when available,
4. writes:
   - `integration/pcpi_demo/results/tiled_matmul/tiled_benchmark_summary.md`
   - `integration/pcpi_demo/results/tiled_matmul/tiled_benchmark_summary.json`

This gives the same style of benchmark presentation as the earlier 4x4 flow, but now for tiled `NxN` workloads.

Latest verified benchmark rows:

| Case | Dim | Accel Cycles | SW no-MUL Cycles | SW MUL Cycles | SW no-MUL / Accel | SW MUL / Accel | SW no-MUL / SW MUL |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `square4_identity_seq` | 4 | 3161 | 22611 | 7463 | 7.1531x | 2.3610x | 3.0297x |
| `square8_pattern` | 8 | 22159 | 264606 | 56161 | 11.9412x | 2.5345x | 4.7116x |
| `square10_edge` | 10 | 95244 | 514271 | 108444 | 5.3995x | 1.1386x | 4.7423x |
| `square16_pattern` | 16 | 169453 | 2115566 | 437153 | 12.4847x | 2.5798x | 4.8394x |
| `square32_pattern` | 32 | 1311105 | 16822235 | 3451681 | 12.8306x | 2.6327x | 4.8736x |

## Why The Speedup Improved After The Timing Update

The first tiled measurements started too early:
1. they included the full-matrix input copy into firmware-visible memory
2. that setup cost is not the tiled compute kernel itself

The updated flow writes a start marker immediately before the actual tiled matmul call.
The testbench now measures:
1. start marker write
2. tiled compute
3. final sentinel write

So the updated numbers are still honest, but they are focused on the matmul region rather than unrelated precompute setup.

## File-By-File Guide

### `tiled_matmul/firmware/firmware_tiled_matmul.c`

Purpose:
1. entry firmware for the tiled flow.

What it does:
1. includes generated case data,
2. copies full `NxN` inputs into full matrix buffers,
3. selects either accelerator-tiled or software path based on compile-time macros,
4. writes the first output element to address `0x0` as the TB sentinel.

### `tiled_matmul/firmware/tiled_matmul_lib.h`

Purpose:
1. reusable tiled matmul library.

What it does:
1. defines full-matrix and staging-buffer base addresses,
2. provides tile load/store helpers,
3. provides fixed custom-op helper for the existing PCPI instruction,
4. implements:
   - `matmul_accel_tiled_q5_10_square(...)`
   - `matmul_sw_q5_10_square(...)`

### `tiled_matmul/firmware/Makefile`

Purpose:
1. dedicated firmware build flow for tiled firmware.

Why separate:
1. the tiled firmware needs its own link address and generated hex,
2. we do not want to disturb the original 4x4 firmware build flow.

### `tiled_matmul/firmware/sections.lds`

Purpose:
1. linker script for tiled firmware.

What it does:
1. places the tiled firmware text at `0x4000`.

### `tiled_matmul/tests/gen_tiled_cases.py`

Purpose:
1. generates the default square benchmark cases.

What it writes:
1. `cases_square.json`

### `tiled_matmul/tests/cases_square.json`

Purpose:
1. default tiled benchmark case manifest.

What it stores:
1. `name`
2. `dim`
3. `a_q5_10`
4. `b_q5_10`
5. optional `notes`

### `tiled_matmul/tests/gen_tiled_case_header.py`

Purpose:
1. converts one named tiled case into a C header.

What it writes:
1. `tiled_case_data.h`

### `tiled_matmul/tests/real_to_q5_10_tiled_case.py`

Purpose:
1. converts live real-valued square matrices to the tiled case schema.

What it supports:
1. flat or nested square real inputs,
2. `dim`-aware validation,
3. appending generated live cases,
4. clearing generated live cases.

### `tiled_matmul/tests/live_real_input.json`

Purpose:
1. editable template for live evaluator inputs.

### `tb/tb_tiled_matmul_common.v`

Purpose:
1. shared verification environment for tiled flows.

What it does:
1. uses large memory,
2. boots from `0x4000`,
3. loads the tiled firmware hex into the correct offset,
4. computes expected full `NxN` output in the TB,
5. checks the complete output matrix,
6. emits cycle markers.

### `tb/tb_picorv32_pcpi_tiled_matmul.v`

Purpose:
1. accelerator-backed tiled testbench.

### `tb/tb_picorv32_sw_tiled_matmul.v`

Purpose:
1. no-MUL software baseline tiled testbench.

### `tb/tb_picorv32_sw_tiled_matmul_mul.v`

Purpose:
1. MUL-enabled software baseline tiled testbench.

### `scripts/run_tiled_matmul_demo.ps1`

Purpose:
1. one-case tiled runner.

Typical use:
1. quick correctness check for a chosen case and mode.

### `scripts/run_tiled_cycle_compare.ps1`

Purpose:
1. one-case 3-way tiled compare runner.

What it writes:
1. per-case logs,
2. per-case markdown/json summary,
3. per-case output matrix JSON in Q5.10 and real form.

### `scripts/run_tiled_live_cycle_compare.ps1`

Purpose:
1. live evaluator runner for real-valued square matrices.

What it does:
1. converts the live real JSON,
2. creates a generated tiled case,
3. runs all three variants.

What it writes:
1. `integration/pcpi_demo/tiled_matmul/tests/live_eval_cases.json`
2. `integration/pcpi_demo/results/tiled_matmul/live_eval_tiled_cycle_compare_summary.md`
3. `integration/pcpi_demo/results/tiled_matmul/live_eval_tiled_cycle_compare_summary.json`
4. `integration/pcpi_demo/results/tiled_matmul/live_eval_tiled_outputs_real.json`

### `scripts/run_tiled_benchmark.ps1`

Purpose:
1. aggregate benchmark runner.

What it writes:
1. one benchmark table summarizing all tiled cases.
