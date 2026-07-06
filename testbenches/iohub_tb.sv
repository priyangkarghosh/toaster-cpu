`timescale 1ns/1ps
import tbus_pkg::*;

// iohub_tb — unit test for the io hub completer: clint registers + irq
// lines, err acks for unknown offsets/windows.
module iohub_tb;

    logic clk = 0, reset;
    always #5 clk = ~clk;

    req_t c_req;
    rsp_t c_rsp;
    logic irq_msi, irq_mti;

    iohub dut (
        .clk     (clk),
        .reset   (reset),
        .c_req   (c_req),
        .c_rsp   (c_rsp),
        .irq_msi (irq_msi),
        .irq_mti (irq_mti)
    );

    // register addresses as the core sees them
    localparam [31:0] MSIP      = 32'h1000_0000;
    localparam [31:0] MTIMECMP  = 32'h1000_4000;
    localparam [31:0] MTIMECMPH = 32'h1000_4004;
    localparam [31:0] MTIME     = 32'h1000_BFF8;
    localparam [31:0] MTIMEH    = 32'h1000_BFFC;

    int pass_count = 0, fail_count = 0;

    task automatic check(input logic cond, input string name);
        if (cond) begin pass_count++; $display("PASS  %s", name); end
        else      begin fail_count++; $display("FAIL  %s", name); end
    endtask

    // one bus transaction. samples on negedge so registered acks are stable
    logic [31:0] rd;
    logic err;
    task automatic bus_op(input logic write, input [31:0] addr, input [31:0] wdata);
        c_req.valid = 1;
        c_req.write = write;
        c_req.addr  = addr;
        c_req.wdata = wdata;
        c_req.be    = 4'hF;
        do @(negedge clk); while (!c_rsp.ack);
        rd  = c_rsp.rdata;
        err = c_rsp.err;
        c_req = '0;
        @(negedge clk);
    endtask

    logic [31:0] t0;

    initial begin
        $display("=========================================");
        $display("  iohub unit testbench");
        $display("=========================================");
        reset = 1; c_req = '0;
        repeat (2) @(negedge clk);
        reset = 0;

        // clint: mtime free-runs
        bus_op(0, MTIME, 0); t0 = rd;
        bus_op(0, MTIME, 0);
        check(!err && rd > t0, "mtime ticks");

        // clint: mti level = (mtime >= mtimecmp)
        check(!irq_mti, "mti idle after reset");
        bus_op(1, MTIMECMPH, 0);
        bus_op(1, MTIMECMP, 32'd1);          // mtime is already well past 1
        @(negedge clk);
        check(irq_mti, "mti fires past cmp");
        bus_op(0, MTIMECMP, 0);
        check(rd == 32'd1, "mtimecmp readback");
        bus_op(1, MTIMECMPH, 32'hFFFF_FFFF); // far future again
        @(negedge clk);
        check(!irq_mti, "mti clears on cmp bump");

        // clint: msip bit0 drives msi
        bus_op(1, MSIP, 32'h0000_0001);
        check(irq_msi, "msi fires on msip=1");
        bus_op(0, MSIP, 0);
        check(rd == 32'd1, "msip readback");
        bus_op(1, MSIP, 0);
        check(!irq_msi, "msi clears on msip=0");

        // err paths: unknown clint offset, unmatched window, then clean again
        bus_op(0, 32'h1000_8000, 0);
        check(err, "unknown clint offset errs");
        bus_op(0, 32'h1001_0000, 0);
        check(err, "unmatched window errs");
        bus_op(0, MTIME, 0);
        check(!err, "known offset clean after err");

        $display("================================");
        $display("  PASSED %0d  FAILED %0d", pass_count, fail_count);
        if (fail_count == 0) $display("  ALL TESTS PASSED");
        else                 $display("  *** FAILURES DETECTED ***");
        $display("================================");
        $finish;
    end
endmodule
