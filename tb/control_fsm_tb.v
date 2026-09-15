`timescale 1ns/1ps

module control_fsm_tb;
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg buffer_ready = 0;
    reg window_valid = 0;
    reg compute_done = 0;
    wire kernel_load_enable, buffer_enable, compute_enable, output_enable;
    wire busy, done;

    control_fsm #(.PIPE_LATENCY(5)) dut (
        .clk, .rst, .start, .buffer_ready, .window_valid, .compute_done,
        .kernel_load_enable, .buffer_enable, .compute_enable, .output_enable,
        .busy, .done
    );
    always #5 clk = ~clk;

    initial begin
        repeat (2) @(posedge clk);
        #1;
        if (busy || done) begin $display("FAIL reset status"); $fatal; end
        rst = 0;

        @(negedge clk); start = 1;
        @(posedge clk); #1;
        if (!busy || !kernel_load_enable) begin $display("FAIL LOAD_KERNEL state"); $fatal; end

        @(posedge clk); #1;
        if (!busy || !buffer_enable) begin $display("FAIL FILL_BUFFER state"); $fatal; end

        @(negedge clk); buffer_ready = 1;
        @(posedge clk); #1;
        if (!busy || !compute_enable) begin $display("FAIL COMPUTE transition"); $fatal; end
        buffer_ready = 0;

        @(negedge clk); compute_done = 1;
        @(posedge clk); #1;
        compute_done = 0;
        if (!busy || !compute_enable) begin $display("FAIL DRAIN entry"); $fatal; end

        repeat (5) @(posedge clk);
        #1;
        if (!done || !busy) begin $display("FAIL DONE state"); $fatal; end
        @(posedge clk); #1;
        if (done || busy) begin $display("FAIL DONE pulse/return to idle"); $fatal; end

        $display("CONTROL_FSM PASS");
        $finish;
    end
endmodule
