`timescale 1ns/1ps

module adder_tree_tb;

    parameter N             = 3;
    parameter PRODUCT_WIDTH = 16;
    parameter ACC_WIDTH     = 20;

    // DUT signals
    reg signed [N*N*PRODUCT_WIDTH-1:0] products_in;
    reg                                products_valid;

    wire signed [ACC_WIDTH-1:0] sum_out;
    wire                         sum_valid;

    // Instantiate DUT
    adder_tree #(
        .N(N),
        .PRODUCT_WIDTH(PRODUCT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .products_in(products_in),
        .products_valid(products_valid),
        .sum_out(sum_out),
        .sum_valid(sum_valid)
    );

    // ------------------------------------------------------------
    // Test variables
    // ------------------------------------------------------------

    integer i;
    integer test_count;
    integer pass_count;
    integer fail_count;

    reg signed [PRODUCT_WIDTH-1:0] test_product [0:8];

    reg signed [ACC_WIDTH-1:0] expected_sum;

    // ------------------------------------------------------------
    // Put one 16-bit product into products_in
    // ------------------------------------------------------------

    task set_product;
        input integer index;
        input signed [PRODUCT_WIDTH-1:0] value;

        begin
            products_in[index*PRODUCT_WIDTH +: PRODUCT_WIDTH] = value;
        end
    endtask

    // ------------------------------------------------------------
    // Calculate expected result and compare with DUT
    // ------------------------------------------------------------

    task check_result;

        begin

            expected_sum = 0;

            for (i = 0; i < 9; i = i + 1)
                expected_sum = expected_sum + test_product[i];

            #1;

            test_count = test_count + 1;

            if (sum_out === expected_sum) begin
                pass_count = pass_count + 1;

                $display(
                    "PASS: Test %0d | Expected = %0d | Got = %0d",
                    test_count,
                    expected_sum,
                    sum_out
                );
            end
            else begin
                fail_count = fail_count + 1;

                $display(
                    "FAIL: Test %0d | Expected = %0d | Got = %0d",
                    test_count,
                    expected_sum,
                    sum_out
                );

                $display("Inputs:");

                for (i = 0; i < 9; i = i + 1)
                    $display(
                        "  p[%0d] = %0d",
                        i,
                        test_product[i]
                    );
            end

        end

    endtask

    // ------------------------------------------------------------
    // Apply nine products
    // ------------------------------------------------------------

    task apply_products;

        input signed [PRODUCT_WIDTH-1:0] p0;
        input signed [PRODUCT_WIDTH-1:0] p1;
        input signed [PRODUCT_WIDTH-1:0] p2;
        input signed [PRODUCT_WIDTH-1:0] p3;
        input signed [PRODUCT_WIDTH-1:0] p4;
        input signed [PRODUCT_WIDTH-1:0] p5;
        input signed [PRODUCT_WIDTH-1:0] p6;
        input signed [PRODUCT_WIDTH-1:0] p7;
        input signed [PRODUCT_WIDTH-1:0] p8;

        begin

            test_product[0] = p0;
            test_product[1] = p1;
            test_product[2] = p2;
            test_product[3] = p3;
            test_product[4] = p4;
            test_product[5] = p5;
            test_product[6] = p6;
            test_product[7] = p7;
            test_product[8] = p8;

            set_product(0, p0);
            set_product(1, p1);
            set_product(2, p2);
            set_product(3, p3);
            set_product(4, p4);
            set_product(5, p5);
            set_product(6, p6);
            set_product(7, p7);
            set_product(8, p8);

            #1;

            check_result;

        end

    endtask

    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------

    initial begin

        // Waveform
        $dumpfile("adder_tree_tb.vcd");
        $dumpvars(0, adder_tree_tb);

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        products_in   = 0;
        products_valid = 0;

        // ========================================================
        // TEST 1: All zeros
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 1: ALL ZEROS");
        $display("==========================================");

        apply_products(
            0, 0, 0,
            0, 0, 0,
            0, 0, 0
        );


        // ========================================================
        // TEST 2: One non-zero input
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 2: ONE NON-ZERO INPUT");
        $display("==========================================");

        apply_products(
            10, 0, 0,
            0, 0, 0,
            0, 0, 0
        );


        // ========================================================
        // TEST 3: Non-zero last input
        // Tests p[8] carried forward
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 3: ONLY p[8] NON-ZERO");
        $display("==========================================");

        apply_products(
            0, 0, 0,
            0, 0, 0,
            0, 0, 123
        );


        // ========================================================
        // TEST 4: All positive
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 4: ALL POSITIVE");
        $display("==========================================");

        apply_products(
            1, 2, 3,
            4, 5, 6,
            7, 8, 9
        );


        // ========================================================
        // TEST 5: All negative
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 5: ALL NEGATIVE");
        $display("==========================================");

        apply_products(
            -1, -2, -3,
            -4, -5, -6,
            -7, -8, -9
        );


        // ========================================================
        // TEST 6: Mixed signs
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 6: MIXED SIGNS");
        $display("==========================================");

        apply_products(
            10, -20, 30,
            -40, 50, -60,
            70, -80, 90
        );


        // ========================================================
        // TEST 7: Alternating signs
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 7: ALTERNATING SIGNS");
        $display("==========================================");

        apply_products(
            100, -100, 100,
            -100, 100, -100,
            100, -100, 100
        );


        // ========================================================
        // TEST 8: Equal positive values
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 8: ALL +1000");
        $display("==========================================");

        apply_products(
            1000, 1000, 1000,
            1000, 1000, 1000,
            1000, 1000, 1000
        );


        // ========================================================
        // TEST 9: Equal negative values
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 9: ALL -1000");
        $display("==========================================");

        apply_products(
            -1000, -1000, -1000,
            -1000, -1000, -1000,
            -1000, -1000, -1000
        );


        // ========================================================
        // TEST 10: Maximum positive 16-bit value
        // 32767 * 9 = 294903
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 10: MAX POSITIVE PRODUCT");
        $display("==========================================");

        apply_products(
            32767, 32767, 32767,
            32767, 32767, 32767,
            32767, 32767, 32767
        );


        // ========================================================
        // TEST 11: Maximum negative 16-bit value
        // -32768 * 9 = -294912
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 11: MAX NEGATIVE PRODUCT");
        $display("==========================================");

        apply_products(
            -32768, -32768, -32768,
            -32768, -32768, -32768,
            -32768, -32768, -32768
        );


        // ========================================================
        // TEST 12: Maximum positive and negative mixed
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 12: EXTREME MIXED VALUES");
        $display("==========================================");

        apply_products(
            32767, -32768, 32767,
            -32768, 32767, -32768,
            32767, -32768, 32767
        );


        // ========================================================
        // TEST 13: Positive values near accumulator boundary
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 13: LARGE POSITIVE SUM");
        $display("==========================================");

        apply_products(
            30000, 30000, 30000,
            30000, 30000, 30000,
            30000, 30000, 30000
        );


        // ========================================================
        // TEST 14: Large negative sum
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 14: LARGE NEGATIVE SUM");
        $display("==========================================");

        apply_products(
            -30000, -30000, -30000,
            -30000, -30000, -30000,
            -30000, -30000, -30000
        );


        // ========================================================
        // TEST 15: Cancellation
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 15: COMPLETE CANCELLATION");
        $display("==========================================");

        apply_products(
            1000, -1000, 2000,
            -2000, 3000, -3000,
            4000, -4000, 0
        );


        // ========================================================
        // TEST 16: Only first pair
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 16: FIRST ADDER");
        $display("==========================================");

        apply_products(
            123, 456, 0,
            0, 0, 0,
            0, 0, 0
        );


        // ========================================================
        // TEST 17: Only second pair
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 17: SECOND ADDER");
        $display("==========================================");

        apply_products(
            0, 0, 123,
            456, 0, 0,
            0, 0, 0
        );


        // ========================================================
        // TEST 18: Only third pair
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 18: THIRD ADDER");
        $display("==========================================");

        apply_products(
            0, 0, 0,
            0, 123, 456,
            0, 0, 0
        );


        // ========================================================
        // TEST 19: Only fourth pair
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 19: FOURTH ADDER");
        $display("==========================================");

        apply_products(
            0, 0, 0,
            0, 0, 0,
            123, 456, 0
        );


        // ========================================================
        // TEST 20: p[8] + previous tree
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 20: p[8] COMBINATION");
        $display("==========================================");

        apply_products(
            100, 100, 100,
            100, 100, 100,
            100, 100, 1000
        );


        // ========================================================
        // TEST 21-30: Random tests
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TESTS 21-30: RANDOM VALUES");
        $display("==========================================");

        for (i = 0; i < 10; i = i + 1) begin

            apply_products(
                $random,
                $random,
                $random,
                $random,
                $random,
                $random,
                $random,
                $random,
                $random
            );

        end


        // ========================================================
        // VALID SIGNAL TEST
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 31: VALID SIGNAL");
        $display("==========================================");

        products_valid = 0;

        #1;

        if (sum_valid === 1'b0) begin
            $display("PASS: sum_valid correctly follows products_valid = 0");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: sum_valid should be 0");
            fail_count = fail_count + 1;
        end

        test_count = test_count + 1;


        products_valid = 1;

        #1;

        if (sum_valid === 1'b1) begin
            $display("PASS: sum_valid correctly follows products_valid = 1");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: sum_valid should be 1");
            fail_count = fail_count + 1;
        end

        test_count = test_count + 1;


        // ========================================================
        // Final report
        // ========================================================

        #5;

        $display("");
        $display("==========================================");
        $display("           TESTBENCH COMPLETE");
        $display("==========================================");
        $display("Total tests : %0d", test_count);
        $display("Passed      : %0d", pass_count);
        $display("Failed      : %0d", fail_count);
        $display("==========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $display("==========================================");

        $finish;

    end

endmodule