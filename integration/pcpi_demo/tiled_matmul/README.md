# Tiled NxN Matmul Layer

This subtree adds a software tiling layer on top of the existing 4x4 accelerator.

What stays unchanged:
1. `accel_standalone/rtl/*`
2. `integration/pcpi_demo/rtl/pcpi_tinyml_accel.v`
3. Existing 4x4 smoke, regression, handoff, custom-case, and cycle-compare flows

What this subtree adds:
1. A bare-metal C tiling library for square `NxN` Q5.10 matrix multiply
2. Dedicated firmware entry for tiled accelerator-backed runs
3. Dedicated larger-matrix case schema and header generator
4. Dedicated larger-matrix runners and testbenches
5. Dedicated high-address firmware link/load path so staged `4x4` tile buffers do not overlap program text

Important behavior:
1. Hardware still computes only one `4x4 x 4x4 -> 4x4` tile per accelerator invocation.
2. Larger matrices are computed by packing logical `4x4` tiles into the existing accelerator staging buffers.
3. Partial sums across tile-`k` are accumulated in software.
4. Non-multiples of 4 are handled by zero-padding edge tiles in software.

Primary files:
1. `integration/pcpi_demo/tiled_matmul/firmware/firmware_tiled_matmul.c`
2. `integration/pcpi_demo/tiled_matmul/firmware/tiled_matmul_lib.h`
3. `integration/pcpi_demo/tiled_matmul/tests/cases_square.json`
4. `integration/pcpi_demo/tiled_matmul/tests/gen_tiled_case_header.py`
5. `integration/pcpi_demo/tiled_matmul/tests/live_real_input.json`
6. `integration/pcpi_demo/tiled_matmul/tests/real_to_q5_10_tiled_case.py`
7. `integration/pcpi_demo/scripts/run_tiled_matmul_demo.ps1`
8. `integration/pcpi_demo/scripts/run_tiled_cycle_compare.ps1`
9. `integration/pcpi_demo/scripts/run_tiled_live_cycle_compare.ps1`
10. `integration/pcpi_demo/scripts/run_tiled_benchmark.ps1`

Default case set:
1. `square4_identity_seq`
2. `square8_pattern`
3. `square10_edge`
4. `square16_pattern`
5. `square32_pattern`

Run one accelerator-backed tiled demo:

```powershell
.\integration\pcpi_demo\scripts\run_tiled_matmul_demo.ps1 -CaseName square8_pattern -Mode accel
```

Run one 3-way compare (accelerator tiled vs SW no-MUL vs SW MUL):

```powershell
.\integration\pcpi_demo\scripts\run_tiled_cycle_compare.ps1 -CaseName square16_pattern
```

Run live real-valued square input through all 3 variants:

```powershell
.\integration\pcpi_demo\scripts\run_tiled_live_cycle_compare.ps1
```

Run the aggregate tiled benchmark table:

```powershell
.\integration\pcpi_demo\scripts\run_tiled_benchmark.ps1
```

Outputs produced by the tiled flow:
1. per-case cycle summaries:
   - `integration/pcpi_demo/results/tiled_matmul/<case>_cycle_compare_summary.md`
   - `integration/pcpi_demo/results/tiled_matmul/<case>_cycle_compare_summary.json`
2. per-case matrix outputs in Q5.10 and real form:
   - `integration/pcpi_demo/results/tiled_matmul/<case>_outputs_real.json`
3. aggregate benchmark table:
   - `integration/pcpi_demo/results/tiled_matmul/tiled_benchmark_summary.md`
   - `integration/pcpi_demo/results/tiled_matmul/tiled_benchmark_summary.json`

Why the first tiled version did not look tabulated:
1. it only had the per-case compare runner
2. so each run produced one case summary, but there was no aggregate benchmark collector yet
3. `run_tiled_benchmark.ps1` is the additive piece that now writes the benchmark table in the same style as the earlier 4x4 flow

Latest verified live real-input run:

| Case | Dim | Accel Cycles | SW no-MUL Cycles | SW MUL Cycles | SW no-MUL / Accel | SW MUL / Accel |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `live_eval_tiled` | 8 | 22159 | 182478 | 56161 | 8.2349x | 2.5345x |

Latest verified tiled benchmark table:

| Case | Dim | Accel Cycles | SW no-MUL Cycles | SW MUL Cycles | SW no-MUL / Accel | SW MUL / Accel | SW no-MUL / SW MUL |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `square4_identity_seq` | 4 | 3161 | 22611 | 7463 | 7.1531x | 2.3610x | 3.0297x |
| `square8_pattern` | 8 | 22159 | 264606 | 56161 | 11.9412x | 2.5345x | 4.7116x |
| `square10_edge` | 10 | 95244 | 514271 | 108444 | 5.3995x | 1.1386x | 4.7423x |
| `square16_pattern` | 16 | 169453 | 2115566 | 437153 | 12.4847x | 2.5798x | 4.8394x |
| `square32_pattern` | 32 | 1311105 | 16822235 | 3451681 | 12.8306x | 2.6327x | 4.8736x |

Measurement note:
1. these cycle counts now start at an explicit firmware marker written immediately before the actual tiled matmul call
2. that removes input-buffer copy/setup time from the measurement window
3. this is a fairer comparison for tiled compute than timing from reset release

Latest verified on this feature branch:
1. `square4_identity_seq`: PASS through new tiled accelerator path
2. `square8_pattern`: PASS, 3-way compare
3. `square10_edge`: PASS, verifies non-multiple-of-4 zero padding
4. `square16_pattern`: PASS, 3-way compare
5. `square32_pattern`: PASS, 3-way compare
