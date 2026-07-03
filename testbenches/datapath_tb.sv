`timescale 1ns/1ps
import riscv_pkg::*;

module datapath_tb;

    logic clk = 0;
    logic reset;
    always #5 clk = ~clk;

    toaster_cpu #(
        .MEM_FILE("test.txt"),
        .CAPACITY(512)
    ) dut (
        .clk  (clk),
        .reset(reset)
    );

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task dump;
        for (int i = 0; i < 32; i++)
            $display("r%-2d = 0x%08h = %0d",
                i, dut.u_core.u_rf.regs[i], $signed(dut.u_core.u_rf.regs[i]));
        $display("==========");
    endtask

    task dump_mem(input [31:0] addr, input int count);
        for (int i = 0; i < count; i++)
            $display("mem[0x%08h] = 0x%08h = %d",
                addr + i*4,
                dut.u_mem.mem[(addr >> 2) + i],
                $signed(dut.u_mem.mem[(addr >> 2) + i]));
    endtask

    // ----------------------------------------------------------------
    // Per-cycle trace (suppressed during reset)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        #1;
        if (!reset) begin
            dump();
            $display("pc=%0d  alu_op=%b  x=%0d  y=%0d  z=%0d",
                dut.u_core.u_exec.id_ex.pc,
                dut.u_core.u_exec.id_ex.alu_op,
                dut.u_core.u_exec.alu_x,
                dut.u_core.u_exec.alu_y,
                dut.u_core.u_exec.alu_out);
            if (dut.u_core.m_req.valid & dut.u_core.m_req.write)
                $display("[STORE] addr=0x%08h  data=0x%08h  be=%b",
                    dut.u_core.m_req.addr,
                    dut.u_core.m_req.wdata,
                    dut.u_core.m_req.be);
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
        if (!reset && dut.u_core.u_exec.id_ex.ir == EBREAK) begin
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
