# RV32 Pipeline + MATMUL Accelerator Integration Guide

Last updated: 2026-03-05  
Scope: `RISC-V/pipeline_top` + `midsem_sim` accelerator integration

## 1. Quick Summary

This project now has:

1. An assembled 5-stage RV32 pipeline top module.
2. A custom MATMUL instruction decode path.
3. A descriptor-driven matrix accelerator subsystem.
4. End-to-end simulation where:
   - CPU issues custom MATMUL instruction,
   - pipeline stalls during accelerator run,
   - accelerator writes matrix `C` to memory,
   - status is written back to destination register `rd`.
5. A high-verbosity testbench with mixed scalar instructions + MATMUL across 8 matrix scenarios.
6. A draw.io XML architecture diagram for fast visual onboarding.

---

## 2. Important Files

### Core / System RTL

- `RISC-V/pipeline_top/src/rv32_pipeline_top.v`
- `RISC-V/pipeline_top/src/rv32_pipeline_matmul_system.v`

### Testbenches

- `RISC-V/pipeline_top/tb/tb_rv32_pipeline_top_smoke.v`
- `RISC-V/pipeline_top/tb/tb_rv32_pipeline_matmul_system.v`

### Accelerator-side integration artifacts

- `midsem_sim/rtl/riscv_matmul_bridge.v`
- `midsem_sim/rtl/riscv_accel_integration_stub.v`
- `midsem_sim/tb/tb_riscv_accel_integration.v`

### Diagram

- `RISC-V/pipeline_top/diagrams/rv32_pipeline_matmul_architecture.drawio.xml`

### Notes/usage

- `RISC-V/pipeline_top/README.md`

---

## 3. Custom Instruction Definition

### MATMUL Encoding (R-type style)

- `opcode = 7'b0001011`
- `funct3 = 3'b000`
- `funct7 = 7'b0101010`

Field layout:

- `[31:25] funct7`
- `[24:20] rs2`
- `[19:15] rs1`
- `[14:12] funct3`
- `[11:7] rd`
- `[6:0] opcode`

### Semantics in current design

- `rs1`: descriptor base pointer (byte address)
- `rs2`: reserved, must be `x0` (0)
- `rd`: receives status code

Status written to `rd`:

- `0`: success
- `1`: bad dimensions (`M/N/K` not 4/4/4 in v1)
- `2`: bad alignment
- `3`: invalid reserved `rs2` usage

---

## 4. Descriptor Contract (v1)

At address in `rs1`:

1. `+0x00`: `A_base`
2. `+0x04`: `B_base`
3. `+0x08`: `C_base`
4. `+0x0C`: `{N[31:16], M[15:0]}`
5. `+0x10`: `{flags[31:16], K[15:0]}`
6. `+0x14`: `strideA` (bytes)
7. `+0x18`: `strideB` (bytes)
8. `+0x1C`: `strideC` (bytes)

Current fixed v1 constraints:

- `M = 4`, `N = 4`, `K = 4`
- Q5.10 element format (signed 16-bit)

---

## 5. Architecture and Working

## 5.1 Technical Flow (signal-level)

1. Instruction arrives in IF/ID.
2. `rv32_pipeline_top` checks raw instruction bits for MATMUL pattern.
3. On match:
   - `accel_start` pulse generated.
   - `accel_src0 <= rs1` (descriptor ptr), `accel_src1 <= rs2`.
   - custom-inflight/stall logic holds pipeline appropriately.
4. `rv32_pipeline_matmul_system` receives start and:
   - reads descriptor from its memory.
   - validates dims/alignment/rs2.
   - loads full A/B 4x4 into `a_flat_reg`/`b_flat_reg`.
   - starts `matrix_accel_4x4_q5_10`.
5. While accelerator runs:
   - `dbg_matmul_busy=1`.
   - core stall path asserted (`dbg_stall` observed in TB).
6. On accelerator `done`:
   - system writes full `c_flat` back to memory at `C_base + strideC`.
   - `accel_result` status prepared.
   - done/status handshake returns to core.
7. Core WB writes status to `rd`.
8. Scalar pipeline instructions proceed after stall release.

## 5.2 Layman Flow

1. CPU sees special MATMUL instruction.
2. CPU gives hardware a pointer to a “job sheet” (descriptor).
3. Hardware reads where A and B are in memory.
4. Hardware multiplies A×B.
5. Hardware stores C back to memory.
6. CPU gets success/error code in destination register.

---

## 6. Main Signals to Know

### Core custom interface

- `accel_start`
- `accel_busy`
- `accel_done`
- `accel_result`
- `accel_src0` (descriptor pointer from rs1)
- `accel_src1` (reserved field from rs2)

### Debug visibility

- `dbg_stall`
- `dbg_matmul_busy`
- `dbg_matmul_done`
- `dbg_wb_regwrite`
- `dbg_wb_rd`
- `dbg_wb_data`

### Matrix debug taps

- `dbg_a00..dbg_a03`
- `dbg_b00..dbg_b03`
- `dbg_c00..dbg_c03`

---

## 7. Testbench Coverage

Primary regression TB:

- `RISC-V/pipeline_top/tb/tb_rv32_pipeline_matmul_system.v`

What it verifies per case:

1. Scalar instruction before MATMUL commits.
2. MATMUL instruction triggers and stall is observed.
3. Scalar instruction issued during stall does not commit while stalled.
4. Status writeback to `x5` occurs with `0` (success).
5. Scalar instruction after MATMUL commits.
6. Matrix C in memory matches golden model.
7. Accelerator cycle count equals 10.

Matrix scenarios covered (8):

1. `identity`
2. `ones_x_ones`
3. `signed_mixed`
4. `zero_x_rand`
5. `rand_x_zero`
6. `diag_x_identity`
7. `upper_x_lower`
8. `checker_signed`

---

## 8. High-Readability Logs (Vivado Messages)

The TB emits verbose logs:

- `TB_DESC`: descriptor config summary
- `TB_TRACE`: per instruction issue (decoded fields)
- `TB_MATRIX` / `TB_MATRIX_ROW`: matrix values for A/B/expected C
- `TB_EVENT`: signal edges and key state events
- `TB_CHECK_PASS` / `TB_CHECK_FAIL`: verification checkpoints
- `TB_PASS test=...` and final `SUMMARY`

This is intentionally designed so another bot/engineer can reason from logs without opening all RTL.

---

## 9. Diagram Explanation (Block-by-Block)

Diagram file:

- `RISC-V/pipeline_top/diagrams/rv32_pipeline_matmul_architecture.drawio.xml`

How to read it:

1. Left-to-right main path: IF -> ID -> EX -> MEM -> WB.
2. Vertical bars are pipeline registers:
   - IF/ID, ID/EX, EX/MEM, MEM/WB.
3. Black edges are datapath buses.
4. Blue edges are control/handshake lines.
5. ID stage includes custom comparator for MATMUL bitfields.
6. MEM side includes descriptor controller + pack/unpack logic.
7. Accelerator block runs in parallel subsystem with `start/busy/done`.
8. C writeback path stores `c_flat` to memory.
9. WB result mux includes `accel_result` path.
10. Debug block shows `dbg_stall`, `dbg_matmul_*`, and WB debug taps.

---

## 10. Run Commands

From repo root:

```powershell
iverilog -g2012 -o .\RISC-V\pipeline_top\matmul_system_tb.vvp `
  .\RISC-V\pipeline_top\src\rv32_pipeline_top.v `
  .\RISC-V\pipeline_top\src\rv32_pipeline_matmul_system.v `
  .\RISC-V\pipeline_top\tb\tb_rv32_pipeline_matmul_system.v `
  .\RISC-V\instruction_decoder\src\instruction_decoder.v `
  .\RISC-V\Control_Unit\src\Control_Unit.v `
  .\RISC-V\alu_control\src\alu_control.v `
  .\RISC-V\alu\src\alu.v `
  .\RISC-V\register_bank\src\register_bank.v `
  .\RISC-V\data_memory\src\data_memory.v `
  .\RISC-V\hazard_detection_unit\src\hazard_detection_unit.v `
  .\RISC-V\forwarding_unit\src\forwarding_unit.v `
  .\midsem_sim\rtl\pe_cell_q5_10.v `
  .\midsem_sim\rtl\issue_logic_4x4_q5_10.v `
  .\midsem_sim\rtl\systolic_array_4x4_q5_10.v `
  .\midsem_sim\rtl\matrix_accel_4x4_q5_10.v

vvp .\RISC-V\pipeline_top\matmul_system_tb.vvp
```

Expected final line:

- `TB_PASS summary pass=8 total=8`

---

## 11. Current Limitations

1. Descriptor v1 is fixed to 4x4x4 only.
2. `rs2` currently reserved and must be zero.
3. Existing upstream `alu_control.v` prints non-blocking hex-width warnings.
4. This is simulation-validated integration; board-level performance measurement is a later step.

---

## 12. Suggested Next Engineering Steps

1. Add negative tests for status codes 1/2/3 in dedicated TB sections.
2. Expand descriptor to variable `M/N/K`.
3. Introduce memory latency/handshake realism if targeting synthesis-quality subsystem behavior.
4. Add software-side `.insn` examples for assembler-driven MATMUL invocation.

