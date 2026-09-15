`timescale 1ns/1ps

module multiplier_tb;

    parameter DATA_WIDTH    = 8;
    parameter KERNEL_WIDTH  = 8;
    parameter PRODUCT_WIDTH = 16;

    reg [DATA_WIDTH-1:0] pixel_in;
    reg signed [KERNEL_WIDTH-1:0] kernel_in;

    // Product is 16-bit signed for the 8x8 multiplier.
    wire signed [PRODUCT_WIDTH-1:0] product_out;

    integer expected;
    integer errors;
    integer i;

    // These are used for the golden calculation.
    // Keeping both operands as integers avoids Verilog's
    // signed/unsigned expression rules.
    integer pixel_value;
    integer kernel_value;

    multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .KERNEL_WIDTH(KERNEL_WIDTH),
        .PRODUCT_WIDTH(PRODUCT_WIDTH)
    ) dut (
        .pixel_in(pixel_in),
        .kernel_in(kernel_in),
        .product_out(product_out)
    );

    // ------------------------------------------------------------
    // Check one multiplication
    // ------------------------------------------------------------
    task check;
        input [DATA_WIDTH-1:0] pixel;
        input integer kernel;

        begin
            pixel_in  = pixel;
            kernel_in = kernel;

            #1;

            // IMPORTANT:
            // Do NOT calculate:
            //     expected = pixel * $signed(kernel_in);
            //
            // because pixel is unsigned and this can cause the
            // expression to be treated as unsigned.
            //
            // Convert both values to normal signed integers first.
            pixel_value  = pixel;
            kernel_value = kernel;

            expected = pixel_value * kernel_value;

            if ($signed(product_out) !== expected) begin
                $display(
                    "FAIL: pixel=%0d kernel=%0d expected=%0d got=%0d",
                    pixel_value,
                    kernel_value,
                    expected,
                    $signed(product_out)
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS: pixel=%0d kernel=%0d product=%0d",
                    pixel_value,
                    kernel_value,
                    $signed(product_out)
                );
            end
        end
    endtask


    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin

        errors = 0;

        $display("==========================================");
        $display("MULTIPLIER TESTBENCH");
        $display("==========================================");


        // --------------------------------------------------------
        // TEST 1: Zero cases
        // --------------------------------------------------------

        $display("\nTEST 1: ZERO CASES");

        check(0, 0);
        check(0, 1);
        check(0, -1);
        check(0, 127);
        check(0, -128);

        check(1, 0);
        check(100, 0);
        check(255, 0);


        // --------------------------------------------------------
        // TEST 2: Positive multiplication
        // --------------------------------------------------------

        $display("\nTEST 2: POSITIVE PRODUCTS");

        check(1, 1);
        check(2, 3);
        check(10, 5);
        check(25, 4);
        check(100, 2);
        check(128, 2);
        check(200, 10);
        check(255, 127);


        // --------------------------------------------------------
        // TEST 3: Negative multiplication
        // --------------------------------------------------------

        $display("\nTEST 3: NEGATIVE PRODUCTS");

        check(1, -1);
        check(2, -3);
        check(10, -5);
        check(25, -4);
        check(100, -2);
        check(128, -2);
        check(200, -10);
        check(255, -127);


        // --------------------------------------------------------
        // TEST 4: Kernel edge values
        // --------------------------------------------------------

        $display("\nTEST 4: KERNEL EDGE VALUES");

        check(1, -128);
        check(1, 127);

        check(128, -128);
        check(128, 127);

        check(254, -128);
        check(254, 127);

        check(255, -128);
        check(255, 127);


        // --------------------------------------------------------
        // TEST 5: Pixel edge values
        // --------------------------------------------------------

        $display("\nTEST 5: PIXEL EDGE VALUES");

        check(0, -128);
        check(0, 127);

        check(1, -128);
        check(1, 127);

        check(254, -128);
        check(254, 127);

        check(255, -128);
        check(255, 127);


        // --------------------------------------------------------
        // TEST 6: CNN-LIKE VALUES
        // --------------------------------------------------------

        $display("\nTEST 6: CNN-LIKE VALUES");

        check(255, 1);
        check(255, -1);

        check(128, 1);
        check(128, -1);

        check(127, 1);
        check(127, -1);

        check(64, 8);
        check(64, -8);

        check(128, 16);
        check(128, -16);

        check(255, 64);
        check(255, -64);


        // --------------------------------------------------------
        // TEST 7: Exhaustive kernel test
        //
        // Every signed 8-bit kernel value:
        //     -128 through +127
        //
        // is tested with several pixel values.
        // --------------------------------------------------------

        $display("\nTEST 7: EXHAUSTIVE KERNEL TEST");

        for (i = -128; i <= 127; i = i + 1) begin

            check(0,   i);
            check(1,   i);
            check(127, i);
            check(128, i);
            check(254, i);
            check(255, i);

        end


        // --------------------------------------------------------
        // TEST 8: Exhaustive pixel test
        //
        // Every unsigned 8-bit pixel:
        //     0 through 255
        //
        // is tested with representative signed kernels.
        // --------------------------------------------------------

        $display("\nTEST 8: EXHAUSTIVE PIXEL TEST");

        for (i = 0; i <= 255; i = i + 1) begin

            check(i, -128);
            check(i, -64);
            check(i, -16);
            check(i, -1);
            check(i, 0);
            check(i, 1);
            check(i, 16);
            check(i, 64);
            check(i, 127);

        end


        // --------------------------------------------------------
        // TEST 9: Random testing
        //
        // IMPORTANT:
        // $random is a signed 32-bit value. Do not directly use
        // it as the golden-model calculation.
        //
        // Generate the desired ranges explicitly:
        //
        // pixel  : 0 .. 255
        // kernel : -128 .. 127
        // --------------------------------------------------------

        $display("\nTEST 9: RANDOM TESTING");

        for (i = 0; i < 1000; i = i + 1) begin

            pixel_value  = $urandom_range(0, 255);
            kernel_value = $urandom_range(0, 255) - 128;

            pixel_in  = pixel_value;
            kernel_in = kernel_value;

            #1;

            // Both operands are integers here, so the calculation
            // is unquestionably signed.
            expected = pixel_value * kernel_value;

            if ($signed(product_out) !== expected) begin

                $display(
                    "FAIL RANDOM: pixel=%0d kernel=%0d expected=%0d got=%0d",
                    pixel_value,
                    kernel_value,
                    expected,
                    $signed(product_out)
                );

                errors = errors + 1;

            end

        end


        // --------------------------------------------------------
        // Final result
        // --------------------------------------------------------

        $display("\n==========================================");

        if (errors == 0) begin
            $display("ALL TESTS PASSED");
        end
        else begin
            $display("TEST FAILED: %0d errors", errors);
        end

        $display("==========================================");

        $finish;

    end


    // ------------------------------------------------------------
    // Waveform
    // ------------------------------------------------------------

    initial begin
        $dumpfile("multiplier_tb.vcd");
        $dumpvars(0, multiplier_tb);
    end

endmodule
