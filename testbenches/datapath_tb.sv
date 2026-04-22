`timescale 1ns/1ps

module datapath_tb;
    // clock/reset
    logic clk = 0;
    logic reset;
    always #5 clk = ~clk; // 100MHz

    // memory connections
    logic [31:0] mem_pc;
    logic [31:0] mem_inst_in;
    logic [3:0]  mem_write;
    logic [31:0] mem_addr;
    logic [31:0] mem_data_in = '0;
    logic [31:0] mem_data_out;

    datapath dut (
        .clk(clk),
        .reset(reset),
        .mem_pc(mem_pc),
        .mem_inst_in(mem_inst_in),
        .mem_write(mem_write),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out)
    );

    task feed_inst(input [31:0] inst);
        mem_inst_in = inst;
        @(posedge clk);
        #1;
    endtask

    task dump;
        integer i;
        for (i = 0; i < 16; i = i + 1)
            $display("r%-2d = 0x%08h = %0d",
                i,
                dut.u_rf.regs[i],
                $signed(dut.u_rf.regs[i])
            );
        $display("==========");
    endtask

    always @(posedge clk) begin
        #1;
        dump();
    end

    localparam NOP = 32'b0010011;
    initial begin
        // reset
        reset = 1;
        mem_inst_in = NOP;
        repeat(2) @(posedge clk);
        reset = 0;
        #1;

        // addi x1, x0, 5
        feed_inst(32'h00500093);
        // addi x2, x0, 3
        feed_inst(32'h00300113);
        // add x3, x1, x2
        feed_inst(32'h002080B3);
        // nops to flush pipeline
        repeat(4) feed_inst(NOP);

        $display("done");
        $finish;
    end
endmodule