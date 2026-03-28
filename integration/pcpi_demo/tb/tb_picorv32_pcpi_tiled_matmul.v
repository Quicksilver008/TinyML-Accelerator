`define TB_MODULE_NAME tb_picorv32_pcpi_tiled_matmul
`define TB_ENABLE_PCPI
`define TB_ENABLE_MUL 0
`define TB_DUMPFILE "integration/pcpi_demo/results/tiled_matmul/tiled_matmul_accel_wave.vcd"
`define TB_LABEL "tiled_accel"
`include "tb_tiled_matmul_common.v"
