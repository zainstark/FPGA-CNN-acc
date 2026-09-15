`timescale 1ns/1ps

module line_buffer_tb;

    // ============================================================
    // Parameters
    // ============================================================

    parameter N           = 3;
    parameter DATA_WIDTH  = 8;
    parameter IMAGE_WIDTH = 8;

    // ============================================================
    // DUT signals
    // ============================================================

    reg clk;
    reg rst;

    reg [DATA_WIDTH-1:0] pixel_in;
    reg                  pixel_valid;

    wire pixel_ready;

    wire [N*DATA_WIDTH-1:0] column_pixels;
    wire                    column_valid;

    wire [$clog2(IMAGE_WIDTH)-1:0] column;
    wire [$clog2(IMAGE_WIDTH)-1:0] row;


    // ============================================================
    // Instantiate DUT
    // ============================================================

    line_buffer #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .pixel_in      (pixel_in),
        .pixel_valid   (pixel_valid),
        .pixel_ready   (pixel_ready),

        .column_pixels (column_pixels),
        .column_valid  (column_valid),
        .column        (column),
        .row           (row)
    );


    // ============================================================
    // Clock
    // ============================================================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end


    // ============================================================
    // Waveform
    // ============================================================

    initial begin
        $dumpfile("line_buffer_tb.vcd");
        $dumpvars(0, line_buffer_tb);
    end


    // ============================================================
    // Test image
    //
    // Pixel value = row * 16 + column
    //
    // 8x8 image:
    //
    // 00 01 02 03 04 05 06 07
    // 10 11 12 13 14 15 16 17
    // 20 21 22 23 24 25 26 27
    // 30 31 32 33 34 35 36 37
    // 40 41 42 43 44 45 46 47
    // 50 51 52 53 54 55 56 57
    // 60 61 62 63 64 65 66 67
    // 70 71 72 73 74 75 76 77
    //
    // This makes errors very easy to recognize.
    // ============================================================

    function [DATA_WIDTH-1:0] test_pixel;

        input integer r;
        input integer c;

        begin
            test_pixel = r * 16 + c;
        end

    endfunction


    // ============================================================
    // Send one pixel and check the result
    // ============================================================

    task send_pixel;

        input integer test_row;
        input integer test_col;

        reg [DATA_WIDTH-1:0] oldest_pixel;
        reg [DATA_WIDTH-1:0] previous_pixel;
        reg [DATA_WIDTH-1:0] current_pixel;

        reg [N*DATA_WIDTH-1:0] expected_column;

        begin

            // ----------------------------------------------------
            // Drive the input on the falling edge.
            // ----------------------------------------------------

            @(negedge clk);

            pixel_in    = test_pixel(test_row, test_col);
            pixel_valid = 1'b1;


            // ----------------------------------------------------
            // DUT processes the pixel on the next rising edge.
            // ----------------------------------------------------

            @(negedge clk);


            // ----------------------------------------------------
            // First two rows cannot produce a valid 3-row column.
            // ----------------------------------------------------

            if (test_row < N-1) begin

                if (column_valid !== 1'b0) begin

                    $display("");
                    $display("ERROR: column became valid too early!");
                    $display("Expected row    = %0d", test_row);
                    $display("Expected column = %0d", test_col);
                    $display("column_valid    = %b", column_valid);

                    $stop;

                end

            end


            // ----------------------------------------------------
            // Rows >= 2 should produce valid columns.
            // ----------------------------------------------------

            else begin

                oldest_pixel   = test_pixel(test_row-2, test_col);
                previous_pixel = test_pixel(test_row-1, test_col);
                current_pixel  = test_pixel(test_row,   test_col);

                expected_column = {
                    current_pixel,
                    previous_pixel,
                    oldest_pixel
                };


                // ------------------------------------------------
                // Check valid
                // ------------------------------------------------

                if (column_valid !== 1'b1) begin

                    $display("");
                    $display("ERROR: column_valid is 0!");
                    $display("Expected row    = %0d", test_row);
                    $display("Expected column = %0d", test_col);

                    $stop;

                end


                // ------------------------------------------------
                // Check row
                // ------------------------------------------------

                if (row !== test_row) begin

                    $display("");
                    $display("ERROR: wrong row!");
                    $display("Expected = %0d", test_row);
                    $display("Got      = %0d", row);

                    $stop;

                end


                // ------------------------------------------------
                // Check column
                // ------------------------------------------------

                if (column !== test_col) begin

                    $display("");
                    $display("ERROR: wrong column!");
                    $display("Expected = %0d", test_col);
                    $display("Got      = %0d", column);

                    $stop;

                end


                // ------------------------------------------------
                // Check vertical pixels
                // ------------------------------------------------

                if (column_pixels !== expected_column) begin

                    $display("");
                    $display("ERROR: wrong column_pixels!");
                    $display("Row     = %0d", test_row);
                    $display("Column  = %0d", test_col);

                    $display("Expected = %h", expected_column);
                    $display("Got      = %h", column_pixels);

                    $stop;

                end


                $display(
                    "PASS: row=%0d col=%0d -> %h",
                    row,
                    column,
                    column_pixels
                );

            end


            // Stop driving valid.
            pixel_valid = 1'b0;

        end

    endtask


    // ============================================================
    // Send one complete row
    // ============================================================

    task send_row;

        input integer test_row;

        integer c;

        begin

            for (c = 0; c < IMAGE_WIDTH; c = c + 1) begin

                send_pixel(test_row, c);

            end

        end

    endtask


    // ============================================================
    // Main test
    // ============================================================

    integer r;


    initial begin

        // ========================================================
        // Initial conditions
        // ========================================================

        rst         = 1'b1;
        pixel_in    = 8'h00;
        pixel_valid = 1'b0;


        // ========================================================
        // TEST 1: RESET
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 1: RESET");
        $display("==========================================");

        repeat (2) @(posedge clk);

        #1;

        if (column_valid !== 1'b0) begin
            $display("ERROR: column_valid after reset");
            $stop;
        end

        if (column_pixels !== 0) begin
            $display("ERROR: column_pixels after reset");
            $stop;
        end

        if (row !== 0) begin
            $display("ERROR: row after reset");
            $stop;
        end

        if (column !== 0) begin
            $display("ERROR: column after reset");
            $stop;
        end

        if (pixel_ready !== 1'b1) begin
            $display("ERROR: pixel_ready is not 1");
            $stop;
        end

        $display("PASS: reset");


        // ========================================================
        // Release reset
        // ========================================================

        @(negedge clk);
        rst = 1'b0;


        // ========================================================
        // TEST 2: FIRST ROW
        //
        // No previous rows exist.
        // column_valid must remain 0.
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 2: FIRST ROW");
        $display("==========================================");

        send_row(0);


        // ========================================================
        // TEST 3: SECOND ROW
        //
        // Only one previous row exists.
        // Still not enough for N=3.
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 3: SECOND ROW");
        $display("==========================================");

        send_row(1);


        // ========================================================
        // TEST 4: THIRD ROW
        //
        // First valid row.
        //
        // Expected:
        //
        // col 0 -> 20 10 00
        // col 1 -> 21 11 01
        // ...
        // col 7 -> 27 17 07
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 4: FIRST VALID ROW");
        $display("==========================================");

        send_row(2);


        // ========================================================
        // TEST 5: Remaining rows
        //
        // Rows 3-7 are valid.
        //
        // This also exercises the circular buffer because:
        //
        // DEPTH = (N-1) * IMAGE_WIDTH
        //       = 2 * 8
        //       = 16
        //
        // The write pointer wraps several times during the
        // 8x8 image.
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 5: REMAINING IMAGE");
        $display("==========================================");

        for (r = 3; r < IMAGE_WIDTH; r = r + 1) begin

            send_row(r);

        end


        // ========================================================
        // TEST 6: FINAL PIXEL
        //
        // The final pixel is (7,7).
        //
        // Expected column:
        //
        // 77
        // 67
        // 57
        //
        // The previous test already checks this, but we print
        // it explicitly because it is an important boundary.
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 6: FINAL IMAGE PIXEL");
        $display("==========================================");

        $display("Final pixel was row=7 col=7");
        $display("Final column = %h", column_pixels);

        if (row !== IMAGE_WIDTH-1) begin
            $display("ERROR: final row incorrect");
            $stop;
        end

        if (column !== IMAGE_WIDTH-1) begin
            $display("ERROR: final column incorrect");
            $stop;
        end

        if (column_valid !== 1'b1) begin
            $display("ERROR: final column should be valid");
            $stop;
        end

        if (column_pixels !== 24'h776757) begin
            $display("ERROR: final column incorrect");
            $display("Expected = 776757");
            $display("Got      = %h", column_pixels);
            $stop;
        end

        $display("PASS: final image pixel");


        // ========================================================
        // TEST 7: INVALID INPUT
        //
        // pixel_valid = 0 must not advance the line buffer.
        // column_valid must become 0.
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 7: INVALID INPUT");
        $display("==========================================");

        @(negedge clk);

        pixel_in    = 8'hAA;
        pixel_valid = 1'b0;

        @(negedge clk);

        if (column_valid !== 1'b0) begin
            $display("ERROR: column_valid should be 0");
            $stop;
        end

        $display("PASS: invalid input");


        // ========================================================
        // TEST 8: RESET AFTER COMPLETE IMAGE
        //
        // Make sure a reset clears the state.
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 8: RESET AFTER IMAGE");
        $display("==========================================");

        @(negedge clk);

        rst = 1'b1;

        @(posedge clk);

        #1;

        if (row !== 0) begin
            $display("ERROR: row did not reset");
            $stop;
        end

        if (column !== 0) begin
            $display("ERROR: column did not reset");
            $stop;
        end

        if (column_valid !== 1'b0) begin
            $display("ERROR: column_valid did not reset");
            $stop;
        end

        if (column_pixels !== 0) begin
            $display("ERROR: column_pixels did not reset");
            $stop;
        end

        $display("PASS: reset after image");


        // ========================================================
        // Release reset
        // ========================================================

        @(negedge clk);

        rst = 1'b0;


        // ========================================================
        // TEST 9: NEW IMAGE AFTER RESET
        //
        // Verify that stale pixels from the previous image don't
        // accidentally produce valid data too early.
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 9: NEW IMAGE AFTER RESET");
        $display("==========================================");

        send_row(0);
        send_row(1);
        send_row(2);


        // ========================================================
        // TEST 10: pixel_ready
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TEST 10: PIXEL READY");
        $display("==========================================");

        if (pixel_ready !== 1'b1) begin
            $display("ERROR: pixel_ready is not permanently 1");
            $stop;
        end

        $display("PASS: pixel_ready");


        // ========================================================
        // DONE
        // ========================================================

        $display("");
        $display("==========================================");
        $display("ALL TESTS PASSED");
        $display("==========================================");

        #20;

        $finish;

    end

endmodule