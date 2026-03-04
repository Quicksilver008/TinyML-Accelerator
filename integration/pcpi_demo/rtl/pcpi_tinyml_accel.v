`timescale 1ns/1ps

module pcpi_tinyml_accel (
    input wire clk,
    input wire resetn,

    input wire        pcpi_valid,
    input wire [31:0] pcpi_insn,
    input wire [31:0] pcpi_rs1,
    input wire [31:0] pcpi_rs2,
    output wire       pcpi_wr,
    output wire [31:0] pcpi_rd,
    output wire       pcpi_wait,
    output wire       pcpi_ready,

    output reg        accel_mem_valid,
    output reg        accel_mem_we,
    output reg [31:0] accel_mem_addr,
    output reg [31:0] accel_mem_wdata,
    input wire [31:0] accel_mem_rdata,
    input wire        accel_mem_ready
);

    // Custom instruction encoding (R-type over custom-0 opcode)
    localparam [6:0] OPCODE_CUSTOM0 = 7'b0001011;
    localparam [2:0] FUNCT3_MATMUL  = 3'b000;
    localparam [6:0] FUNCT7_MATMUL  = 7'b0101010;

    localparam [31:0] C_BASE_ADDR = 32'h0000_0200;

    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_LOAD_A   = 3'd1;
    localparam [2:0] S_LOAD_B   = 3'd2;
    localparam [2:0] S_KICK     = 3'd3;
    localparam [2:0] S_WAIT_ACC = 3'd4;
    localparam [2:0] S_STORE_C  = 3'd5;
    localparam [2:0] S_RESP     = 3'd6;

    reg [2:0] state;
    reg [4:0] elem_idx;
    reg [31:0] base_a;
    reg [31:0] base_b;

    reg [255:0] a_flat;
    reg [255:0] b_flat;
    reg accel_start;
    reg resp_valid;
    reg [31:0] result_reg;

    wire accel_busy;
    wire accel_done;
    wire [255:0] c_flat;
    wire [7:0] accel_cycle_count;

    wire insn_match;
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;

    assign opcode = pcpi_insn[6:0];
    assign funct3 = pcpi_insn[14:12];
    assign funct7 = pcpi_insn[31:25];
    assign insn_match = (opcode == OPCODE_CUSTOM0) && (funct3 == FUNCT3_MATMUL) && (funct7 == FUNCT7_MATMUL);

    function [31:0] c_elem_word;
        input [255:0] c_vec;
        input [4:0] idx;
        reg signed [15:0] elem;
        begin
            elem = c_vec[(idx * 16) +: 16];
            c_elem_word = {{16{elem[15]}}, elem};
        end
    endfunction

    matrix_accel_4x4_q5_10 accel_uut (
        .clk(clk),
        .rst(!resetn),
        .start(accel_start),
        .a_flat(a_flat),
        .b_flat(b_flat),
        .busy(accel_busy),
        .done(accel_done),
        .c_flat(c_flat),
        .cycle_count(accel_cycle_count)
    );

    always @(*) begin
        accel_mem_valid = 1'b0;
        accel_mem_we = 1'b0;
        accel_mem_addr = 32'd0;
        accel_mem_wdata = 32'd0;

        case (state)
            S_LOAD_A: begin
                accel_mem_valid = 1'b1;
                accel_mem_addr = base_a + (elem_idx << 2);
            end
            S_LOAD_B: begin
                accel_mem_valid = 1'b1;
                accel_mem_addr = base_b + (elem_idx << 2);
            end
            S_STORE_C: begin
                accel_mem_valid = 1'b1;
                accel_mem_we = 1'b1;
                accel_mem_addr = C_BASE_ADDR + (elem_idx << 2);
                accel_mem_wdata = c_elem_word(c_flat, elem_idx);
            end
            default: begin
            end
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE;
            elem_idx <= 5'd0;
            base_a <= 32'd0;
            base_b <= 32'd0;
            a_flat <= 256'd0;
            b_flat <= 256'd0;
            accel_start <= 1'b0;
            resp_valid <= 1'b0;
            result_reg <= 32'd0;
        end else begin
            accel_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    resp_valid <= 1'b0;
                    if (pcpi_valid && insn_match) begin
                        base_a <= pcpi_rs1;
                        base_b <= pcpi_rs2;
                        elem_idx <= 5'd0;
                        state <= S_LOAD_A;
                    end
                end

                S_LOAD_A: begin
                    if (accel_mem_ready) begin
                        a_flat[(elem_idx * 16) +: 16] <= accel_mem_rdata[15:0];
                        if (elem_idx == 5'd15) begin
                            elem_idx <= 5'd0;
                            state <= S_LOAD_B;
                        end else begin
                            elem_idx <= elem_idx + 5'd1;
                        end
                    end
                end

                S_LOAD_B: begin
                    if (accel_mem_ready) begin
                        b_flat[(elem_idx * 16) +: 16] <= accel_mem_rdata[15:0];
                        if (elem_idx == 5'd15) begin
                            elem_idx <= 5'd0;
                            state <= S_KICK;
                        end else begin
                            elem_idx <= elem_idx + 5'd1;
                        end
                    end
                end

                S_KICK: begin
                    accel_start <= 1'b1;
                    state <= S_WAIT_ACC;
                end

                S_WAIT_ACC: begin
                    if (accel_done) begin
                        elem_idx <= 5'd0;
                        state <= S_STORE_C;
                    end
                end

                S_STORE_C: begin
                    if (accel_mem_ready) begin
                        if (elem_idx == 5'd15) begin
                            result_reg <= c_elem_word(c_flat, 5'd0);
                            resp_valid <= 1'b1;
                            state <= S_RESP;
                        end else begin
                            elem_idx <= elem_idx + 5'd1;
                        end
                    end
                end

                S_RESP: begin
                    if (!pcpi_valid) begin
                        resp_valid <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    assign pcpi_wait = pcpi_valid && insn_match && !resp_valid;
    assign pcpi_ready = pcpi_valid && insn_match && resp_valid;
    assign pcpi_wr = pcpi_ready;
    assign pcpi_rd = result_reg;

endmodule
