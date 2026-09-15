`timescale 1ns/1ps

module output_stage_tb;
    reg clk = 0;
    reg rst = 1;
    reg signed [19:0] data_in = 0;
    reg data_valid = 0;
    wire signed [15:0] data_out;
    wire output_valid;

    output_stage dut (.clk, .rst, .data_in, .data_valid, .data_out, .output_valid);
    always #5 clk = ~clk;

    task check;
        input integer value;
        input integer expected;
        begin
            @(negedge clk);
            data_in = value;
            data_valid = 1;
            @(posedge clk);
            #1;
            if (!output_valid || $signed(data_out) !== expected) begin
                $display("FAIL value=%0d expected=%0d got=%0d valid=%b", value, expected, $signed(data_out), output_valid);
                $fatal;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst = 0;
        check(0, 0);
        check(32767, 32767);
        check(32768, 32767);
        check(-32768, -32768);
        check(-32769, -32768);
        check(12345, 12345);
        @(negedge clk);
        data_valid = 0;
        @(posedge clk);
        #1;
        if (output_valid) begin $display("FAIL invalid input propagated"); $fatal; end
        $display("OUTPUT_STAGE PASS");
        $finish;
    end
endmodule
