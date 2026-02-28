`timescale 1ns/1ps

module tb_matrix_accel_4x4;

    reg clk;
    reg rst;
    reg start;
    reg [255:0] a_flat;
    reg [255:0] b_flat;
    wire busy;
    wire done;
    wire [255:0] c_flat;
    wire [7:0] cycle_count;

    integer r;
    integer c;
    integer pass_count;
    integer total_count;
    integer case_ok;

    matrix_accel_4x4_q5_10 dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_flat(a_flat),
        .b_flat(b_flat),
        .busy(busy),
        .done(done),
        .c_flat(c_flat),
        .cycle_count(cycle_count)
    );

    task set_elem;
        inout [255:0] mat;
        input integer row;
        input integer col;
        input signed [15:0] val;
        integer base;
        begin
            base = ((row * 4) + col) * 16;
            mat[base +: 16] = val;
        end
    endtask

    function signed [15:0] get_elem;
        input [255:0] mat;
        input integer row;
        input integer col;
        integer base;
        begin
            base = ((row * 4) + col) * 16;
            get_elem = mat[base +: 16];
        end
    endfunction

    task pulse_start;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    task wait_done;
        begin
            while (!done) begin
                @(posedge clk);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        start = 1'b0;
        a_flat = 256'd0;
        b_flat = 256'd0;
        pass_count = 0;
        total_count = 0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        // Test 1: A x I = A
        a_flat = 256'd0;
        b_flat = 256'd0;
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                set_elem(a_flat, r, c, ((r * 4 + c + 1) <<< 10));
                if (r == c) begin
                    set_elem(b_flat, r, c, (1 <<< 10));
                end else begin
                    set_elem(b_flat, r, c, 16'sd0);
                end
            end
        end

        pulse_start();
        wait_done();

        total_count = total_count + 1;
        case_ok = 1;
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                if (get_elem(c_flat, r, c) !== get_elem(a_flat, r, c)) begin
                    case_ok = 0;
                    $display("MISMATCH test=identity row=%0d col=%0d got=%0d expected=%0d",
                             r, c, get_elem(c_flat, r, c), get_elem(a_flat, r, c));
                end
            end
        end
        if (case_ok) begin
            pass_count = pass_count + 1;
        end
        $display("RESULT test=identity pass=%0d accel_cycles=%0d", case_ok, cycle_count);

        // Test 2: Ones x Ones => each output = 4.0 (Q5.10)
        a_flat = 256'd0;
        b_flat = 256'd0;
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                set_elem(a_flat, r, c, (1 <<< 10));
                set_elem(b_flat, r, c, (1 <<< 10));
            end
        end

        pulse_start();
        wait_done();

        total_count = total_count + 1;
        case_ok = 1;
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                if (get_elem(c_flat, r, c) !== (4 <<< 10)) begin
                    case_ok = 0;
                    $display("MISMATCH test=ones row=%0d col=%0d got=%0d expected=%0d",
                             r, c, get_elem(c_flat, r, c), (4 <<< 10));
                end
            end
        end
        if (case_ok) begin
            pass_count = pass_count + 1;
        end
        $display("RESULT test=ones pass=%0d accel_cycles=%0d", case_ok, cycle_count);

        $display("SUMMARY pass=%0d total=%0d", pass_count, total_count);
        if (pass_count != total_count) begin
            $fatal(1, "Simulation failed one or more checks.");
        end
        $finish;
    end

endmodule
