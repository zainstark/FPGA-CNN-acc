`timescale 1ns/1ps
module tb_conv;
  reg clk = 0, rst = 1, start = 0;
  reg [7:0] pixel_in = 0;            reg pixel_valid = 0;
  reg signed [7:0] kernel_in = 0;    reg [3:0] kernel_addr = 0; reg kernel_valid = 0;
  reg output_ready = 1;
  wire pixel_ready, output_valid, busy, done;
  wire signed [15:0] pixel_out;

  conv_top dut(.clk(clk), .rst(rst), .start(start),
    .pixel_in(pixel_in), .pixel_valid(pixel_valid), .pixel_ready(pixel_ready),
    .kernel_in(kernel_in), .kernel_addr(kernel_addr), .kernel_valid(kernel_valid),
    .pixel_out(pixel_out), .output_valid(output_valid), .output_ready(output_ready),
    .busy(busy), .done(done));

  always #5 clk = ~clk;                       // 100 MHz sim clock

  reg [7:0]         img  [0:1023];
  reg signed [7:0]  ker  [0:8];
  reg signed [15:0] expd [0:899];
  reg [8*256-1:0] f_img, f_ker, f_exp;
  integer i, fd, tmp, r, seed = 32'h1234;
  integer cycle = 0, c_start = 0, c_done = 0, c_px67 = 0, c_first_out = 0, c_last_out = 0;
  integer acc_cnt = 0, out_cnt = 0, mism = 0, stab_err = 0, stall_cycles = 0, rd_err = 0;
  reg done_seen = 0, bp_en = 0, hexfmt = 0, prev_stall = 0;
  reg signed [15:0] prev_out = 0;

  // ---------------- monitor ----------------
  always @(posedge clk) begin
    if (start && c_start == 0) c_start = cycle;
    if (pixel_valid && pixel_ready) begin
      if (acc_cnt == 66) c_px67 = cycle;          // pixel (2,2) accepted
      acc_cnt = acc_cnt + 1;
    end
    if (output_valid && output_ready) begin
      if (out_cnt == 0) c_first_out = cycle;
      c_last_out = cycle;
      if (out_cnt < 900 && pixel_out !== expd[out_cnt]) begin
        mism = mism + 1;
        if (mism <= 10) $display("MISMATCH idx=%0d got=%0d exp=%0d", out_cnt, pixel_out, expd[out_cnt]);
      end
      out_cnt = out_cnt + 1;
    end
    // an output that was stalled must still be valid and unchanged next cycle
    if (prev_stall && !(output_valid && pixel_out === prev_out)) stab_err = stab_err + 1;
    prev_stall = output_valid && !output_ready;
    if (output_valid && !output_ready) stall_cycles = stall_cycles + 1;
    prev_out = pixel_out;
    if (done) begin c_done = cycle; done_seen = 1; end
    cycle = cycle + 1;
  end

  // ---------------- optional random backpressure ----------------
  always @(posedge clk) if (bp_en) output_ready <= (($random(seed) & 3) != 0);

  task print_result(input integer code);
    begin
      $write("RESULT accepted=%0d outputs=%0d mismatches=%0d stability_errors=%0d read_errors=%0d bp=%0d stall_cycles=%0d c_start=%0d c_px67=%0d c_first_out=%0d c_last_out=%0d c_done=%0d lat_pipeline=%0d lat_start_to_done=%0d lat_start_to_last_out=%0d verdict=",
        acc_cnt, out_cnt, mism, stab_err, rd_err, bp_en, stall_cycles,
        c_start, c_px67, c_first_out, c_last_out, c_done,
        (c_first_out - c_px67), (c_done - c_start), (c_last_out - c_start));
      if (code == 1) $display("PASS"); else if (code == 2) $display("TIMEOUT"); else $display("FAIL");
    end
  endtask

  initial begin
    if (!$value$plusargs("IMG=%s", f_img) || !$value$plusargs("KER=%s", f_ker) ||
        !$value$plusargs("EXP=%s", f_exp)) begin
      $display("need +IMG= +KER= +EXP="); $finish;
    end
    hexfmt = $test$plusargs("HEX");
    bp_en  = $test$plusargs("BP");

    fd = $fopen(f_img, "r"); if (fd == 0) begin $display("cannot open image"); $finish; end
    for (i = 0; i < 1024; i = i + 1) begin
      if (hexfmt) r = $fscanf(fd, "%h", tmp); else r = $fscanf(fd, "%d", tmp);
      if (r != 1) rd_err = rd_err + 1; img[i] = tmp[7:0];
    end $fclose(fd);
    fd = $fopen(f_ker, "r"); if (fd == 0) begin $display("cannot open kernel"); $finish; end
    for (i = 0; i < 9; i = i + 1) begin
      if (hexfmt) r = $fscanf(fd, "%h", tmp); else r = $fscanf(fd, "%d", tmp);
      if (r != 1) rd_err = rd_err + 1; ker[i] = tmp[7:0];
    end $fclose(fd);
    fd = $fopen(f_exp, "r"); if (fd == 0) begin $display("cannot open expected"); $finish; end
    for (i = 0; i < 900; i = i + 1) begin
      if (hexfmt) r = $fscanf(fd, "%h", tmp); else r = $fscanf(fd, "%d", tmp);
      if (r != 1) rd_err = rd_err + 1; expd[i] = tmp[15:0];
    end $fclose(fd);

    if ($test$plusargs("VCD")) begin $dumpfile("sim/conv.vcd"); $dumpvars(0, tb_conv); end

    repeat (4) @(posedge clk); #1 rst = 0;
    repeat (2) @(posedge clk); #1;
    for (i = 0; i < 9; i = i + 1) begin           // kernel load
      kernel_addr = i; kernel_in = ker[i]; kernel_valid = 1; @(posedge clk); #1;
    end
    kernel_valid = 0;
    start = 1; @(posedge clk); #1 start = 0;

    i = 0;                                        // pixel stream with valid/ready
    while (i < 1024) begin
      pixel_in = img[i]; pixel_valid = 1;
      @(posedge clk);
      if (pixel_ready) i = i + 1;
      #1;
    end
    pixel_valid = 0;

    wait (done_seen);
    i = 0; while (out_cnt < 900 && i < 20000) begin @(posedge clk); i = i + 1; end
    repeat (30) @(posedge clk);                   // catch any extra outputs

    print_result((acc_cnt == 1024 && out_cnt == 900 && mism == 0 && stab_err == 0 && rd_err == 0) ? 1 : 0);
    $finish;
  end

  initial begin #20_000_000; print_result(2); $finish; end   // watchdog
endmodule