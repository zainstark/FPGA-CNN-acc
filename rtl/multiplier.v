module multiplier #(
    parameter DATA_WIDTH    = 8,
    parameter KERNEL_WIDTH  = 8,
    parameter PRODUCT_WIDTH = 16
)(
    input  wire [DATA_WIDTH-1:0]           pixel_in,
    input  wire signed [KERNEL_WIDTH-1:0]  kernel_in,
    output wire signed [PRODUCT_WIDTH-1:0] product_out
);
    // pixel_in is unsigned. Verilog's rule "mixed signed/unsigned operands
    // -> whole expression is unsigned" is the classic bug here. Fix: make
    // the pixel explicitly signed by prepending a literal 0 sign bit
    // (value is unchanged, 0..255, but the multiply below is now a true
    // signed x signed multiply).
    wire signed [DATA_WIDTH:0] pixel_signed = {1'b0, pixel_in};
    

    // Max |product| = 255*128 = 32640, fits in 16-bit signed (max 32767),
    // so no product-level saturation is required (confirmed by golden model).
    assign product_out  = pixel_signed * kernel_in;
endmodule