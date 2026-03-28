`timescale 1ns/1ps

`ifndef TB_MODULE_NAME
`define TB_MODULE_NAME tb_tiled_matmul_common
`endif

`ifndef TB_ENABLE_MUL
`define TB_ENABLE_MUL 0
`endif

`ifndef TB_STACKADDR
`define TB_STACKADDR 32'h0000_7ff0
`endif

`ifndef TB_MEM_WORDS
`define TB_MEM_WORDS 8192
`endif

`ifndef TB_MEM_ADDR_MSB
`define TB_MEM_ADDR_MSB 14
`endif

`ifndef TB_MAX_DIM
`define TB_MAX_DIM 32
`endif

`ifndef TB_TIMEOUT_CYCLES
`define TB_TIMEOUT_CYCLES 50000000
`endif

`ifndef TB_PROGADDR_RESET
`define TB_PROGADDR_RESET 32'h0000_4000
`endif

`ifndef TB_DUMPFILE
`define TB_DUMPFILE "integration/pcpi_demo/results/tiled_matmul/tiled_matmul_wave.vcd"
`endif

`ifndef TB_FIRMWARE_HEX
`define TB_FIRMWARE_HEX "integration/pcpi_demo/tiled_matmul/firmware/firmware.hex"
`endif

`ifndef TB_LABEL
`define TB_LABEL "tiled_matmul"
`endif

module `TB_MODULE_NAME;

    localparam [31:0] TILE_A_BASE = 32'h0000_0100;
    localparam [31:0] TILE_B_BASE = 32'h0000_0140;
    localparam [31:0] TILE_C_BASE = 32'h0000_0200;
    localparam [31:0] FULL_A_BASE = 32'h0000_1000;
    localparam [31:0] FULL_B_BASE = 32'h0000_2000;
    localparam [31:0] FULL_C_BASE = 32'h0000_3000;
    localparam integer MAX_MAT_ELEMS = (`TB_MAX_DIM * `TB_MAX_DIM);
`ifdef TB_ENABLE_PCPI
    localparam integer CPU_ENABLE_PCPI = 1;
`else
    localparam integer CPU_ENABLE_PCPI = 0;
`endif

    reg clk;
    reg resetn;

    wire trap;

    wire mem_valid;
    wire mem_instr;
    wire mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_rdata;

`ifdef TB_ENABLE_PCPI
    wire pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire pcpi_wr;
    wire [31:0] pcpi_rd;
    wire pcpi_wait;
    wire pcpi_ready;

    wire        accel_mem_valid;
    wire        accel_mem_we;
    wire [31:0] accel_mem_addr;
    wire [31:0] accel_mem_wdata;
    wire [31:0] accel_mem_rdata;
    wire        accel_mem_ready;
`endif

    reg [31:0] memory [0:`TB_MEM_WORDS-1];
    reg [31:0] expected_c [0:MAX_MAT_ELEMS-1];
    reg test_passed;
    reg matmul_started;
    reg [8*64-1:0] case_name;
    integer i;
    integer timeout_cycles;
    integer matmul_start_cycle;
    integer mat_dim;
    integer mat_elems;

    assign mem_ready = 1'b1;
    assign mem_rdata = memory[mem_addr[`TB_MEM_ADDR_MSB:2]];

`ifdef TB_ENABLE_PCPI
    assign accel_mem_ready = 1'b1;
    assign accel_mem_rdata = memory[accel_mem_addr[`TB_MEM_ADDR_MSB:2]];
`endif

    picorv32 #(
        .ENABLE_PCPI(CPU_ENABLE_PCPI),
        .ENABLE_MUL(`TB_ENABLE_MUL),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .COMPRESSED_ISA(0),
        .PROGADDR_RESET(`TB_PROGADDR_RESET),
        .STACKADDR(`TB_STACKADDR)
    ) cpu (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(),
        .mem_la_write(),
        .mem_la_addr(),
        .mem_la_wdata(),
        .mem_la_wstrb(),
`ifdef TB_ENABLE_PCPI
        .pcpi_valid(pcpi_valid),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1),
        .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr),
        .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait),
        .pcpi_ready(pcpi_ready),
`else
        .pcpi_valid(),
        .pcpi_insn(),
        .pcpi_rs1(),
        .pcpi_rs2(),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'd0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
`endif
        .irq(32'd0),
        .eoi()
    );

`ifdef TB_ENABLE_PCPI
    pcpi_tinyml_accel pcpi_accel (
        .clk(clk),
        .resetn(resetn),
        .pcpi_valid(pcpi_valid),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1),
        .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr),
        .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait),
        .pcpi_ready(pcpi_ready),
        .accel_mem_valid(accel_mem_valid),
        .accel_mem_we(accel_mem_we),
        .accel_mem_addr(accel_mem_addr),
        .accel_mem_wdata(accel_mem_wdata),
        .accel_mem_rdata(accel_mem_rdata),
        .accel_mem_ready(accel_mem_ready)
    );
`endif

    always #5 clk = ~clk;

    task automatic verify_full_c_matrix_buffer;
        integer idx;
        integer c_word_index;
        begin
            for (idx = 0; idx < mat_elems; idx = idx + 1) begin
                c_word_index = (FULL_C_BASE >> 2) + idx;
                if (memory[c_word_index] !== expected_c[idx]) begin
                    $display("TB_FAIL %s full-C mismatch idx=%0d got=0x%08h expected=0x%08h",
                             `TB_LABEL, idx, memory[c_word_index], expected_c[idx]);
                    $fatal(1, "Tiled full C matrix mismatch.");
                end
            end
            $display("TB_PASS %s full-C verification for %0d elements.", `TB_LABEL, mat_elems);
        end
    endtask

    task automatic build_expected_from_full_buffers;
        integer row_idx;
        integer col_idx;
        integer dot_idx;
        integer dst_idx;
        reg signed [15:0] a_elem;
        reg signed [15:0] b_elem;
        reg signed [31:0] acc;
        begin
            for (dst_idx = 0; dst_idx < MAX_MAT_ELEMS; dst_idx = dst_idx + 1) begin
                expected_c[dst_idx] = 32'd0;
            end

            for (row_idx = 0; row_idx < mat_dim; row_idx = row_idx + 1) begin
                for (col_idx = 0; col_idx < mat_dim; col_idx = col_idx + 1) begin
                    acc = 32'sd0;
                    for (dot_idx = 0; dot_idx < mat_dim; dot_idx = dot_idx + 1) begin
                        a_elem = memory[(FULL_A_BASE >> 2) + (row_idx * mat_dim) + dot_idx][15:0];
                        b_elem = memory[(FULL_B_BASE >> 2) + (dot_idx * mat_dim) + col_idx][15:0];
                        acc = acc + (($signed(a_elem) * $signed(b_elem)) >>> 10);
                    end
                    expected_c[(row_idx * mat_dim) + col_idx] = {{16{acc[15]}}, acc[15:0]};
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if (mem_valid && (|mem_wstrb)) begin
            if (mem_wstrb[0]) memory[mem_addr[`TB_MEM_ADDR_MSB:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) memory[mem_addr[`TB_MEM_ADDR_MSB:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) memory[mem_addr[`TB_MEM_ADDR_MSB:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) memory[mem_addr[`TB_MEM_ADDR_MSB:2]][31:24] <= mem_wdata[31:24];

            if (mem_addr == 32'h0000_0000) begin
                build_expected_from_full_buffers();
                if (mem_wdata == expected_c[0]) begin
                    $display("TB_PASS %s sentinel write matches expected c00: 0x%08h", `TB_LABEL, mem_wdata);
                    verify_full_c_matrix_buffer();
                    test_passed <= 1'b1;
                end else begin
                    $display("TB_FAIL %s wrong sentinel write: got=0x%08h expected=0x%08h",
                             `TB_LABEL, mem_wdata, expected_c[0]);
                    $fatal(1, "Incorrect tiled matmul sentinel result.");
                end
            end else if (mem_addr == 32'h0000_0008) begin
                matmul_started <= 1'b1;
                matmul_start_cycle <= timeout_cycles;
                $display("TB_INFO %s matmul start marker observed at cycle=%0d", `TB_LABEL, timeout_cycles);
            end
        end
`ifdef TB_ENABLE_PCPI
        else if (accel_mem_valid && accel_mem_we) begin
            memory[accel_mem_addr[`TB_MEM_ADDR_MSB:2]] <= accel_mem_wdata;
        end
`endif
    end

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        test_passed = 1'b0;
        matmul_started = 1'b0;
        timeout_cycles = 0;
        matmul_start_cycle = 0;
        case_name = "square8_pattern";
        mat_dim = 8;
        mat_elems = 64;

        if ($value$plusargs("CASE_NAME=%s", case_name)) begin
            $display("TB_INFO case=%0s", case_name);
        end else begin
            $display("TB_INFO case=square8_pattern");
        end

        if ($value$plusargs("MAT_DIM=%d", mat_dim)) begin
            $display("TB_INFO dim=%0d", mat_dim);
        end else begin
            $display("TB_INFO dim(default)=%0d", mat_dim);
        end

        mat_elems = mat_dim * mat_dim;
        if (mat_dim <= 0) begin
            $fatal(1, "MAT_DIM must be positive.");
        end
        if (mat_elems > MAX_MAT_ELEMS) begin
            $fatal(1, "MAT_DIM=%0d exceeds TB_MAX_DIM=%0d.", mat_dim, `TB_MAX_DIM);
        end

        $dumpfile(`TB_DUMPFILE);
        $dumpvars(0, `TB_MODULE_NAME);

        for (i = 0; i < `TB_MEM_WORDS; i = i + 1) begin
            memory[i] = 32'h0000_0013;
        end

        $readmemh(`TB_FIRMWARE_HEX, memory, (`TB_PROGADDR_RESET >> 2));

        for (i = 0; i < mat_elems; i = i + 1) begin
            memory[(FULL_A_BASE >> 2) + i] = 32'd0;
            memory[(FULL_B_BASE >> 2) + i] = 32'd0;
            memory[(FULL_C_BASE >> 2) + i] = 32'd0;
            expected_c[i] = 32'd0;
        end

        for (i = 0; i < 16; i = i + 1) begin
            memory[(TILE_A_BASE >> 2) + i] = 32'd0;
            memory[(TILE_B_BASE >> 2) + i] = 32'd0;
            memory[(TILE_C_BASE >> 2) + i] = 32'd0;
        end

        repeat (8) @(posedge clk);
        resetn = 1'b1;

        while (!test_passed) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
            if (trap) begin
                $display("TB_FAIL %s trap asserted before pass. pc=0x%08h state=%0s mem_valid=%0d mem_addr=0x%08h",
                         `TB_LABEL, cpu.reg_pc, cpu.dbg_ascii_state, mem_valid, mem_addr);
`ifdef TB_ENABLE_PCPI
                $display("TB_FAIL %s pcpi_valid=%0d pcpi_wait=%0d pcpi_ready=%0d pcpi_insn=0x%08h pcpi_timeout=%0d",
                         `TB_LABEL, pcpi_valid, pcpi_wait, pcpi_ready, pcpi_insn, cpu.pcpi_timeout);
`endif
                $fatal(1, "CPU trap.");
            end
            if (timeout_cycles > `TB_TIMEOUT_CYCLES) begin
                $display("TB_FAIL %s timeout waiting for sentinel write.", `TB_LABEL);
                $fatal(1, "Timeout.");
            end
        end

        if (!matmul_started) begin
            $fatal(1, "Tiled matmul start marker was never observed.");
        end

        $display("TB_CYCLES matmul_to_sentinel_cycles=%0d", timeout_cycles - matmul_start_cycle);
        $display("TB_PASS %s complete.", `TB_LABEL);
        $finish;
    end

endmodule
