# Midsem Simulation Results

## Accelerator Verification

| Test | Pass | Accelerator Cycles |
|---|---:|---:|
| `identity` | 1 | 10 |
| `ones` | 1 | 10 |

Overall pass rate: **2 / 2**

## Analytic Comparison (Cycle Model)

Assumptions: scalar software MM model uses 5 cycles/MAC plus loop overhead; accelerator setup overhead is modeled as 8 cycles.

| Metric | Value |
|---|---:|
| Matrix Size | 4x4 |
| Software Cycle Model | 352 |
| Accelerator Compute Cycles (simulated) | 10 |
| Accelerator End-to-End Cycles (modeled) | 18 |
| Speedup (compute-only) | 35.20x |
| Speedup (end-to-end) | 19.56x |

These speedups are pre-silicon estimates for presentation, not final board measurements.

## Next Step

Use this same test content after core integration, then replace analytic software cycles with measured `mcycle` or ARM `clock_gettime` data.
