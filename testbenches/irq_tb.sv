`timescale 1ns/1ps

// irq_tb — end-to-end interrupt test through the real hardware stack:
// core -> tbus -> iohub -> clint -> irq wire -> csr -> trap -> mret.
// a program arms mtimecmp and raises msip over the bus; the handler
// clears both sources architecturally. no tb bus model, no magic addrs
module irq_tb;

    logic clk = 0, reset;
    always #5 clk = ~clk;

    toaster_cpu #(.MEM_FILE("testbenches/irq_boot.hex")) dut (
        .clk   (clk),
        .reset (reset)
    );

    localparam [11:0] A_MSTATUS = 12'h300;
    localparam [11:0] A_MIE     = 12'h304;
    localparam [11:0] A_MTVEC   = 12'h305;
    localparam [11:0] A_MCAUSE  = 12'h342;

    localparam int TIMEOUT_CYCLES = 5000;

    // raw encoders (32-bit RISC-V formats)
    function automatic [31:0] enc_r(
        input [6:0] op, input [4:0] rd, rs1, rs2,
        input [2:0] f3, input [6:0] f7
    );
        enc_r = {f7, rs2, rs1, f3, rd, op};
    endfunction

    function automatic [31:0] enc_i(
        input [6:0] op, input [4:0] rd, rs1,
        input [2:0] f3, input [11:0] imm
    );
        enc_i = {imm, rs1, f3, rd, op};
    endfunction

    function automatic [31:0] enc_s(
        input [4:0] rs1, rs2, input [2:0] f3, input [11:0] imm
    );
        enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    endfunction

    function automatic [31:0] enc_b(
        input [4:0] rs1, rs2, input [2:0] f3, input [12:0] imm
    );
        enc_b = {imm[12], imm[10:5], rs2, rs1, f3,
                 imm[4:1], imm[11], 7'b1100011};
    endfunction

    function automatic [31:0] enc_u(
        input [6:0] op, input [4:0] rd, input [19:0] imm
    );
        enc_u = {imm, rd, op};
    endfunction

    function automatic [31:0] enc_j(
        input [4:0] rd, input [20:0] imm
    );
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    // mnemonic helpers
    function automatic [31:0] i_nop();
        i_nop = enc_i(7'b0010011, 5'd0, 5'd0, 3'b000, 12'd0);
    endfunction
    function automatic [31:0] i_lui  (input [4:0] rd, input [19:0] imm);
        i_lui   = enc_u(7'b0110111, rd, imm);
    endfunction
    function automatic [31:0] i_jal (input [4:0] rd,  input [20:0] imm);
        i_jal  = enc_j(rd, imm);
    endfunction
    function automatic [31:0] i_addi (input [4:0] rd, rs1, input [11:0] imm);
        i_addi  = enc_i(7'b0010011, rd, rs1, 3'b000, imm);
    endfunction
    function automatic [31:0] i_add (input [4:0] rd, rs1, rs2);
        i_add  = enc_r(7'b0110011, rd, rs1, rs2, 3'b000, 7'b0000000);
    endfunction
    function automatic [31:0] i_lw (input [4:0] rd, rs1, input [11:0] imm);
        i_lw  = enc_i(7'b0000011, rd, rs1, 3'b010, imm);
    endfunction
    function automatic [31:0] i_sw (input [4:0] base, src, input [11:0] imm);
        i_sw  = enc_s(base, src, 3'b010, imm);
    endfunction
    function automatic [31:0] i_beq (input [4:0] rs1, rs2, input [12:0] imm);
        i_beq  = enc_b(rs1, rs2, 3'b000, imm);
    endfunction
    function automatic [31:0] i_bne (input [4:0] rs1, rs2, input [12:0] imm);
        i_bne  = enc_b(rs1, rs2, 3'b001, imm);
    endfunction
    function automatic [31:0] i_csrrw (input [4:0] rd, rs1, input [11:0] csr);
        i_csrrw  = enc_i(7'b1110011, rd, rs1, 3'b001, csr);
    endfunction
    function automatic [31:0] i_csrrs (input [4:0] rd, rs1, input [11:0] csr);
        i_csrrs  = enc_i(7'b1110011, rd, rs1, 3'b010, csr);
    endfunction
    function automatic [31:0] i_mret();
        i_mret = enc_i(7'b1110011, 5'd0, 5'd0, 3'b000, 12'h302);
    endfunction

    // program loader: pokes words straight into the unified memory
    logic [31:0] iptr;
    task automatic emit(input logic [31:0] instr);
        dut.u_mem.mem[iptr[31:2]] = instr;
        iptr += 4;
    endtask

    int pass_count = 0, fail_count = 0;

    task automatic check(input string name, input [4:0] r, input [31:0] exp);
        if (dut.u_core.u_rf.regs[r] === exp) begin
            pass_count++; $display("PASS  %s", name);
        end else begin
            fail_count++;
            $display("FAIL  %s  r%0d = %h, expected %h", name, r, dut.u_core.u_rf.regs[r], exp);
        end
    endtask

    task automatic check_cond(input string name, input logic cond);
        if (cond) begin pass_count++; $display("PASS  %s", name); end
        else      begin fail_count++; $display("FAIL  %s", name); end
    endtask

    int cyc;

    initial begin
        $display("=========================================");
        $display("  end-to-end irq testbench (real clint)");
        $display("=========================================");
        reset = 1;
        @(negedge clk); // past time-0 so $readmemh can't clobber the program

        // fill imem with nops, then assemble over it
        for (int i = 0; i < 512; i++) dut.u_mem.mem[i] = i_nop();

        // main: enable irqs, arm the timer, spin; then self-ipi, spin
        iptr = 0;
        emit(i_addi (5'd1, 5'd0, 12'h200));      // 0x00  mtvec = 0x200, direct
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));      // 0x04
        emit(i_addi (5'd1, 5'd0, 12'h088));      // 0x08  mie = MTIE|MSIE
        emit(i_csrrw(5'd0, 5'd1, A_MIE));        // 0x0C
        emit(i_addi (5'd1, 5'd0, 12'h008));      // 0x10  mstatus.MIE = 1
        emit(i_csrrw(5'd0, 5'd1, A_MSTATUS));    // 0x14
        emit(i_lui  (5'd21, 20'h10004));         // 0x18  r21 = mtimecmp base
        emit(i_addi (5'd1, 5'd0, 12'd1));        // 0x1C
        emit(i_sw   (5'd21, 5'd1, 12'd0));       // 0x20  mtimecmp_lo = 1 (hi still -1)
        emit(i_sw   (5'd21, 5'd0, 12'd4));       // 0x24  mtimecmp_hi = 0 -> mti fires
        emit(i_beq  (5'd10, 5'd0, 13'd0));       // 0x28  spin until handler ran
        emit(i_add  (5'd14, 5'd0, 5'd11));       // 0x2C  r14 = first mcause
        emit(i_add  (5'd15, 5'd0, 5'd10));       // 0x30  r15 = entries so far
        emit(i_lui  (5'd13, 20'h10000));         // 0x34  r13 = msip addr
        emit(i_addi (5'd1, 5'd0, 12'd1));        // 0x38
        emit(i_sw   (5'd13, 5'd1, 12'd0));       // 0x3C  msip = 1 -> msi fires
        emit(i_addi (5'd2, 5'd0, 12'd2));        // 0x40
        emit(i_bne  (5'd10, 5'd2, 13'd0));       // 0x44  spin until second entry
        emit(i_add  (5'd16, 5'd0, 5'd11));       // 0x48  r16 = second mcause
        emit(i_lui  (5'd22, 20'h1000C));         // 0x4C
        emit(i_lw   (5'd17, 5'd22, 12'hFF8));    // 0x50  r17 = mtime_lo over the bus
        emit(i_addi (5'd31, 5'd0, 12'h7AB));     // 0x54  sentinel: done
        emit(i_jal  (5'd0, 21'd0));              // 0x58  park

        // handler: save cause, count entry, clear both irq sources, return
        iptr = 32'h200;
        emit(i_csrrs(5'd11, 5'd0, A_MCAUSE));    // r11 = mcause
        emit(i_addi (5'd10, 5'd10, 12'd1));      // r10 = entry count
        emit(i_addi (5'd12, 5'd0, -12'd1));
        emit(i_sw   (5'd21, 5'd12, 12'd4));      // mtimecmp_hi = -1: mti re-armed far future
        emit(i_lui  (5'd12, 20'h10000));
        emit(i_sw   (5'd12, 5'd0, 12'd0));       // msip = 0
        emit(i_mret());

        repeat (3) @(negedge clk);
        reset = 0;

        // run until the program parks or we give up
        for (cyc = 0; cyc < TIMEOUT_CYCLES; cyc++) begin
            @(negedge clk);
            if (dut.u_core.u_rf.regs[31] === 32'h7AB) break;
        end
        check_cond("program reached sentinel", cyc < TIMEOUT_CYCLES);

        check("mti taken, cause = 0x80000007", 5'd14, 32'h8000_0007);
        check("one handler entry after mti",   5'd15, 32'd1);
        check("msi taken, cause = 0x80000003", 5'd16, 32'h8000_0003);
        check("two handler entries total",     5'd10, 32'd2);
        check_cond("mtime readable over bus",  dut.u_core.u_rf.regs[17] !== '0
                                             && dut.u_core.u_rf.regs[17] !== 'x);
        check_cond("mti cleared by handler",   dut.irq_mti === 1'b0);
        check_cond("msi cleared by handler",   dut.irq_msi === 1'b0);

        $display("================================");
        $display("  PASSED %0d  FAILED %0d", pass_count, fail_count);
        if (fail_count == 0) $display("  ALL TESTS PASSED");
        else                 $display("  *** FAILURES DETECTED ***");
        $display("================================");
        $finish;
    end
endmodule
