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
        .clk(clk), .reset(reset),
        .i_addr(i_addr), .i_data(i_data),
        .d_write(d_write), .d_addr(d_addr),
        .d_rdata(d_rdata), .d_wdata(d_wdata),
        .d_width(d_width)
    );

    memory #(
        .MEM_FILE("test.txt"),
        .CAPACITY(512)
    ) u_mem (
        .clk(clk),
        .i_addr(i_addr), .i_data(i_data),
        .d_write(d_write), .d_width(d_width),
        .d_addr(d_addr), .d_wdata(d_wdata),
        .d_rdata(d_rdata)
    );

    task dump;
        for (int i = 0; i < 32; i++)
            $display("r%-2d = 0x%08h = %0d", i, dut.u_rf.regs[i], $signed(dut.u_rf.regs[i]));
        $display("==========");
    endtask

    task dump_mem(input [31:0] addr, input int count);
        for (int i = 0; i < count; i++)
            $display("mem[0x%08h] = 0x%08h = %d", addr + i*4, u_mem.mem[(addr >> 2) + i], $signed(u_mem.mem[(addr >> 2) + i]));
    endtask

    always @(posedge clk) begin
        #1;
        dump();
        $display("pc=%0d, alu_op=%b A=%0d B=%0d Z=%0d", dut.u_exec.id_ex.pc, dut.u_exec.id_ex.alu_op, dut.u_exec.alu_a, dut.u_exec.alu_b, dut.u_exec.alu_out);
        if (d_write) $display("[STORE] addr=0x%08h data=0x%08h width=%0d", d_addr, d_wdata, d_width);
    end

    always @(posedge clk) begin
        if (i_data == 32'h00100073) begin
            repeat(6) @(posedge clk);
            #1;
            dump();
            dump_mem(32'h400, 100);
            $finish;
        end
    end

    initial begin
        reset = 1;
        repeat(2) @(posedge clk);
        reset = 0;
    end
endmodule
