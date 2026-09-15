module line_buffer #(
    parameter N           = 3,
    parameter DATA_WIDTH  = 8,
    parameter IMAGE_WIDTH = 32
)(
    input  wire                            clk,
    input  wire                            rst,
    input  wire [DATA_WIDTH-1:0]           pixel_in,
    input  wire                            pixel_valid,
    output wire                            pixel_ready,

    output reg  [N*DATA_WIDTH-1:0]         column_pixels,
    output reg                             column_valid,
    output reg  [$clog2(IMAGE_WIDTH)-1:0]  column,
    output reg  [$clog2(IMAGE_WIDTH)-1:0]  row   // reused width; row < IMAGE_HEIGHT assumed <= IMAGE_WIDTH bits
);
    // Sustains one accepted pixel/cycle; no internal stalling.
    assign pixel_ready = 1'b1;
    wire accepted = pixel_valid;

    // Circular buffer holding the last 2 full rows (N-1 rows for general N).
    // buf_mem[wptr]            = pixel written 2*IMAGE_WIDTH cycles ago = X(row-2,col)
    // buf_mem[wptr+IMAGE_WIDTH]= pixel written   IMAGE_WIDTH cycles ago = X(row-1,col)
    localparam DEPTH = (N-1)*IMAGE_WIDTH;
    reg [DATA_WIDTH-1:0] buf_mem [0:DEPTH-1];
    reg [$clog2(DEPTH)-1:0] wptr;

    reg [$clog2(IMAGE_WIDTH)-1:0] col_cnt;
    reg [$clog2(IMAGE_WIDTH)-1:0] row_cnt;

    integer k;
    // Vertical taps read combinationally before this cycle's write.
    wire [DATA_WIDTH-1:0] vtap [0:N-2];
    genvar gv;
    generate
        for (gv = 0; gv < N-1; gv = gv + 1) begin : VTAP
            // gv=0 -> oldest row tap (row-(N-1)); gv=N-2 -> row-1 tap
            assign vtap[gv] = buf_mem[(wptr + gv*IMAGE_WIDTH) % DEPTH];
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            wptr         <= 0;
            col_cnt      <= 0;
            row_cnt      <= 0;
            column_valid <= 1'b0;
            column_pixels<= {(N*DATA_WIDTH){1'b0}};
            column       <= 0;
            row          <= 0;
        end else if (accepted) begin
            // Register the taps + current pixel as this cycle's column output
            // (index N-1 = current row, per row-major flattening convention).
            column_pixels[(N*DATA_WIDTH)-1 -: DATA_WIDTH] <= pixel_in; // element N-1
            for (k = 0; k < N-1; k = k + 1)
                column_pixels[(k+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= vtap[k]; // elements 0..N-2
            column_valid <= (row_cnt >= (N-1));
            column       <= col_cnt;
            row          <= row_cnt;

            // Write current pixel into the delay line, advance write pointer.
            buf_mem[wptr] <= pixel_in;
            wptr <= (wptr + 1) % DEPTH;

            // Advance row/column counters (raster order).
            if (col_cnt == IMAGE_WIDTH-1) begin
                col_cnt <= 0;
                row_cnt <= row_cnt + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end else begin
            column_valid <= 1'b0;
        end
    end
endmodule