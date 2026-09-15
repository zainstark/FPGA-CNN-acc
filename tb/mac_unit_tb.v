`timescale 1ns/1ps

module mac_unit_tb;
    reg clk = 0;
    reg rst = 1;
    reg [9*8-1:0] window_in = 0;
    reg signed [9*8-1:0] kernel_in = 0;
    reg window_valid = 0;
    wire signed [19:0] result_out;
    wire result_valid;

    mac_unit dut (.clk, .rst, .window_in, .kernel_in, .window_valid, .result_out, .result_valid);
    always #5 clk = ~clk;

    task check;
        input integer pixel;
        input integer coefficient;
        input integer expected;
        integer i;
        begin
            @(negedge clk);
            for (i = 0; i < 9; i = i + 1) begin
                window_in[i*8 +: 8] = pixel;
                kernel_in[i*8 +: 8] = coefficient;
            end
            window_valid = 1;
            @(posedge clk);
            #1;
            if (!result_valid || $signed(result_out) !== expected) begin
                $display("FAIL pixel=%0d coefficient=%0d expected=%0d got=%0d valid=%b", pixel, coefficient, expected, $signed(result_out), result_valid);
                $fatal;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst = 0;
        check(0, 127, 0);
        check(10, 1, 90);
        check(10, -1, -90);
        check(255, 127, 9*255*127);
        check(255, -128, 9*255*(-128));
        @(negedge clk);
        window_valid = 0;
        @(posedge clk);
        #1;
        if (result_valid) begin $display("FAIL invalid window propagated"); $fatal; end
        $display("MAC_UNIT PASS");
        $finish;
    end
endmodule
