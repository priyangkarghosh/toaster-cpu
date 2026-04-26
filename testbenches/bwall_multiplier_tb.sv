`timescale 1ns/1ps
module bwall_multiplier_tb;
    logic        clk, reset;
    logic        signed_in;
    logic        valid_in;
    logic [31:0] x, y;
    logic [63:0] p;
    logic        valid_out;
    bwall_multiplier dut (
        .clk       (clk),
        .reset     (reset),
        .signed_in (signed_in),
        .valid_in  (valid_in),
        .x         (x),
        .y         (y),
        .p         (p),
        .valid_out (valid_out)
    );
    initial clk = 0;
    always #5 clk = ~clk;
    localparam PIPE_DEPTH = 3;
    initial begin
        reset = 1; valid_in = 0; x = 0; y = 0; signed_in = 0;
        repeat (4) @(posedge clk);
        reset = 0;

        // Test 1: unsigned 321 * 5125 = 1,645,125
        @(negedge clk);
        x = 32'd321; y = 32'd5125; signed_in = 0; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'd1645125)
            $display("PASS: 321 * 5125 = %0d", p);
        else
            $display("FAIL: 321 * 5125 expected 1645125, got %0d", p);

        // Test 2: signed -9563 * -9563984 = 91,467,348,592
        @(negedge clk);
        x = -32'd9563; y = -32'd9563984; signed_in = 1; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'd91467348592)
            $display("PASS: -9563 * -9563984 = %0d", p);
        else
            $display("FAIL: -9563 * -9563984 expected 91467348592, got %0d", p);

        // Test 3: unsigned max * 1 = 4,294,967,295
        @(negedge clk);
        x = 32'hFFFF_FFFF; y = 32'd1; signed_in = 0; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'hFFFF_FFFF)
            $display("PASS: 0xFFFFFFFF * 1 = %0d", p);
        else
            $display("FAIL: 0xFFFFFFFF * 1 expected 4294967295, got %0d", p);

        // Test 4: signed 100 * -1 = -100
        @(negedge clk);
        x = 32'd100; y = 32'hFFFF_FFFF; signed_in = 1; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'hFFFF_FFFF_FFFF_FF9C)
            $display("PASS: 100 * -1 = %0d", $signed(p));
        else
            $display("FAIL: 100 * -1 expected -100, got %0d", $signed(p));

        // Test 5: signed 0 * anything = 0
        @(negedge clk);
        x = 32'd0; y = 32'hDEADBEEF; signed_in = 1; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'd0)
            $display("PASS: 0 * 0xDEADBEEF = 0");
        else
            $display("FAIL: 0 * 0xDEADBEEF expected 0, got %0d", p);

        // Test 6: signed max positive * max positive = 2^62 - 2^31 + 1
        @(negedge clk);
        x = 32'h7FFF_FFFF; y = 32'h7FFF_FFFF; signed_in = 1; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'd4611686016279904257)
            $display("PASS: 0x7FFFFFFF * 0x7FFFFFFF = %0d", p);
        else
            $display("FAIL: 0x7FFFFFFF * 0x7FFFFFFF expected 4611686016279904257, got %0d", p);

        // Test 7: signed most-negative * most-negative = 2^62
        @(negedge clk);
        x = 32'h8000_0000; y = 32'h8000_0000; signed_in = 1; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'h4000_0000_0000_0000)
            $display("PASS: 0x80000000 * 0x80000000 = %0d", p);
        else
            $display("FAIL: 0x80000000 * 0x80000000 expected 4611686018427387904, got %0d", p);

        // Test 8: signed most-negative * 1 = most-negative (sign extension check)
        @(negedge clk);
        x = 32'h8000_0000; y = 32'd1; signed_in = 1; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'hFFFF_FFFF_8000_0000)
            $display("PASS: -2147483648 * 1 = %0d", $signed(p));
        else
            $display("FAIL: -2147483648 * 1 expected -2147483648, got %0d", $signed(p));

        // Test 9: unsigned max * max
        @(negedge clk);
        x = 32'hFFFF_FFFF; y = 32'hFFFF_FFFF; signed_in = 0; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'hFFFFFFFE_00000001)
            $display("PASS: 0xFFFFFFFF * 0xFFFFFFFF = %0d", p);
        else
            $display("FAIL: 0xFFFFFFFF * 0xFFFFFFFF expected 18446744069414584321, got %0d", p);

        // Test 10: signed 1 * 1 = 1
        @(negedge clk);
        x = 32'd1; y = 32'd1; signed_in = 1; valid_in = 1;
        @(negedge clk); valid_in = 0;
        repeat (PIPE_DEPTH) @(posedge clk);
        @(posedge clk); #1;
        if (p === 64'd1)
            $display("PASS: 1 * 1 = 1");
        else
            $display("FAIL: 1 * 1 expected 1, got %0d", p);

        $finish;
    end
endmodule