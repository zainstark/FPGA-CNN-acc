`timescale 1ns/1ps

module conv_tb;
    localparam N            = 3;
    localparam DATA_WIDTH   = 8;
    localparam KERNEL_WIDTH = 8;
    localparam PRODUCT_WIDTH= 16;
    localparam ACC_WIDTH    = 20;
    localparam OUT_WIDTH    = 16;
    localparam IMAGE_WIDTH  = 32;
    localparam IMAGE_HEIGHT = 32;
    localparam OUT_H        = IMAGE_HEIGHT - N + 1; // 30
    localparam OUT_W        = IMAGE_WIDTH  - N + 1; // 30
    localparam CLK_PERIOD   = 10;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg  [DATA_WIDTH-1:0] pixel_in;
    reg                   pixel_valid;
    wire                  pixel_ready;

    reg  signed [KERNEL_WIDTH-1:0] kernel_in;
    reg  [$clog2(N*N)-1:0]         kernel_addr;
    reg                            kernel_valid;

    wire signed [OUT_WIDTH-1:0] pixel_out;
    wire output_valid;
    reg  output_ready = 1'b1;

    wire busy, done;

    conv_top #(
        .N(N), .DATA_WIDTH(DATA_WIDTH), .KERNEL_WIDTH(KERNEL_WIDTH),
        .PRODUCT_WIDTH(PRODUCT_WIDTH), .ACC_WIDTH(ACC_WIDTH), .OUT_WIDTH(OUT_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) dut (
        .clk(clk), .rst(rst), .start(start),
        .pixel_in(pixel_in), .pixel_valid(pixel_valid), .pixel_ready(pixel_ready),
        .kernel_in(kernel_in), .kernel_addr(kernel_addr), .kernel_valid(kernel_valid),
        .pixel_out(pixel_out), .output_valid(output_valid), .output_ready(output_ready),
        .busy(busy), .done(done)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // --------- test-vector storage ---------
    reg [DATA_WIDTH-1:0] image [0:IMAGE_HEIGHT-1][0:IMAGE_WIDTH-1];
    reg signed [KERNEL_WIDTH-1:0] kernel [0:N-1][0:N-1];
    reg signed [OUT_WIDTH-1:0] expected [0:OUT_H-1][0:OUT_W-1];

    integer total_mismatches = 0;
    integer total_cases      = 0;

    task load_case;
        input [8*128-1:0] case_dir;
        integer fh, r, c, v;
        integer tmp;
        begin
            fh = $fopen({case_dir, "/image.txt"}, "r");
            if (fh == 0) begin $display("ERROR: cannot open %0s/image.txt", case_dir); $finish; end
            for (r = 0; r < IMAGE_HEIGHT; r = r + 1)
                for (c = 0; c < IMAGE_WIDTH; c = c + 1) begin
                    v = $fscanf(fh, "%d", tmp);
                    if (v != 1) begin
                        $display("ERROR: %0s/image.txt malformed at row %0d col %0d (fscanf returned %0d)",
                                  case_dir, r, c, v);
                        $finish;
                    end
                    image[r][c] = tmp[DATA_WIDTH-1:0];
                end
            $fclose(fh);

            fh = $fopen({case_dir, "/kernel.txt"}, "r");
            if (fh == 0) begin $display("ERROR: cannot open %0s/kernel.txt", case_dir); $finish; end
            for (r = 0; r < N; r = r + 1)
                for (c = 0; c < N; c = c + 1) begin
                    v = $fscanf(fh, "%d", tmp);
                    if (v != 1) begin
                        $display("ERROR: %0s/kernel.txt malformed at row %0d col %0d (fscanf returned %0d)",
                                  case_dir, r, c, v);
                        $finish;
                    end
                    kernel[r][c] = tmp[KERNEL_WIDTH-1:0];
                end
            $fclose(fh);

            fh = $fopen({case_dir, "/expected.txt"}, "r");
            if (fh == 0) begin $display("ERROR: cannot open %0s/expected.txt", case_dir); $finish; end
            for (r = 0; r < OUT_H; r = r + 1)
                for (c = 0; c < OUT_W; c = c + 1) begin
                    v = $fscanf(fh, "%d", tmp);
                    if (v != 1) begin
                        $display("ERROR: %0s/expected.txt malformed at row %0d col %0d (fscanf returned %0d)",
                                  case_dir, r, c, v);
                        $finish;
                    end
                    expected[r][c] = tmp[OUT_WIDTH-1:0];
                end
            $fclose(fh);
        end
    endtask
    integer out_r, out_c;
    integer output_count;
    
    integer case_mismatches;

    task run_case;
        
        input [8*128-1:0] case_dir;
        integer r, c, idx;
        begin
            load_case(case_dir);
            total_cases = total_cases + 1;
            

            // Reset for a clean frame.
            rst = 1; start = 0; pixel_valid = 0; kernel_valid = 0;
            @(posedge clk); @(posedge clk);
            rst = 0;
            @(posedge clk);
            case_mismatches = 0;
            out_r = 0; out_c = 0;
            output_count = 0;
            // Load kernel (row-major, matches window/kernel ordering).
            for (r = 0; r < N; r = r + 1)
                for (c = 0; c < N; c = c + 1) begin
                    idx = r*N + c;
                    // Drive setup signals away from the sampling edge.
                    @(negedge clk);
                    kernel_valid = 1; kernel_addr = idx; kernel_in = kernel[r][c];
                end
            @(negedge clk);
            kernel_valid = 0;

            // Start the frame.
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // Stream pixels, respecting pixel_ready.
            r = 0; c = 0;
            while (r < IMAGE_HEIGHT) begin
                @(negedge clk);
                pixel_valid = 1;
                pixel_in    = image[r][c];
                // Ready/valid is sampled on the rising edge. Capture ready
                // on the preceding falling edge so a state transition or
                // FIFO update cannot make the testbench advance without an
                // accepted pixel.
                if (pixel_ready) begin
                    if (c == IMAGE_WIDTH-1) begin c = 0; r = r + 1; end
                    else c = c + 1;
                end
            end
            // Keep the final pixel valid through its accepting rising edge.
            @(posedge clk);
            pixel_valid = 0;

            // Drain remaining outputs until done or a generous timeout.
            begin : drain_wait
                integer timeout;
                timeout = 0;
                while (output_count < OUT_H*OUT_W && timeout < 10000) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
                if (output_count < OUT_H*OUT_W)
                    $display("[%0s] TIMEOUT: only %0d/%0d outputs received",
                              case_dir, output_count, OUT_H*OUT_W);
                if (output_count != OUT_H*OUT_W)
                    case_mismatches = case_mismatches + 1;
            end

            if (out_r != OUT_H || out_c != 0)
                $display("[%0s] FAIL: got %0d full output rows (expected %0d) + %0d extra",
                          case_dir, out_r, OUT_H, out_c);
            if (out_r != OUT_H || out_c != 0)
                case_mismatches = case_mismatches + 1;

            total_mismatches = total_mismatches + case_mismatches;
            $display("[%0s] mismatches=%0d", case_dir, case_mismatches);

            @(posedge clk);
        end
    endtask

    // Output checker: runs concurrently, compares every accepted output
    // pixel against expected[][] in raster order, flags extras/missing.
    always @(posedge clk) begin
        if (output_valid && output_ready) begin
            output_count = output_count + 1;
            if (out_r < OUT_H) begin
                if (pixel_out !== expected[out_r][out_c])
                    begin
                        $display("  MISMATCH at (%0d,%0d): got=%0d expected=%0d",
                                  out_r, out_c, pixel_out, expected[out_r][out_c]);
                        case_mismatches = case_mismatches + 1;
                    end
                if (out_c == OUT_W-1) begin out_c = 0; out_r = out_r + 1; end
                else out_c = out_c + 1;
            end else begin
                $display("  EXTRA output pixel beyond expected %0dx%0d frame", OUT_H, OUT_W);
                case_mismatches = case_mismatches + 1;
            end
        end
    end

    initial begin
        run_case("test_vectors/zero");
        run_case("test_vectors/constant_negative");
        run_case("test_vectors/constant_positive");
        run_case("test_vectors/positive_kernel");
        run_case("test_vectors/negative_kernel");
        run_case("test_vectors/mixed_sign_kernel");
        run_case("test_vectors/random");
        run_case("test_vectors/maximum_pixels");
        run_case("test_vectors/maximum_positive_kernel");
        run_case("test_vectors/maximum_negative_kernel");
        run_case("test_vectors/saturation_positive");
        run_case("test_vectors/saturation_negative");
        run_case("test_vectors/checkerboard");
        run_case("test_vectors/sobel_x");
        run_case("test_vectors/signed_edge_values");

        $display("=================================================");
        if (total_mismatches == 0)
            $display("ALL %0d CASES PASSED (0 mismatches)", total_cases);
        else
            $display("FAIL: %0d mismatches across %0d cases", total_mismatches, total_cases);
        $display("=================================================");

        if (total_mismatches != 0) $stop;
        $finish;
    end
endmodule