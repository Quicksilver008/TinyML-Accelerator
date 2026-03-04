`timescale 1ns/1ps

module tb_picorv32_pcpi_tinyml;

    localparam [31:0] A_BASE = 32'h0000_0100;
    localparam [31:0] B_BASE = 32'h0000_0140;
    localparam [31:0] C_BASE = 32'h0000_0200;

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

    reg [31:0] memory [0:255];
    reg [31:0] expected_c [0:15];
    reg test_passed;
    reg [8*64-1:0] case_name;
    integer i;
    integer k;
    integer timeout_cycles;

    // Native memory and accelerator sideband memory are always ready in this simple demo.
    assign mem_ready = 1'b1;
    assign mem_rdata = memory[mem_addr[9:2]];
    assign accel_mem_ready = 1'b1;
    assign accel_mem_rdata = memory[accel_mem_addr[9:2]];

    picorv32 #(
        .ENABLE_PCPI(1),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .COMPRESSED_ISA(0),
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_0800)
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
        .pcpi_valid(pcpi_valid),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1),
        .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr),
        .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait),
        .pcpi_ready(pcpi_ready),
        .irq(32'd0),
        .eoi()
    );

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

    always #5 clk = ~clk;

    task automatic verify_c_matrix_buffer;
        integer idx;
        begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                if (memory[(C_BASE >> 2) + idx] !== expected_c[idx]) begin
                    $display("TB_FAIL C-buffer mismatch idx=%0d got=0x%08h expected=0x%08h",
                             idx, memory[(C_BASE >> 2) + idx], expected_c[idx]);
                    $fatal(1, "Matrix C buffer mismatch.");
                end
            end
            $display("TB_PASS C-buffer verification for all 16 elements.");
        end
    endtask

    task automatic build_expected_from_memory;
        integer row_idx;
        integer col_idx;
        integer dot_idx;
        reg signed [15:0] a_elem;
        reg signed [15:0] b_elem;
        reg signed [31:0] acc;
        begin
            for (row_idx = 0; row_idx < 4; row_idx = row_idx + 1) begin
                for (col_idx = 0; col_idx < 4; col_idx = col_idx + 1) begin
                    acc = 32'sd0;
                    for (dot_idx = 0; dot_idx < 4; dot_idx = dot_idx + 1) begin
                        a_elem = memory[(A_BASE >> 2) + (row_idx * 4) + dot_idx][15:0];
                        b_elem = memory[(B_BASE >> 2) + (dot_idx * 4) + col_idx][15:0];
                        acc = acc + (($signed(a_elem) * $signed(b_elem)) >>> 10);
                    end
                    expected_c[(row_idx * 4) + col_idx] = {{16{acc[15]}}, acc[15:0]};
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if (mem_valid && (|mem_wstrb)) begin
            if (mem_wstrb[0]) memory[mem_addr[9:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) memory[mem_addr[9:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) memory[mem_addr[9:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) memory[mem_addr[9:2]][31:24] <= mem_wdata[31:24];

            // Program stores x4 to address 0 after loading first C element.
            if (mem_addr == 32'h0000_0000) begin
                build_expected_from_memory();
                if (mem_wdata == expected_c[0]) begin
                    $display("TB_PASS custom instruction result write: 0x%08h", mem_wdata);
                    verify_c_matrix_buffer();
                    test_passed <= 1'b1;
                end else begin
                    $display("TB_FAIL wrong result write: got=0x%08h expected=0x%08h", mem_wdata, expected_c[0]);
                    $fatal(1, "Incorrect custom instruction result.");
                end
            end
        end else if (accel_mem_valid && accel_mem_we) begin
            memory[accel_mem_addr[9:2]] <= accel_mem_wdata;
        end
    end

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        test_passed = 1'b0;
        timeout_cycles = 0;
        case_name = "default";
        if ($value$plusargs("CASE_NAME=%s", case_name)) begin
            $display("TB_INFO case=%0s", case_name);
        end else begin
            $display("TB_INFO case=default");
        end

        $dumpfile("integration/pcpi_demo/results/pcpi_demo_wave.vcd");
        $dumpvars(0, tb_picorv32_pcpi_tinyml);

        for (i = 0; i < 256; i = i + 1) begin
            memory[i] = 32'h0000_0013; // NOP: addi x0, x0, 0
        end

        // Load firmware program into memory (addresses starting from 0x0).
        $readmemh("integration/pcpi_demo/firmware/firmware.hex", memory);

        // A and B are provided by firmware.
        for (i = 0; i < 16; i = i + 1) begin
            memory[(A_BASE >> 2) + i] = 32'h0000_0000;
            memory[(B_BASE >> 2) + i] = 32'h0000_0000;
            expected_c[i] = 32'h0000_0000;
        end

        // Clear C buffer space.
        for (i = 0; i < 16; i = i + 1) begin
            memory[(C_BASE >> 2) + i] = 32'h0000_0000;
        end

        repeat (8) @(posedge clk);
        resetn = 1'b1;

        while (!test_passed) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
            if (trap) begin
                $display("TB_FAIL trap asserted before pass.");
                $fatal(1, "CPU trap.");
            end
            if (timeout_cycles > 5000) begin
                $display("TB_FAIL timeout waiting for store result.");
                $fatal(1, "Timeout.");
            end
        end

        $display("TB_PASS integration pcpi demo complete.");
        $finish;
    end

endmodule
