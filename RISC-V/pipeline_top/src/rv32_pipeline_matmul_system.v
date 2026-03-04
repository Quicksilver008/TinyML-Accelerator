`timescale 1ns/1ps

module rv32_pipeline_matmul_system #(
    parameter MEM_WORDS = 1024
) (
    input wire clk,
    input wire rst,
    input wire [31:0] ext_instr_word,
    input wire ext_instr_valid,
    input wire use_ext_instr,

    // Host memory preload/readback interface for simulation
    input wire host_mem_we,
    input wire [31:0] host_mem_addr,
    input wire [31:0] host_mem_wdata,
    output wire [31:0] host_mem_rdata,

    output wire [255:0] mat_c_flat,
    output wire [7:0] matmul_cycle_count,
    output wire dbg_matmul_busy,
    output wire dbg_matmul_done,
    output wire [31:0] dbg_pc_if,
    output wire [31:0] dbg_instr_if,
    output wire [31:0] dbg_instr_id,
    output wire dbg_stall,
    output wire dbg_custom_inflight,
    output wire dbg_wb_regwrite,
    output wire [4:0] dbg_wb_rd,
    output wire [31:0] dbg_wb_data,
    output wire signed [15:0] dbg_a00,
    output wire signed [15:0] dbg_a01,
    output wire signed [15:0] dbg_a02,
    output wire signed [15:0] dbg_a03,
    output wire signed [15:0] dbg_b00,
    output wire signed [15:0] dbg_b01,
    output wire signed [15:0] dbg_b02,
    output wire signed [15:0] dbg_b03,
    output wire signed [15:0] dbg_c00,
    output wire signed [15:0] dbg_c01,
    output wire signed [15:0] dbg_c02,
    output wire signed [15:0] dbg_c03
);

    localparam integer N = 4;
    localparam [31:0] STATUS_OK = 32'd0;
    localparam [31:0] STATUS_BAD_DIMS = 32'd1;
    localparam [31:0] STATUS_BAD_ALIGN = 32'd2;
    localparam [31:0] STATUS_BAD_RS2 = 32'd3;

    reg [31:0] mem [0:MEM_WORDS-1];

    // Descriptor fields
    reg [31:0] desc_ptr;
    reg [31:0] a_base;
    reg [31:0] b_base;
    reg [31:0] c_base;
    reg [15:0] dim_m;
    reg [15:0] dim_n;
    reg [15:0] dim_k;
    reg [15:0] desc_flags;
    reg [31:0] stride_a;
    reg [31:0] stride_b;
    reg [31:0] stride_c;

    reg [255:0] a_flat_reg;
    reg [255:0] b_flat_reg;

    wire core_accel_start;
    wire [31:0] core_accel_src0;
    wire [31:0] core_accel_src1;
    wire [4:0] core_accel_rd_unused;

    reg ctrl_busy;
    reg accel_done_pulse;
    reg [31:0] accel_result_reg;
    reg waiting_array_done;
    reg array_start;

    wire array_busy;
    wire array_done;
    wire [255:0] c_flat_wire;
    wire [7:0] cycle_count_wire;

    integer rr;
    integer cc;
    integer base;
    reg [31:0] elem_addr;
    reg [15:0] elem_val;
    reg [31:0] status_code;

    function automatic [15:0] mem_read_half;
        input [31:0] byte_addr;
        integer idx;
        begin
            idx = byte_addr[31:2];
            if (byte_addr[1]) begin
                mem_read_half = mem[idx][31:16];
            end else begin
                mem_read_half = mem[idx][15:0];
            end
        end
    endfunction

    task automatic mem_write_half;
        input [31:0] byte_addr;
        input [15:0] value;
        integer idx;
        begin
            idx = byte_addr[31:2];
            if (byte_addr[1]) begin
                mem[idx][31:16] = value;
            end else begin
                mem[idx][15:0] = value;
            end
        end
    endtask

    assign host_mem_rdata = mem[host_mem_addr[31:2]];

    rv32_pipeline_top core (
        .clk(clk),
        .rst(rst),
        .ext_instr_word(ext_instr_word),
        .ext_instr_valid(ext_instr_valid),
        .use_ext_instr(use_ext_instr),
        .accel_busy(ctrl_busy),
        .accel_done(accel_done_pulse),
        .accel_result(accel_result_reg),
        .accel_start(core_accel_start),
        .accel_src0(core_accel_src0),
        .accel_src1(core_accel_src1),
        .accel_rd(core_accel_rd_unused),
        .dbg_pc_if(dbg_pc_if),
        .dbg_instr_if(dbg_instr_if),
        .dbg_instr_id(dbg_instr_id),
        .dbg_stall(dbg_stall),
        .dbg_custom_inflight(dbg_custom_inflight),
        .dbg_wb_regwrite(dbg_wb_regwrite),
        .dbg_wb_rd(dbg_wb_rd),
        .dbg_wb_data(dbg_wb_data)
    );

    matrix_accel_4x4_q5_10 matmul_accel (
        .clk(clk),
        .rst(~rst),
        .start(array_start),
        .a_flat(a_flat_reg),
        .b_flat(b_flat_reg),
        .busy(array_busy),
        .done(array_done),
        .c_flat(c_flat_wire),
        .cycle_count(cycle_count_wire)
    );

    assign mat_c_flat = c_flat_wire;
    assign matmul_cycle_count = cycle_count_wire;
    assign dbg_matmul_busy = ctrl_busy;
    assign dbg_matmul_done = accel_done_pulse;
    assign dbg_a00 = a_flat_reg[15:0];
    assign dbg_a01 = a_flat_reg[31:16];
    assign dbg_a02 = a_flat_reg[47:32];
    assign dbg_a03 = a_flat_reg[63:48];
    assign dbg_b00 = b_flat_reg[15:0];
    assign dbg_b01 = b_flat_reg[31:16];
    assign dbg_b02 = b_flat_reg[47:32];
    assign dbg_b03 = b_flat_reg[63:48];
    assign dbg_c00 = c_flat_wire[15:0];
    assign dbg_c01 = c_flat_wire[31:16];
    assign dbg_c02 = c_flat_wire[47:32];
    assign dbg_c03 = c_flat_wire[63:48];

    always @(posedge clk) begin
        if (!rst) begin
            ctrl_busy <= 1'b0;
            accel_done_pulse <= 1'b0;
            accel_result_reg <= STATUS_OK;
            waiting_array_done <= 1'b0;
            array_start <= 1'b0;
            desc_ptr <= 32'd0;
            a_base <= 32'd0;
            b_base <= 32'd0;
            c_base <= 32'd0;
            dim_m <= 16'd0;
            dim_n <= 16'd0;
            dim_k <= 16'd0;
            desc_flags <= 16'd0;
            stride_a <= 32'd0;
            stride_b <= 32'd0;
            stride_c <= 32'd0;
            a_flat_reg <= 256'd0;
            b_flat_reg <= 256'd0;
        end else begin
            accel_done_pulse <= 1'b0;
            array_start <= 1'b0;

            if (host_mem_we) begin
                mem[host_mem_addr[31:2]] <= host_mem_wdata;
            end

            // Launch custom operation: rs1 holds descriptor pointer; rs2 reserved (must be zero)
            if (core_accel_start && !ctrl_busy && !waiting_array_done) begin
                ctrl_busy <= 1'b1;
                status_code = STATUS_OK;
                desc_ptr <= core_accel_src0;

                if (core_accel_src1 != 32'd0) begin
                    status_code = STATUS_BAD_RS2;
                end

                a_base <= mem[(core_accel_src0 + 32'h00) >> 2];
                b_base <= mem[(core_accel_src0 + 32'h04) >> 2];
                c_base <= mem[(core_accel_src0 + 32'h08) >> 2];
                dim_m <= mem[(core_accel_src0 + 32'h0C) >> 2][15:0];
                dim_n <= mem[(core_accel_src0 + 32'h0C) >> 2][31:16];
                dim_k <= mem[(core_accel_src0 + 32'h10) >> 2][15:0];
                desc_flags <= mem[(core_accel_src0 + 32'h10) >> 2][31:16];
                stride_a <= mem[(core_accel_src0 + 32'h14) >> 2];
                stride_b <= mem[(core_accel_src0 + 32'h18) >> 2];
                stride_c <= mem[(core_accel_src0 + 32'h1C) >> 2];

                if ((mem[(core_accel_src0 + 32'h0C) >> 2][15:0] != 16'd4) ||
                    (mem[(core_accel_src0 + 32'h0C) >> 2][31:16] != 16'd4) ||
                    (mem[(core_accel_src0 + 32'h10) >> 2][15:0] != 16'd4)) begin
                    status_code = STATUS_BAD_DIMS;
                end

                if ((mem[(core_accel_src0 + 32'h00) >> 2][0] != 1'b0) ||
                    (mem[(core_accel_src0 + 32'h04) >> 2][0] != 1'b0) ||
                    (mem[(core_accel_src0 + 32'h08) >> 2][0] != 1'b0) ||
                    (mem[(core_accel_src0 + 32'h14) >> 2][0] != 1'b0) ||
                    (mem[(core_accel_src0 + 32'h18) >> 2][0] != 1'b0) ||
                    (mem[(core_accel_src0 + 32'h1C) >> 2][0] != 1'b0)) begin
                    status_code = STATUS_BAD_ALIGN;
                end

                if (status_code != STATUS_OK) begin
                    accel_result_reg <= status_code;
                    accel_done_pulse <= 1'b1;
                    ctrl_busy <= 1'b0;
                end else begin
                    for (rr = 0; rr < N; rr = rr + 1) begin
                        for (cc = 0; cc < N; cc = cc + 1) begin
                            base = ((rr * N) + cc) * 16;

                            elem_addr = mem[(core_accel_src0 + 32'h00) >> 2] + (rr * mem[(core_accel_src0 + 32'h14) >> 2]) + (cc * 2);
                            elem_val = mem_read_half(elem_addr);
                            a_flat_reg[base +: 16] <= elem_val;

                            elem_addr = mem[(core_accel_src0 + 32'h04) >> 2] + (rr * mem[(core_accel_src0 + 32'h18) >> 2]) + (cc * 2);
                            elem_val = mem_read_half(elem_addr);
                            b_flat_reg[base +: 16] <= elem_val;
                        end
                    end

                    array_start <= 1'b1;
                    waiting_array_done <= 1'b1;
                end
            end

            if (waiting_array_done && array_done) begin
                for (rr = 0; rr < N; rr = rr + 1) begin
                    for (cc = 0; cc < N; cc = cc + 1) begin
                        base = ((rr * N) + cc) * 16;
                        elem_addr = c_base + (rr * stride_c) + (cc * 2);
                        mem_write_half(elem_addr, c_flat_wire[base +: 16]);
                    end
                end
                waiting_array_done <= 1'b0;
                ctrl_busy <= 1'b0;
                accel_result_reg <= STATUS_OK;
                accel_done_pulse <= 1'b1;
            end
        end
    end

endmodule
