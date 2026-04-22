`timescale 1ns/1ps
module datapath_tb;
    // clock/reset
    logic clk = 0;
    logic reset;
    always #5 clk = ~clk; // 100MHz

    // memory ports
    logic [31:0] i_addr;
    logic [31:0] i_data;
    logic        d_write;
    logic [31:0] d_addr;
    logic [31:0] d_rdata = '0;
    logic [31:0] d_wdata;

    datapath dut (
        .clk(clk),
        .reset(reset),
        .i_addr(i_addr),
        .i_data(i_data),
        .d_write(d_write),
        .d_addr(d_addr),
        .d_rdata(d_rdata),
        .d_wdata(d_wdata)
    );

    task feed_inst(input [31:0] inst);
        i_data = inst;
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

    // simple stub memory for loads — responds to d_addr
    always_comb begin
        case (d_addr)
            32'h00: d_rdata = 32'h000000AA;
            32'h04: d_rdata = 32'h000000BB;
            32'h08: d_rdata = 32'hDEADBEEF;
            default: d_rdata = 32'hCAFEBABE;
        endcase
    end

    // monitor stores
    always @(posedge clk) begin
        if (d_write)
            $display("[STORE] addr=0x%08h data=0x%08h", d_addr, d_wdata);
    end

    localparam NOP = 32'h00000013;

    initial begin
        // reset
        reset = 1;
        i_data = NOP;
        repeat(2) @(posedge clk);
        reset = 0;
        #1;

        // --- basic ALU ---
        // addi x1, x0, 5
        feed_inst(32'h00500093);
        // addi x2, x0, 3
        feed_inst(32'h00300113);
        // add x3, x1, x2        -> x3 = 8
        feed_inst(32'h002080B3);
        repeat(4) feed_inst(NOP);

        // --- store ---
        // addi x4, x0, 0        -> x4 = 0  (base addr)
        feed_inst(32'h00000213);
        // addi x5, x0, 42       -> x5 = 42 (value to store)
        feed_inst(32'h02a00293);
        // sw x5, 0(x4)          -> mem[0] = 42
        feed_inst(32'h00522023);
        repeat(4) feed_inst(NOP);

        // --- load ---
        // lw x6, 0(x4)          -> x6 = stub returns 0xAA for addr 0
        feed_inst(32'h00022303);
        // lw x7, 4(x4)          -> x7 = stub returns 0xBB for addr 4
        feed_inst(32'h00422383);
        repeat(4) feed_inst(NOP);

        // --- load then use (forwarding) ---
        // lw  x8, 8(x4)         -> x8 = 0xDEADBEEF
        feed_inst(32'h00822403);
        // addi x9, x8, 1        -> x9 = 0xDEADBEF0 (load-use hazard if no interlock)
        feed_inst(32'h00140493);
        repeat(4) feed_inst(NOP);

        $display("done");
        $finish;
    end
endmodule
