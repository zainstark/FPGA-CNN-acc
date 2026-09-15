module output_stage #(
    parameter ACC_WIDTH = 20,
    parameter OUT_WIDTH = 16
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire signed [ACC_WIDTH-1:0] data_in,
    input  wire                        data_valid,
    output reg  signed [OUT_WIDTH-1:0] data_out,
    output reg                         output_valid
);
    localparam signed [ACC_WIDTH-1:0] SAT_MAX = (1 <<< (OUT_WIDTH-1)) - 1; //  32767
    localparam signed [ACC_WIDTH-1:0] SAT_MIN = -(1 <<< (OUT_WIDTH-1));    // -32768

    wire signed [OUT_WIDTH-1:0] sat_comb =
        (data_in > SAT_MAX) ? SAT_MAX[OUT_WIDTH-1:0] :
        (data_in < SAT_MIN) ? SAT_MIN[OUT_WIDTH-1:0] :
                               data_in[OUT_WIDTH-1:0];

    always @(posedge clk) begin
        if (rst) begin
            data_out     <= {OUT_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end else begin
            data_out     <= sat_comb;
            output_valid <= data_valid;
        end
    end
endmodule