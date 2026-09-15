module mac_unit #(
    parameter N             = 3,
    parameter DATA_WIDTH    = 8,
    parameter KERNEL_WIDTH  = 8,
    parameter PRODUCT_WIDTH = 16,
    parameter ACC_WIDTH     = 20
)(
    input  wire                               clk,
    input  wire                               rst,
    input  wire [N*N*DATA_WIDTH-1:0]          window_in,
    input  wire signed [N*N*KERNEL_WIDTH-1:0] kernel_in,
    input  wire                               window_valid,
    output reg  signed [ACC_WIDTH-1:0]        result_out,
    output reg                                result_valid
);
    genvar gi;
    wire signed [N*N*PRODUCT_WIDTH-1:0] products;

    generate
        for (gi = 0; gi < N*N; gi = gi + 1) begin : MULT
            multiplier #(
                .DATA_WIDTH   (DATA_WIDTH),
                .KERNEL_WIDTH (KERNEL_WIDTH),
                .PRODUCT_WIDTH(PRODUCT_WIDTH)
            ) u_mult (
                .pixel_in   (window_in [(gi+1)*DATA_WIDTH-1   -: DATA_WIDTH]),
                .kernel_in  (kernel_in [(gi+1)*KERNEL_WIDTH-1 -: KERNEL_WIDTH]),
                .product_out(products  [(gi+1)*PRODUCT_WIDTH-1 -: PRODUCT_WIDTH])
            );
        end
    endgenerate

    wire signed [ACC_WIDTH-1:0] sum_comb;
    wire                        sum_valid_comb;

    adder_tree #(
        .N(N), .PRODUCT_WIDTH(PRODUCT_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) u_adder_tree (
        .products_in   (products),
        .products_valid(window_valid),
        .sum_out       (sum_comb),
        .sum_valid     (sum_valid_comb)
    );

    // One pipeline register: result_valid tracks window_valid delayed 1 cycle.
    always @(posedge clk) begin
        if (rst) begin
            result_out   <= {ACC_WIDTH{1'b0}};
            result_valid <= 1'b0;
        end else begin
            result_out   <= sum_comb;
            result_valid <= sum_valid_comb;
        end
    end
endmodule