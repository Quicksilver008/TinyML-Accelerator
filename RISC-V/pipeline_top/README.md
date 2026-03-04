# RV32 Pipeline Top (Assembled)

This folder provides an assembled CPU top module that wires existing repository blocks into a 5-stage style pipeline skeleton:

- IF: internal PC + instruction fetch
- ID: instruction decode + control + register read
- EX: ALU control + forwarding + ALU
- MEM: data memory access
- WB: register write-back

File:

- `src/rv32_pipeline_top.v`

## Included Integration Hooks

The top includes custom-instruction hook ports intended for accelerator integration:

- `accel_start`, `accel_src0`, `accel_src1`, `accel_rd`
- `accel_busy`, `accel_done`, `accel_result`

Current custom decode pattern is:

- `opcode=0001011`
- `funct3=000`
- `funct7=0101010`

## Smoke Testbench

Testbench:

- `tb/tb_rv32_pipeline_top_smoke.v`

Icarus compile/run:

```powershell
iverilog -g2012 -o .\RISC-V\pipeline_top\smoke.vvp `
  .\RISC-V\pipeline_top\src\rv32_pipeline_top.v `
  .\RISC-V\pipeline_top\tb\tb_rv32_pipeline_top_smoke.v `
  .\RISC-V\instruction_decoder\src\instruction_decoder.v `
  .\RISC-V\Control_Unit\src\Control_Unit.v `
  .\RISC-V\alu_control\src\alu_control.v `
  .\RISC-V\alu\src\alu.v `
  .\RISC-V\register_bank\src\register_bank.v `
  .\RISC-V\data_memory\src\data_memory.v `
  .\RISC-V\hazard_detection_unit\src\hazard_detection_unit.v `
  .\RISC-V\forwarding_unit\src\forwarding_unit.v

vvp .\RISC-V\pipeline_top\smoke.vvp
```

Expected terminal line:

- `TB_PASS smoke test completed.`

## Note

This is an assembled, integration-ready top for iterative development, not yet a fully verified production core. It is intended to make end-to-end edits and accelerator hookup practical.

## Pipeline + Matrix Accelerator System Test (Descriptor Contract v1)

System wrapper:

- `src/rv32_pipeline_matmul_system.v`

Testbench:

- `tb/tb_rv32_pipeline_matmul_system.v`

Contract used by custom instruction:

- `rs1` = descriptor base pointer (byte address)
- `rs2` = reserved (must be zero in v1)
- `rd` = status code written on completion

Descriptor layout at `rs1`:

- `+0x00`: `A_base`
- `+0x04`: `B_base`
- `+0x08`: `C_base`
- `+0x0C`: `{N[31:16], M[15:0]}` (must be 4,4 in v1)
- `+0x10`: `{flags[31:16], K[15:0]}` (K must be 4 in v1)
- `+0x14`: `strideA` (bytes)
- `+0x18`: `strideB` (bytes)
- `+0x1C`: `strideC` (bytes)

Status values returned in `rd`:

- `0`: success
- `1`: bad dimensions
- `2`: bad alignment
- `3`: invalid reserved `rs2` usage

Compile/run:

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

Expected key lines:

- For each case: pass checks for `wb_pre`, `dbg_stall`, `wb_during`, `wb_status`, `wb_post`, `C_mem`, `matmul_cycle_count`
- Final summary: `TB_PASS summary pass=8 total=8`

Current regression covers 8 matrix combinations:

- `identity`
- `ones_x_ones`
- `signed_mixed`
- `zero_x_rand`
- `rand_x_zero`
- `diag_x_identity`
- `upper_x_lower`
- `checker_signed`
