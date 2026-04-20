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

    datapath #(.W(32), .RF_ADDR_BITS(5)) dut (
        .clk(clk),
        .reset(reset),

        .mem_pc(mem_pc),
        .mem_inst_in(mem_inst_in),

        .mem_write(mem_write),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out)
    );

    // simple instruction ROM task
    task feed_inst(input [31:0] inst);
        mem_inst_in = inst;
        @(posedge clk);
        #1;
    endtask

    task dump;
        integer i;
        for (i = 0; i < 16; i = i + 1)
            $display("r%-2d = 0x%08h = 0b%032b = %0d",
                i,
                dut.u_rf.regs[i],
                dut.u_rf.regs[i],
                $signed(dut.u_rf.regs[i])
            );
        $display("==========");
    endtask

    always @(posedge clk) begin
        #1;
        dump();
    end

    initial begin
        // reset
        reset = 1;
        mem_inst_in = 32'b0110011; // nop
        repeat(2) @(posedge clk);
        reset = 0;
        #1;

        // addi x1, x0, 5  →  imm=5, rs1=x0, rd=x1
        feed_inst(32'h00500093);
        // addi x2, x0, 3  →  imm=3, rs1=x0, rd=x2
        feed_inst(32'h00300113);
        // add  x3, x1, x2 →  rs1=x1, rs2=x2, rd=x3
        feed_inst(32'h002080B3);
        // nops to flush pipeline
        repeat(4) feed_inst(32'b0110011);

        $display("done");
        $finish;
    end
endmodule
