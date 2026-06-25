`timescale 1ns/1ps
import riscv_pkg::*;

module datapath_tb;

    logic clk = 0;
    logic reset;
    always #5 clk = ~clk;

    logic [31:0] i_addr, i_data;
    logic        d_write;
    logic [31:0] d_addr, d_rdata, d_wdata;
    mem_width_t  d_width;

    datapath dut (
        .clk    (clk),
        .reset  (reset),
        .i_addr (i_addr),
        .i_data (i_data),
        .d_write(d_write),
        .d_addr (d_addr),
        .d_rdata(d_rdata),
        .d_wdata(d_wdata),
        .d_width(d_width),
        .irq_msi(1'b0),
        .irq_mti(1'b0),
        .irq_mei(1'b0)
    );

    memory #(
        .MEM_FILE("test.txt"),
        .CAPACITY(512)
    ) u_mem (
        .clk   (clk),
        .i_addr(i_addr),
        .i_data(i_data),
        .d_write(d_write),
        .d_width(d_width),
        .d_addr (d_addr),
        .d_wdata(d_wdata),
        .d_rdata(d_rdata)
    );

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task dump;
        for (int i = 0; i < 32; i++)
            $display("r%-2d = 0x%08h = %0d",
                i, dut.u_rf.regs[i], $signed(dut.u_rf.regs[i]));
        $display("==========");
    endtask

    task dump_mem(input [31:0] addr, input int count);
        for (int i = 0; i < count; i++)
            $display("mem[0x%08h] = 0x%08h = %d",
                addr + i*4,
                u_mem.mem[(addr >> 2) + i],
                $signed(u_mem.mem[(addr >> 2) + i]));
    endtask

    // ----------------------------------------------------------------
    // Per-cycle trace (suppressed during reset)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        #1;
        if (!reset) begin
            dump();
            $display("pc=%0d  alu_op=%b  x=%0d  y=%0d  z=%0d",
                dut.u_exec.id_ex.pc,
                dut.u_exec.id_ex.alu_op,
                dut.u_exec.alu_x,
                dut.u_exec.alu_y,
                dut.u_exec.alu_out);
            if (d_write)
                $display("[STORE] addr=0x%08h  data=0x%08h  width=%0d",
                    d_addr, d_wdata, d_width);
        end
    end

    // ----------------------------------------------------------------
    // EBREAK termination
    // Detect ebreak in EX and let the full trap commit (mepc/mcause/
    // mtval/mstatus all latch on the next posedge), then drain so the
    // last in-flight insn retires through WB. mtvec=0 here would
    // otherwise restart the program; 3 cycles is short enough that any
    // re-fetched-from-mtvec insns are still in IF/ID when we $finish.
    // ----------------------------------------------------------------
    localparam logic [31:0] EBREAK = 32'h00100073;

    always @(posedge clk) begin
        if (!reset && dut.u_exec.id_ex.ir == EBREAK) begin
            repeat(3) @(posedge clk);
            #1;
            $display("=== FINAL REGISTER STATE ===");
            dump();
            $display("=== MEMORY DUMP @ 0x400 ===");
            dump_mem(32'h400, 100);
            $finish;
        end
    end

    // ----------------------------------------------------------------
    // Reset
    // ----------------------------------------------------------------
    initial begin
        reset = 1;
        repeat(2) @(posedge clk);
        reset = 0;
    end

endmodule
