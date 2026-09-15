module adder_tree #(
    parameter N             = 3,
    parameter PRODUCT_WIDTH = 16,
    parameter ACC_WIDTH     = 20
)(
    input  wire signed [N*N*PRODUCT_WIDTH-1:0] products_in,
    input  wire                                products_valid,
    output wire signed [ACC_WIDTH-1:0]         sum_out,
    output wire                                sum_valid
);
    // No clk/rst in the interface contract -> purely combinational, N=3 (9
    // products) explicit balanced tree. NOT written generically for
    // arbitrary N: the top-level instructions explicitly prefer a simple,
    // verified N=3 implementation over premature generality here.
    genvar gi;
    wire signed [ACC_WIDTH-1:0] p [0:8];
    generate
        for (gi = 0; gi < 9; gi = gi + 1) begin : UNPACK
            // Sign-extend every product to the full accumulator width
            // *before* adding, so every stage below is a plain ACC_WIDTH
            // signed add with no truncation surprises.
            assign p[gi] = {{(ACC_WIDTH-PRODUCT_WIDTH){products_in[(gi+1)*PRODUCT_WIDTH-1]}},
                              products_in[(gi+1)*PRODUCT_WIDTH-1 -: PRODUCT_WIDTH]};
        end
    endgenerate

    // Stage 1
    wire signed [ACC_WIDTH-1:0] s1_0 = p[0] + p[1];
    wire signed [ACC_WIDTH-1:0] s1_1 = p[2] + p[3];
    wire signed [ACC_WIDTH-1:0] s1_2 = p[4] + p[5];
    wire signed [ACC_WIDTH-1:0] s1_3 = p[6] + p[7];
    // p[8] carried forward unpaired (9 is odd)

    // Stage 2
    wire signed [ACC_WIDTH-1:0] s2_0 = s1_0 + s1_1;
    wire signed [ACC_WIDTH-1:0] s2_1 = s1_2 + s1_3;

    // Stage 3 (final)
    assign sum_out   = (s2_0 + s2_1) + p[8];
    assign sum_valid = products_valid;
endmodule