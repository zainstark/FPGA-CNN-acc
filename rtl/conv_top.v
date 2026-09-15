module conv_top #(
    parameter N             = 3,
    parameter DATA_WIDTH    = 8,
    parameter KERNEL_WIDTH  = 8,
    parameter PRODUCT_WIDTH = 16,
    parameter ACC_WIDTH     = 20,
    parameter OUT_WIDTH     = 16,
    parameter IMAGE_WIDTH   = 32,
    parameter IMAGE_HEIGHT  = 32
)(
    input  wire                            clk,
    input  wire                            rst,
    input  wire                            start,

    input  wire [DATA_WIDTH-1:0]           pixel_in,
    input  wire                            pixel_valid,
    output wire                            pixel_ready,

    input  wire signed [KERNEL_WIDTH-1:0]  kernel_in,
    input  wire [$clog2(N*N)-1:0]          kernel_addr,
    input  wire                            kernel_valid,

    output wire signed [OUT_WIDTH-1:0]     pixel_out,
    output wire                            output_valid,
    input  wire                            output_ready,

    output wire                            busy,
    output wire                            done
);
    localparam integer TOTAL_PIXELS = IMAGE_WIDTH*IMAGE_HEIGHT;
    localparam integer PIPE_LATENCY = 5;
    localparam integer OUTQ_DEPTH   = 8; // >= PIPE_LATENCY, gives stall margin

    // ---------------- Internal datapath/control signals ----------------
    wire compute_done;
    wire lb_column_valid;
    wire wg_window_valid;

    reg [$clog2(OUTQ_DEPTH):0] outq_count;

    // ---------------- Kernel register bank (§3) ----------------
    // Independent of control_fsm state; only blocked while busy, per
    // "no kernel coefficient should change during a running convolution".
    reg signed [KERNEL_WIDTH-1:0] kernel_mem [0:N*N-1];
    integer ki;
    always @(posedge clk) begin
        if (rst) begin
            for (ki = 0; ki < N*N; ki = ki + 1) kernel_mem[ki] <= {KERNEL_WIDTH{1'b0}};
        end else if (kernel_valid && !busy) begin
            kernel_mem[kernel_addr] <= kernel_in;
        end
    end

    wire signed [N*N*KERNEL_WIDTH-1:0] kernel_flat;
    genvar gk;
    generate
        for (gk = 0; gk < N*N; gk = gk + 1) begin : KFLAT
            assign kernel_flat[(gk+1)*KERNEL_WIDTH-1 -: KERNEL_WIDTH] = kernel_mem[gk];
        end
    endgenerate

    // ---------------- Control FSM ----------------
    wire fsm_buffer_enable, fsm_compute_enable, fsm_output_enable, fsm_kernel_load_enable;

    control_fsm #(.IMAGE_WIDTH(IMAGE_WIDTH), .PIPE_LATENCY(PIPE_LATENCY), .IMAGE_HEIGHT(IMAGE_HEIGHT), .N(N)) u_fsm (
        .clk(clk), .rst(rst), .start(start),
        .buffer_ready(lb_column_valid),
        .window_valid(wg_window_valid),
        .compute_done(compute_done),
        .kernel_load_enable(fsm_kernel_load_enable),
        .buffer_enable(fsm_buffer_enable),
        .compute_enable(fsm_compute_enable),
        .output_enable(fsm_output_enable),
        .busy(busy), .done(done)
    );

    // Soft reset pulse at the start of every new frame (busy 0->1 edge),
    // so line_buffer/window_generator/mac_unit/output_stage state never
    // leaks between successive frames. Global rst still resets everything.
    reg busy_d;
    always @(posedge clk) if (rst) busy_d <= 1'b0; else busy_d <= busy;
    wire frame_start_pulse = busy && !busy_d;
    wire soft_rst = rst | frame_start_pulse;

    // ---------------- Pixel acceptance / frame pixel counter ----------------
    reg [$clog2(TOTAL_PIXELS+1)-1:0] pixel_count;
    wire accepted_pixel = pixel_valid && pixel_ready;
    always @(posedge clk) begin
        if (rst || !busy) pixel_count <= 0;
        else if (accepted_pixel) pixel_count <= pixel_count + 1'b1;
    end
    assign compute_done = (pixel_count == TOTAL_PIXELS[$clog2(TOTAL_PIXELS+1)-1:0]);

    // pixel_ready: accept only while busy, only until the frame's 1024
    // pixels are in, and only while the output queue has enough free
    // slots to absorb every pixel already in flight (PIPE_LATENCY) without
    // ever overflowing, even if the consumer stops draining immediately.
    assign pixel_ready = busy && !frame_start_pulse && !compute_done &&
                          (outq_count <= (OUTQ_DEPTH - PIPE_LATENCY - 1));

    // ---------------- Datapath ----------------
    wire [DATA_WIDTH-1:0] lb_column_pixels_unused; // (kept for clarity only)
    wire [N*DATA_WIDTH-1:0] lb_column_pixels;
    wire [$clog2(IMAGE_WIDTH)-1:0] lb_column, lb_row;

    line_buffer #(.N(N), .DATA_WIDTH(DATA_WIDTH), .IMAGE_WIDTH(IMAGE_WIDTH)) u_lb (
        .clk(clk), .rst(soft_rst),
        .pixel_in(pixel_in),
        .pixel_valid(accepted_pixel),
        .pixel_ready(), // unused: line_buffer always accepts; gating is done above
        .column_pixels(lb_column_pixels),
        .column_valid(lb_column_valid),
        .column(lb_column),
        .row(lb_row)
    );

    wire [N*N*DATA_WIDTH-1:0] wg_window_out;

    window_generator #(.N(N), .DATA_WIDTH(DATA_WIDTH), .IMAGE_WIDTH(IMAGE_WIDTH)) u_wg (
        .clk(clk), .rst(soft_rst),
        .column_pixels(lb_column_pixels),
        .column_valid(lb_column_valid),
        .column(lb_column),
        .window_out(wg_window_out),
        .window_valid(wg_window_valid)
    );

    wire signed [ACC_WIDTH-1:0] mac_result;
    wire mac_result_valid;

    mac_unit #(.N(N), .DATA_WIDTH(DATA_WIDTH), .KERNEL_WIDTH(KERNEL_WIDTH),
               .PRODUCT_WIDTH(PRODUCT_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_mac (
        .clk(clk), .rst(soft_rst),
        .window_in(wg_window_out),
        .kernel_in(kernel_flat),
        .window_valid(wg_window_valid),
        .result_out(mac_result),
        .result_valid(mac_result_valid)
    );

    wire signed [OUT_WIDTH-1:0] os_data_out;
    wire os_output_valid;

    output_stage #(.ACC_WIDTH(ACC_WIDTH), .OUT_WIDTH(OUT_WIDTH)) u_os (
        .clk(clk), .rst(soft_rst),
        .data_in(mac_result),
        .data_valid(mac_result_valid),
        .data_out(os_data_out),
        .output_valid(os_output_valid)
    );

    // ---------------- Output queue (backpressure-safe, see audit §2d) ----------------
    reg signed [OUT_WIDTH-1:0] outq_mem [0:OUTQ_DEPTH-1];
    reg [$clog2(OUTQ_DEPTH)-1:0] outq_wptr, outq_rptr;

    wire push = os_output_valid;
    wire pop  = output_valid && output_ready;

    assign output_valid = (outq_count != 0);
    assign pixel_out    = outq_mem[outq_rptr];

    always @(posedge clk) begin
        if (rst || frame_start_pulse) begin
            outq_count <= 0; outq_wptr <= 0; outq_rptr <= 0;
        end else begin
            case ({push, pop})
                2'b10: begin
                    outq_mem[outq_wptr] <= os_data_out;
                    outq_wptr  <= outq_wptr + 1'b1;
                    outq_count <= outq_count + 1'b1;
                end
                2'b01: begin
                    outq_rptr  <= outq_rptr + 1'b1;
                    outq_count <= outq_count - 1'b1;
                end
                2'b11: begin
                    outq_mem[outq_wptr] <= os_data_out;
                    outq_wptr <= outq_wptr + 1'b1;
                    outq_rptr <= outq_rptr + 1'b1;
                    // count unchanged
                end
                default: ;
            endcase
        end
    end
endmodule