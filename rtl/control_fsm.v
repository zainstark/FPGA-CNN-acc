module control_fsm #(
    parameter IMAGE_WIDTH  = 32,
    parameter IMAGE_HEIGHT = 32,
    parameter N            = 3,
    parameter PIPE_LATENCY  = 5 

)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire buffer_ready,   // = line_buffer.column_valid (rows filled)
    input  wire window_valid,   // = window_generator.window_valid
    input  wire compute_done,   // = conv_top pixel counter reaching W*H
    output reg  kernel_load_enable,
    output reg  buffer_enable,
    output reg  compute_enable,
    output reg  output_enable,
    output reg  busy,
    output reg  done
);
    

    localparam [2:0]
        S_IDLE=3'd0, S_LOAD_KERNEL=3'd1, S_FILL_BUFFER=3'd2,
        S_COMPUTE=3'd3, S_DRAIN=3'd4, S_DONE=3'd5;

    reg [2:0] state, next_state;
    reg [$clog2(PIPE_LATENCY+1)-1:0] drain_cnt;

    always @(posedge clk)
        if (rst) state <= S_IDLE; else state <= next_state;

    always @(*) begin
        next_state = state;
        case (state)
            // LOAD_KERNEL is a nominal 1-cycle status state: kernel loading
            // in this design happens independently via kernel_valid/addr
            // whenever !busy (per interfaces.md §2.3/§3, "kernel should
            // normally be loaded before start"), so it does not gate
            // anything here -- it exists so the required FSM diagram has
            // a literal, observable LOAD_KERNEL state.
            S_IDLE:        next_state = start ? S_LOAD_KERNEL : S_IDLE;
            S_LOAD_KERNEL: next_state = S_FILL_BUFFER;
            S_FILL_BUFFER: next_state = (window_valid || buffer_ready) ? S_COMPUTE : S_FILL_BUFFER;
            S_COMPUTE:     next_state = compute_done ? S_DRAIN : S_COMPUTE;
            S_DRAIN:       next_state = (drain_cnt >= PIPE_LATENCY-1) ? S_DONE : S_DRAIN;
            S_DONE:        next_state = S_IDLE;
            default:       next_state = S_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (rst) drain_cnt <= 0;
        else if (state == S_DRAIN) drain_cnt <= drain_cnt + 1'b1;
        else drain_cnt <= 0;
    end

    always @(*) begin
        kernel_load_enable = (state == S_LOAD_KERNEL);
        buffer_enable      = (state == S_FILL_BUFFER) || (state == S_COMPUTE);
        compute_enable     = (state == S_COMPUTE) || (state == S_DRAIN);
        output_enable      = (state == S_COMPUTE) || (state == S_DRAIN) || (state == S_DONE);
        busy               = (state != S_IDLE);
        done               = (state == S_DONE);
    end
endmodule