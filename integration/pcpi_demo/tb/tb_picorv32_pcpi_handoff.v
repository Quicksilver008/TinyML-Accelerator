`timescale 1ns/1ps

module tb_picorv32_pcpi_handoff;

    localparam [31:0] A_BASE = 32'h0000_0240;
    localparam [31:0] B_BASE = 32'h0000_0280;
    localparam [31:0] C_BASE = 32'h0000_0200;
    localparam [31:0] C_END  = 32'h0000_023c;

    localparam [31:0] EXP_FIRST_C00  = 32'h0000_0400;
    localparam [31:0] EXP_SECOND_C00 = 32'hffff_fc00;
    localparam [31:0] EXP_MARKER     = 32'h0000_047b; // first c00 + 123

    localparam [6:0] OPCODE_CUSTOM0 = 7'b0001011;
    localparam [2:0] FUNCT3_MATMUL  = 3'b000;
    localparam [6:0] FUNCT7_MATMUL  = 7'b0101010;

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

    integer i;
    integer timeout_cycles;

    integer custom_issue_count;
    integer ready_count;
    integer wr_count;
    integer handshake_ok_count;
    integer c_store_count;

    reg prev_custom_match;
    reg in_custom;
    reg saw_wait;

    reg first_store_ok;
    reg second_store_ok;
    reg marker_store_ok;
    reg test_passed;

    wire custom_match;
    assign custom_match = pcpi_valid &&
                          (pcpi_insn[6:0]   == OPCODE_CUSTOM0) &&
                          (pcpi_insn[14:12] == FUNCT3_MATMUL) &&
                          (pcpi_insn[31:25] == FUNCT7_MATMUL);

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

    always @(posedge clk) begin
        if (mem_valid && (|mem_wstrb)) begin
            if (mem_wstrb[0]) memory[mem_addr[9:2]][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) memory[mem_addr[9:2]][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) memory[mem_addr[9:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) memory[mem_addr[9:2]][31:24] <= mem_wdata[31:24];

            if (mem_addr == 32'h0000_0000) begin
                if (mem_wdata !== EXP_FIRST_C00) begin
                    $display("TB_FAIL first sentinel mismatch got=0x%08h expected=0x%08h", mem_wdata, EXP_FIRST_C00);
                    $fatal(1, "First sentinel mismatch.");
                end
                first_store_ok <= 1'b1;
                $display("TB_INFO first custom result observed: 0x%08h", mem_wdata);
            end

            if (mem_addr == 32'h0000_0004) begin
                if (mem_wdata !== EXP_SECOND_C00) begin
                    $display("TB_FAIL second sentinel mismatch got=0x%08h expected=0x%08h", mem_wdata, EXP_SECOND_C00);
                    $fatal(1, "Second sentinel mismatch.");
                end
                second_store_ok <= 1'b1;
                $display("TB_INFO second custom result observed: 0x%08h", mem_wdata);
            end

            if (mem_addr == 32'h0000_0008) begin
                if (mem_wdata !== EXP_MARKER) begin
                    $display("TB_FAIL regular-marker mismatch got=0x%08h expected=0x%08h", mem_wdata, EXP_MARKER);
                    $fatal(1, "Regular marker mismatch.");
                end
                marker_store_ok <= 1'b1;
                $display("TB_INFO regular instruction marker observed: 0x%08h", mem_wdata);
            end
        end else if (accel_mem_valid && accel_mem_we) begin
            memory[accel_mem_addr[9:2]] <= accel_mem_wdata;

            if (accel_mem_addr >= C_BASE && accel_mem_addr <= C_END) begin
                c_store_count <= c_store_count + 1;
            end
        end
    end

    always @(posedge clk) begin
        // Count unique custom-instruction issue events.
        if (custom_match && !prev_custom_match) begin
            custom_issue_count <= custom_issue_count + 1;
            in_custom <= 1'b1;
            saw_wait <= 1'b0;
        end
        prev_custom_match <= custom_match;

        if (in_custom && pcpi_wait)
            saw_wait <= 1'b1;

        if (pcpi_ready) begin
            ready_count <= ready_count + 1;
            if (in_custom && saw_wait)
                handshake_ok_count <= handshake_ok_count + 1;
            else begin
                $display("TB_FAIL pcpi_ready without prior wait phase.");
                $fatal(1, "Handshake sequencing error.");
            end
            in_custom <= 1'b0;
            saw_wait <= 1'b0;
        end

        if (pcpi_wr)
            wr_count <= wr_count + 1;
    end

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        timeout_cycles = 0;

        custom_issue_count = 0;
        ready_count = 0;
        wr_count = 0;
        handshake_ok_count = 0;
        c_store_count = 0;

        prev_custom_match = 1'b0;
        in_custom = 1'b0;
        saw_wait = 1'b0;

        first_store_ok = 1'b0;
        second_store_ok = 1'b0;
        marker_store_ok = 1'b0;
        test_passed = 1'b0;

        $dumpfile("integration/pcpi_demo/results/pcpi_handoff_wave.vcd");
        $dumpvars(0, tb_picorv32_pcpi_handoff);

        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'h0000_0013; // NOP

        $readmemh("integration/pcpi_demo/firmware/firmware_handoff.hex", memory);

        // Clear RAM windows used by firmware and accelerator.
        for (i = 0; i < 16; i = i + 1) begin
            memory[(A_BASE >> 2) + i] = 32'd0;
            memory[(B_BASE >> 2) + i] = 32'd0;
            memory[(C_BASE >> 2) + i] = 32'd0;
        end

        repeat (8) @(posedge clk);
        resetn = 1'b1;

        while (!test_passed) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;

            if (trap) begin
                $display("TB_FAIL trap asserted.");
                $fatal(1, "CPU trap.");
            end

            if (timeout_cycles > 15000) begin
                $display("TB_FAIL timeout.");
                $fatal(1, "Timeout.");
            end

            if (first_store_ok && marker_store_ok && second_store_ok) begin
                if (custom_issue_count != 2) begin
                    $display("TB_FAIL custom issue count mismatch got=%0d expected=2", custom_issue_count);
                    $fatal(1, "Custom issue count mismatch.");
                end
                if (ready_count != 2 || wr_count != 2) begin
                    $display("TB_FAIL ready/wr count mismatch ready=%0d wr=%0d", ready_count, wr_count);
                    $fatal(1, "ready/wr count mismatch.");
                end
                if (handshake_ok_count != 2) begin
                    $display("TB_FAIL handshake sequencing count mismatch got=%0d expected=2", handshake_ok_count);
                    $fatal(1, "Handshake sequencing mismatch.");
                end
                if (c_store_count != 32) begin
                    $display("TB_FAIL C-store count mismatch got=%0d expected=32", c_store_count);
                    $fatal(1, "C-store count mismatch.");
                end

                test_passed = 1'b1;
            end
        end

        $display("TB_PASS handoff test complete.");
        $display("TB_PASS custom_issue_count=%0d ready_count=%0d wr_count=%0d handshake_ok_count=%0d c_store_count=%0d",
                 custom_issue_count, ready_count, wr_count, handshake_ok_count, c_store_count);
        $finish;
    end

endmodule
