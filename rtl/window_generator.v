// NOTE: adds one port ("column") beyond interfaces.md's *recommended*
// window_generator port list. Justification: interfaces.md requires
// window_valid = (row>=N-1) && (column>=N-1) (see interfaces.md §5.2),
// but the recommended port list only carries column_valid (which encodes
// the row condition). Without the actual column value the module cannot
// tell where a row wraps, so horizontal validity could never re-arm after
// the first row. `column` is sourced directly from line_buffer's existing
// output -- no other module's interface is touched.
module window_generator #(
    parameter N           = 3,
    parameter DATA_WIDTH  = 8,
    parameter IMAGE_WIDTH = 32
)(
    input  wire                              clk,
    input  wire                              rst,
    input  wire [N*DATA_WIDTH-1:0]           column_pixels,
    input  wire                              column_valid,
    input  wire [$clog2(IMAGE_WIDTH)-1:0]    column,

    output reg  [N*N*DATA_WIDTH-1:0]         window_out,
    output reg                               window_valid
);
    // Horizontal history: hist[0] = 1 column ago ... hist[N-2] = N-1 ago.
    reg [N*DATA_WIDTH-1:0] hist [0:N-2];
    integer h;

    wire [N*DATA_WIDTH-1:0] taps [0:N-1];
    assign taps[0] = column_pixels; // current column (newest)
    genvar gk;
    generate
        for (gk = 1; gk < N; gk = gk + 1) begin : TAP_MAP
            assign taps[gk] = hist[gk-1];
        end
    endgenerate

    // window[row_idx*N + col_idx]: col_idx=N-1 -> current column (taps[0]),
    // col_idx=0 -> oldest column (taps[N-1]); row_idx selects the vertical
    // element within that tap. Matches interfaces.md §1.3 row-major order
    // and the worked example in §15.
    wire [N*N*DATA_WIDTH-1:0] window_comb;
    genvar gr, gc;
    generate
        for (gr = 0; gr < N; gr = gr + 1) begin : ROW
            for (gc = 0; gc < N; gc = gc + 1) begin : COL
                assign window_comb[(gr*N+gc+1)*DATA_WIDTH-1 -: DATA_WIDTH] =
                    taps[N-1-gc][(gr+1)*DATA_WIDTH-1 -: DATA_WIDTH];
            end
        end
    endgenerate

    wire window_valid_comb = column_valid && (column >= (N-1));

    always @(posedge clk) begin
        if (rst) begin
            for (h = 0; h < N-1; h = h + 1)
                hist[h] <= {(N*DATA_WIDTH){1'b0}};
            window_out   <= {(N*N*DATA_WIDTH){1'b0}};
            window_valid <= 1'b0;
        end else begin
            window_out   <= window_comb;
            window_valid <= window_valid_comb;
            if (column_valid) begin
                for (h = N-2; h > 0; h = h - 1)
                    hist[h] <= hist[h-1];
                hist[0] <= column_pixels;
            end
        end
    end
endmodule