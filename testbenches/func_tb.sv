`timescale 1ns/1ps
import riscv_pkg::*;

// ====================================================================
// func_tb — self-checking functional testbench for the 5-stage core.
// Each task drives one or more instructions through fetch->writeback,
// then checks architectural state (regfile and data memory) against
// the expected RISC-V semantics. Final summary lines make pass/fail
// trivial to grep:
//
//     ALL TESTS PASSED       — clean run, fail_count == 0
//     *** FAILURES DETECTED ***  — at least one check or timeout failed
//
// The sentinel mechanism: every test ends with ADDI x31, x0, SENTINEL.
// We then block until r31 holds SENTINEL_VAL, with a per-test timeout
// that's reported as a failure (not silently swallowed). SENTINEL_IMM
// is chosen with bit-11 clear so 12-bit sign extension leaves it intact.
// ====================================================================
module func_tb;

    // ----------------------------------------------------------------
    // clock / reset
    // ----------------------------------------------------------------
    logic clk = 0;
    logic reset;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // dut ports
    // ----------------------------------------------------------------
    logic [31:0] i_addr, i_data;
    logic        d_write;
    logic [31:0] d_addr, d_wdata;
    logic [31:0] d_rdata;
    mem_width_t  d_width;
    logic        irq_msi, irq_mti, irq_mei;

    datapath dut (
        .clk    (clk),     .reset  (reset),
        .i_addr (i_addr),  .i_data (i_data),
        .d_write(d_write), .d_addr (d_addr),
        .d_rdata(d_rdata), .d_wdata(d_wdata),
        .d_width(d_width),
        .irq_msi(irq_msi), .irq_mti(irq_mti), .irq_mei(irq_mei)
    );

    // ----------------------------------------------------------------
    // instruction memory — combinational read, written from tb
    // ----------------------------------------------------------------
    localparam int IMEM_WORDS = 4096;
    logic [31:0] imem [0:IMEM_WORDS-1];
    assign i_data = imem[i_addr[31:2]];

    // ----------------------------------------------------------------
    // data memory — mirrors memory.sv: byte/half/word access with
    // sign or zero extension on loads, masked subword writes on stores.
    // d_rdata is sign-extended at the memory boundary because the
    // datapath itself doesn't do any width handling on load data.
    // ----------------------------------------------------------------
    localparam int DMEM_WORDS = 4096;
    logic [31:0] dmem [0:DMEM_WORDS-1];

    wire [31:0] dword = dmem[d_addr[31:2]];
    wire [1:0]  dboff = d_addr[1:0];

    always_comb begin
        case (d_width)
            MW_BYTE: case (dboff)
                2'd0: d_rdata = {{24{dword[7]}},  dword[7:0]};
                2'd1: d_rdata = {{24{dword[15]}}, dword[15:8]};
                2'd2: d_rdata = {{24{dword[23]}}, dword[23:16]};
                2'd3: d_rdata = {{24{dword[31]}}, dword[31:24]};
                default: d_rdata = '0;
            endcase
            MW_HALF: case (dboff)
                2'd0:    d_rdata = {{16{dword[15]}}, dword[15:0]};
                2'd2:    d_rdata = {{16{dword[31]}}, dword[31:16]};
                default: d_rdata = '0;
            endcase
            MW_BYTEU: case (dboff)
                2'd0: d_rdata = {24'b0, dword[7:0]};
                2'd1: d_rdata = {24'b0, dword[15:8]};
                2'd2: d_rdata = {24'b0, dword[23:16]};
                2'd3: d_rdata = {24'b0, dword[31:24]};
                default: d_rdata = '0;
            endcase
            MW_HALFU: case (dboff)
                2'd0:    d_rdata = {16'b0, dword[15:0]};
                2'd2:    d_rdata = {16'b0, dword[31:16]};
                default: d_rdata = '0;
            endcase
            MW_WORD: d_rdata = dword;
            default: d_rdata = '0;
        endcase
    end

    // magic mmio: handler stores to this addr to drop all pending irq lines
    // (stand-in for an iohub claim/ack register until that block is wired up)
    localparam [31:0] IRQ_CLR_ADDR = 32'h1000_0000;
    always_ff @(posedge clk) begin
        if (d_write && d_addr == IRQ_CLR_ADDR) begin
            irq_msi <= 1'b0;
            irq_mti <= 1'b0;
            irq_mei <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (d_write) begin
            case (d_width)
                MW_BYTE: case (dboff)
                    2'd0: dmem[d_addr[31:2]][7:0]   <= d_wdata[7:0];
                    2'd1: dmem[d_addr[31:2]][15:8]  <= d_wdata[7:0];
                    2'd2: dmem[d_addr[31:2]][23:16] <= d_wdata[7:0];
                    2'd3: dmem[d_addr[31:2]][31:24] <= d_wdata[7:0];
                endcase
                MW_HALF: case (dboff)
                    2'd0:    dmem[d_addr[31:2]][15:0]  <= d_wdata[15:0];
                    2'd2:    dmem[d_addr[31:2]][31:16] <= d_wdata[15:0];
                    default: ; // misaligned: drop
                endcase
                MW_WORD: dmem[d_addr[31:2]] <= d_wdata;
                default: ; // ignore funky widths for stores
            endcase
        end
    end

    // ----------------------------------------------------------------
    // raw encoders (32-bit RISC-V formats)
    // ----------------------------------------------------------------
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

    // ----------------------------------------------------------------
    // mnemonic helpers — keep tests readable as ~assembly
    // ----------------------------------------------------------------
    function automatic [31:0] i_nop();
        i_nop = enc_i(7'b0010011, 5'd0, 5'd0, 3'b000, 12'd0);
    endfunction

    // U-type
    function automatic [31:0] i_lui  (input [4:0] rd, input [19:0] imm);
        i_lui   = enc_u(7'b0110111, rd, imm);
    endfunction
    function automatic [31:0] i_auipc(input [4:0] rd, input [19:0] imm);
        i_auipc = enc_u(7'b0010111, rd, imm);
    endfunction

    // J/I jumps
    function automatic [31:0] i_jal (input [4:0] rd,  input [20:0] imm);
        i_jal  = enc_j(rd, imm);
    endfunction
    function automatic [31:0] i_jalr(input [4:0] rd,  input [4:0] rs1, input [11:0] imm);
        i_jalr = enc_i(7'b1100111, rd, rs1, 3'b000, imm);
    endfunction

    // ALU-imm
    function automatic [31:0] i_addi (input [4:0] rd, rs1, input [11:0] imm);
        i_addi  = enc_i(7'b0010011, rd, rs1, 3'b000, imm);
    endfunction
    function automatic [31:0] i_slti (input [4:0] rd, rs1, input [11:0] imm);
        i_slti  = enc_i(7'b0010011, rd, rs1, 3'b010, imm);
    endfunction
    function automatic [31:0] i_sltiu(input [4:0] rd, rs1, input [11:0] imm);
        i_sltiu = enc_i(7'b0010011, rd, rs1, 3'b011, imm);
    endfunction
    function automatic [31:0] i_xori (input [4:0] rd, rs1, input [11:0] imm);
        i_xori  = enc_i(7'b0010011, rd, rs1, 3'b100, imm);
    endfunction
    function automatic [31:0] i_ori  (input [4:0] rd, rs1, input [11:0] imm);
        i_ori   = enc_i(7'b0010011, rd, rs1, 3'b110, imm);
    endfunction
    function automatic [31:0] i_andi (input [4:0] rd, rs1, input [11:0] imm);
        i_andi  = enc_i(7'b0010011, rd, rs1, 3'b111, imm);
    endfunction
    function automatic [31:0] i_slli (input [4:0] rd, rs1, input [4:0] shamt);
        i_slli  = enc_i(7'b0010011, rd, rs1, 3'b001, {7'b0000000, shamt});
    endfunction
    function automatic [31:0] i_srli (input [4:0] rd, rs1, input [4:0] shamt);
        i_srli  = enc_i(7'b0010011, rd, rs1, 3'b101, {7'b0000000, shamt});
    endfunction
    function automatic [31:0] i_srai (input [4:0] rd, rs1, input [4:0] shamt);
        i_srai  = enc_i(7'b0010011, rd, rs1, 3'b101, {7'b0100000, shamt});
    endfunction

    // ALU-reg
    function automatic [31:0] i_add (input [4:0] rd, rs1, rs2);
        i_add  = enc_r(7'b0110011, rd, rs1, rs2, 3'b000, 7'b0000000);
    endfunction
    function automatic [31:0] i_sub (input [4:0] rd, rs1, rs2);
        i_sub  = enc_r(7'b0110011, rd, rs1, rs2, 3'b000, 7'b0100000);
    endfunction
    function automatic [31:0] i_sll (input [4:0] rd, rs1, rs2);
        i_sll  = enc_r(7'b0110011, rd, rs1, rs2, 3'b001, 7'b0000000);
    endfunction
    function automatic [31:0] i_slt (input [4:0] rd, rs1, rs2);
        i_slt  = enc_r(7'b0110011, rd, rs1, rs2, 3'b010, 7'b0000000);
    endfunction
    function automatic [31:0] i_sltu(input [4:0] rd, rs1, rs2);
        i_sltu = enc_r(7'b0110011, rd, rs1, rs2, 3'b011, 7'b0000000);
    endfunction
    function automatic [31:0] i_xor (input [4:0] rd, rs1, rs2);
        i_xor  = enc_r(7'b0110011, rd, rs1, rs2, 3'b100, 7'b0000000);
    endfunction
    function automatic [31:0] i_srl (input [4:0] rd, rs1, rs2);
        i_srl  = enc_r(7'b0110011, rd, rs1, rs2, 3'b101, 7'b0000000);
    endfunction
    function automatic [31:0] i_sra (input [4:0] rd, rs1, rs2);
        i_sra  = enc_r(7'b0110011, rd, rs1, rs2, 3'b101, 7'b0100000);
    endfunction
    function automatic [31:0] i_or  (input [4:0] rd, rs1, rs2);
        i_or   = enc_r(7'b0110011, rd, rs1, rs2, 3'b110, 7'b0000000);
    endfunction
    function automatic [31:0] i_and (input [4:0] rd, rs1, rs2);
        i_and  = enc_r(7'b0110011, rd, rs1, rs2, 3'b111, 7'b0000000);
    endfunction

    // loads / stores
    function automatic [31:0] i_lb (input [4:0] rd, rs1, input [11:0] imm);
        i_lb  = enc_i(7'b0000011, rd, rs1, 3'b000, imm);
    endfunction
    function automatic [31:0] i_lh (input [4:0] rd, rs1, input [11:0] imm);
        i_lh  = enc_i(7'b0000011, rd, rs1, 3'b001, imm);
    endfunction
    function automatic [31:0] i_lw (input [4:0] rd, rs1, input [11:0] imm);
        i_lw  = enc_i(7'b0000011, rd, rs1, 3'b010, imm);
    endfunction
    function automatic [31:0] i_lbu(input [4:0] rd, rs1, input [11:0] imm);
        i_lbu = enc_i(7'b0000011, rd, rs1, 3'b100, imm);
    endfunction
    function automatic [31:0] i_lhu(input [4:0] rd, rs1, input [11:0] imm);
        i_lhu = enc_i(7'b0000011, rd, rs1, 3'b101, imm);
    endfunction
    function automatic [31:0] i_sb (input [4:0] base, src, input [11:0] imm);
        i_sb  = enc_s(base, src, 3'b000, imm);
    endfunction
    function automatic [31:0] i_sh (input [4:0] base, src, input [11:0] imm);
        i_sh  = enc_s(base, src, 3'b001, imm);
    endfunction
    function automatic [31:0] i_sw (input [4:0] base, src, input [11:0] imm);
        i_sw  = enc_s(base, src, 3'b010, imm);
    endfunction

    // branches
    function automatic [31:0] i_beq (input [4:0] rs1, rs2, input [12:0] imm);
        i_beq  = enc_b(rs1, rs2, 3'b000, imm);
    endfunction
    function automatic [31:0] i_bne (input [4:0] rs1, rs2, input [12:0] imm);
        i_bne  = enc_b(rs1, rs2, 3'b001, imm);
    endfunction
    function automatic [31:0] i_blt (input [4:0] rs1, rs2, input [12:0] imm);
        i_blt  = enc_b(rs1, rs2, 3'b100, imm);
    endfunction
    function automatic [31:0] i_bge (input [4:0] rs1, rs2, input [12:0] imm);
        i_bge  = enc_b(rs1, rs2, 3'b101, imm);
    endfunction
    function automatic [31:0] i_bltu(input [4:0] rs1, rs2, input [12:0] imm);
        i_bltu = enc_b(rs1, rs2, 3'b110, imm);
    endfunction
    function automatic [31:0] i_bgeu(input [4:0] rs1, rs2, input [12:0] imm);
        i_bgeu = enc_b(rs1, rs2, 3'b111, imm);
    endfunction

    // RV32M
    function automatic [31:0] i_mul    (input [4:0] rd, rs1, rs2);
        i_mul    = enc_r(7'b0110011, rd, rs1, rs2, 3'b000, 7'b0000001);
    endfunction
    function automatic [31:0] i_mulh   (input [4:0] rd, rs1, rs2);
        i_mulh   = enc_r(7'b0110011, rd, rs1, rs2, 3'b001, 7'b0000001);
    endfunction
    function automatic [31:0] i_mulhsu (input [4:0] rd, rs1, rs2);
        i_mulhsu = enc_r(7'b0110011, rd, rs1, rs2, 3'b010, 7'b0000001);
    endfunction
    function automatic [31:0] i_mulhu  (input [4:0] rd, rs1, rs2);
        i_mulhu  = enc_r(7'b0110011, rd, rs1, rs2, 3'b011, 7'b0000001);
    endfunction
    function automatic [31:0] i_div    (input [4:0] rd, rs1, rs2);
        i_div    = enc_r(7'b0110011, rd, rs1, rs2, 3'b100, 7'b0000001);
    endfunction
    function automatic [31:0] i_divu   (input [4:0] rd, rs1, rs2);
        i_divu   = enc_r(7'b0110011, rd, rs1, rs2, 3'b101, 7'b0000001);
    endfunction
    function automatic [31:0] i_rem    (input [4:0] rd, rs1, rs2);
        i_rem    = enc_r(7'b0110011, rd, rs1, rs2, 3'b110, 7'b0000001);
    endfunction
    function automatic [31:0] i_remu   (input [4:0] rd, rs1, rs2);
        i_remu   = enc_r(7'b0110011, rd, rs1, rs2, 3'b111, 7'b0000001);
    endfunction

    // CSR (RV32 Zicsr)
    function automatic [31:0] i_csrrw (input [4:0] rd, rs1, input [11:0] csr);
        i_csrrw  = enc_i(7'b1110011, rd, rs1, 3'b001, csr);
    endfunction
    function automatic [31:0] i_csrrs (input [4:0] rd, rs1, input [11:0] csr);
        i_csrrs  = enc_i(7'b1110011, rd, rs1, 3'b010, csr);
    endfunction
    function automatic [31:0] i_csrrc (input [4:0] rd, rs1, input [11:0] csr);
        i_csrrc  = enc_i(7'b1110011, rd, rs1, 3'b011, csr);
    endfunction
    function automatic [31:0] i_csrrwi(input [4:0] rd, input [4:0] uimm, input [11:0] csr);
        i_csrrwi = enc_i(7'b1110011, rd, uimm, 3'b101, csr);
    endfunction
    function automatic [31:0] i_csrrsi(input [4:0] rd, input [4:0] uimm, input [11:0] csr);
        i_csrrsi = enc_i(7'b1110011, rd, uimm, 3'b110, csr);
    endfunction
    function automatic [31:0] i_csrrci(input [4:0] rd, input [4:0] uimm, input [11:0] csr);
        i_csrrci = enc_i(7'b1110011, rd, uimm, 3'b111, csr);
    endfunction
    function automatic [31:0] i_mret();
        i_mret = enc_i(7'b1110011, 5'd0, 5'd0, 3'b000, 12'h302);
    endfunction
    function automatic [31:0] i_ecall();
        i_ecall = enc_i(7'b1110011, 5'd0, 5'd0, 3'b000, 12'h000);
    endfunction
    function automatic [31:0] i_ebreak();
        i_ebreak = enc_i(7'b1110011, 5'd0, 5'd0, 3'b000, 12'h001);
    endfunction

    // CSR addresses used in tests
    localparam [11:0] A_MSTATUS  = 12'h300;
    localparam [11:0] A_MISA     = 12'h301;
    localparam [11:0] A_MIE      = 12'h304;
    localparam [11:0] A_MTVEC    = 12'h305;
    localparam [11:0] A_MSCRATCH = 12'h340;
    localparam [11:0] A_MEPC     = 12'h341;
    localparam [11:0] A_MCAUSE   = 12'h342;
    localparam [11:0] A_MTVAL    = 12'h343;
    localparam [11:0] A_MHARTID  = 12'hF14;

    // ----------------------------------------------------------------
    // sentinel — bit-11 clear so 12-bit sign extension is a no-op
    // ----------------------------------------------------------------
    localparam [4:0]  SENTINEL_REG    = 5'd31;
    localparam [11:0] SENTINEL_IMM    = 12'h7AB;
    localparam [31:0] SENTINEL_VAL    = 32'h000007AB;
    localparam int    TIMEOUT_CYCLES  = 4000;
    localparam int    DRAIN_CYCLES    = 6;

    function automatic [31:0] i_sentinel();
        i_sentinel = i_addi(SENTINEL_REG, 5'd0, SENTINEL_IMM);
    endfunction

    // ----------------------------------------------------------------
    // test infrastructure
    // ----------------------------------------------------------------
    int       pass_count = 0;
    int       fail_count = 0;
    int       test_pass;
    int       test_fail;
    int       iptr;
    logic     timed_out;
    string    current_test;

    task automatic emit(input logic [31:0] instr);
        if (iptr >= IMEM_WORDS) begin
            $fatal(1, "imem overflow at iptr=%0d", iptr);
        end
        imem[iptr] = instr;
        iptr++;
    endtask

    task automatic pipeline_reset();
        reset     = 1;
        iptr      = 0;
        timed_out = 0;
        irq_msi   = 0;
        irq_mti   = 0;
        irq_mei   = 0;
        for (int i = 0; i < IMEM_WORDS; i++) imem[i] = i_nop();
        for (int i = 0; i < DMEM_WORDS; i++) dmem[i] = '0;
        @(posedge clk);
        @(posedge clk);
        reset = 0;
    endtask

    // append the sentinel and block until it writes r31, or time out.
    // a timeout is a failure of the test (caller checks `timed_out`).
    // bounded while loop instead of fork/join_any so older parsers (Quartus
    // 18.1 Lite SV-2005) can handle it.
    task automatic wait_done();
        int t;
        emit(i_sentinel());
        timed_out = 0;
        t = 0;
        while (t < TIMEOUT_CYCLES &&
               dut.u_rf.regs[SENTINEL_REG] !== SENTINEL_VAL) begin
            @(posedge clk);
            t = t + 1;
        end
        if (dut.u_rf.regs[SENTINEL_REG] === SENTINEL_VAL) begin
            repeat (DRAIN_CYCLES) @(posedge clk);
        end else begin
            timed_out = 1;
        end
    endtask

    task automatic start_test(input string name);
        current_test = name;
        test_pass    = 0;
        test_fail    = 0;
        $display("");
        $display("---- %s ----", name);
    endtask

    task automatic end_test();
        if (timed_out) begin
            $display("  FAIL  TIMEOUT (sentinel never retired, pc=0x%08h)", dut.pc);
            test_fail++;
        end
        $display("  ==> %s : %0d passed, %0d failed",
                 current_test, test_pass, test_fail);
        pass_count += test_pass;
        fail_count += test_fail;
    endtask

    task automatic check(
        input string        name,
        input [4:0]         rd,
        input logic [31:0]  expected
    );
        logic [31:0] got;
        if (timed_out) return;
        got = dut.u_rf.regs[rd];
        if (got === expected) begin
            $display("  PASS  %-22s  r%-2d = 0x%08h (%0d)",
                     name, rd, got, $signed(got));
            test_pass++;
        end else begin
            $display("  FAIL  %-22s  r%-2d = 0x%08h  expected 0x%08h",
                     name, rd, got, expected);
            test_fail++;
        end
    endtask

    task automatic check_mem(
        input string        name,
        input logic [31:0]  addr,
        input logic [31:0]  expected
    );
        logic [31:0] got;
        if (timed_out) return;
        got = dmem[addr[31:2]];
        if (got === expected) begin
            $display("  PASS  %-22s  mem[0x%08h] = 0x%08h", name, addr, got);
            test_pass++;
        end else begin
            $display("  FAIL  %-22s  mem[0x%08h] = 0x%08h  expected 0x%08h",
                     name, addr, got, expected);
            test_fail++;
        end
    endtask

    // ================================================================
    // ============================ TESTS =============================
    // ================================================================

    // ----------------------------------------------------------------
    // LUI — places imm20 in upper 20 bits, lower 12 are zero
    // ----------------------------------------------------------------
    task automatic test_lui();
        start_test("LUI");
        pipeline_reset();
        emit(i_lui(5'd1, 20'h00000));
        emit(i_lui(5'd2, 20'h00001));
        emit(i_lui(5'd3, 20'hABCDE));
        emit(i_lui(5'd4, 20'hFFFFF));
        wait_done();
        check("LUI 0",       5'd1, 32'h00000000);
        check("LUI 1",       5'd2, 32'h00001000);
        check("LUI 0xABCDE", 5'd3, 32'hABCDE000);
        check("LUI 0xFFFFF", 5'd4, 32'hFFFFF000);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // AUIPC — pc + (imm20 << 12). pc is the AUIPC's own pc.
    // ----------------------------------------------------------------
    task automatic test_auipc();
        start_test("AUIPC");
        pipeline_reset();
        emit(i_auipc(5'd1, 20'h00000));  // pc=0   -> 0
        emit(i_auipc(5'd2, 20'h00001));  // pc=4   -> 0x00001004
        emit(i_auipc(5'd3, 20'h12345));  // pc=8   -> 0x12345008
        emit(i_auipc(5'd4, 20'hFFFFF));  // pc=12  -> 0xFFFFF00C
        wait_done();
        check("AUIPC pc=0",  5'd1, 32'h00000000);
        check("AUIPC pc=4",  5'd2, 32'h00001004);
        check("AUIPC pc=8",  5'd3, 32'h12345008);
        check("AUIPC pc=12", 5'd4, 32'hFFFFF00C);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // ADDI — including most-positive (0x7FF) and most-negative (0x800)
    //        12-bit immediates, sign-extended
    // ----------------------------------------------------------------
    task automatic test_addi();
        start_test("ADDI");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd5));     // r1 = 5
        emit(i_addi(5'd2, 5'd1, 12'd10));    // r2 = 15  (EX->EX forward)
        emit(i_addi(5'd3, 5'd2, 12'hFFF));   // r3 = 14  (imm = -1)
        emit(i_addi(5'd4, 5'd0, 12'h7FF));   // r4 = 0x000007FF (max pos)
        emit(i_addi(5'd5, 5'd0, 12'h800));   // r5 = 0xFFFFF800 (min neg)
        emit(i_addi(5'd6, 5'd0, 12'h000));   // r6 = 0
        emit(i_addi(5'd7, 5'd5, 12'h7FF));   // r7 = 0xFFFFF800+0x7FF = 0xFFFFFFFF
        wait_done();
        check("ADDI base",   5'd1, 32'd5);
        check("ADDI fwd",    5'd2, 32'd15);
        check("ADDI neg",    5'd3, 32'd14);
        check("ADDI maxpos", 5'd4, 32'h000007FF);
        check("ADDI minneg", 5'd5, 32'hFFFFF800);
        check("ADDI zero",   5'd6, 32'd0);
        check("ADDI sum",    5'd7, 32'hFFFFFFFF);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // SLTI / SLTIU — set if rs1 < imm
    // ----------------------------------------------------------------
    task automatic test_slti_sltiu();
        start_test("SLTI / SLTIU");
        pipeline_reset();
        emit(i_addi (5'd1, 5'd0, 12'd5));      // r1 = 5
        emit(i_addi (5'd2, 5'd0, 12'hFFF));    // r2 = -1
        emit(i_slti (5'd3, 5'd1, 12'd10));     // 5 < 10           -> 1
        emit(i_slti (5'd4, 5'd1, 12'd5));      // 5 < 5            -> 0
        emit(i_slti (5'd5, 5'd1, 12'hFFF));    // 5 < -1           -> 0
        emit(i_slti (5'd6, 5'd2, 12'd0));      // -1 < 0           -> 1
        emit(i_sltiu(5'd7, 5'd1, 12'd10));     // 5u < 10u         -> 1
        emit(i_sltiu(5'd8, 5'd2, 12'd1));      // 0xFFFFFFFF < 1u  -> 0
        emit(i_sltiu(5'd9, 5'd1, 12'hFFF));    // 5u < 0xFFFFFFFFu -> 1
        wait_done();
        check("SLTI 5<10",       5'd3, 32'd1);
        check("SLTI 5<5",        5'd4, 32'd0);
        check("SLTI 5<-1",       5'd5, 32'd0);
        check("SLTI -1<0",       5'd6, 32'd1);
        check("SLTIU 5u<10u",    5'd7, 32'd1);
        check("SLTIU max u<1u",  5'd8, 32'd0);
        check("SLTIU 5u<maxu",   5'd9, 32'd1);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // XORI / ORI / ANDI
    // ----------------------------------------------------------------
    task automatic test_logical_i();
        start_test("XORI / ORI / ANDI");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'h0F0));    // r1 = 0xF0
        emit(i_xori(5'd2, 5'd1, 12'h00F));    // 0xF0 ^ 0x0F = 0xFF
        emit(i_ori (5'd3, 5'd1, 12'h00F));    // 0xF0 | 0x0F = 0xFF
        emit(i_andi(5'd4, 5'd1, 12'h0FF));    // 0xF0 & 0xFF = 0xF0
        emit(i_xori(5'd5, 5'd0, 12'hFFF));    // 0 ^ -1      = -1
        emit(i_andi(5'd6, 5'd5, 12'h0F0));    // -1 & 0xF0   = 0xF0
        emit(i_ori (5'd7, 5'd0, 12'd0));      // 0 | 0       = 0
        wait_done();
        check("XORI",     5'd2, 32'h000000FF);
        check("ORI",      5'd3, 32'h000000FF);
        check("ANDI",     5'd4, 32'h000000F0);
        check("XORI -1",  5'd5, 32'hFFFFFFFF);
        check("ANDI mask",5'd6, 32'h000000F0);
        check("ORI zero", 5'd7, 32'h00000000);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // SLLI / SRLI / SRAI — shift by 0, 1, 31
    // ----------------------------------------------------------------
    task automatic test_shift_i();
        start_test("SLLI / SRLI / SRAI");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd1));        // r1 = 1
        emit(i_addi(5'd2, 5'd0, 12'hFFF));      // r2 = 0xFFFFFFFF (-1)
        emit(i_slli(5'd3, 5'd1, 5'd0));         // 1 << 0  = 1
        emit(i_slli(5'd4, 5'd1, 5'd31));        // 1 << 31 = 0x80000000
        emit(i_srli(5'd5, 5'd2, 5'd0));         // -1 >> 0 = 0xFFFFFFFF
        emit(i_srli(5'd6, 5'd2, 5'd1));         // -1 >>u 1 = 0x7FFFFFFF
        emit(i_srli(5'd7, 5'd2, 5'd31));        // -1 >>u 31 = 1
        emit(i_srai(5'd8, 5'd2, 5'd1));         // -1 >>s 1 = -1
        emit(i_srai(5'd9, 5'd2, 5'd31));        // -1 >>s 31 = -1
        emit(i_addi(5'd10, 5'd0, 12'h7FF));     // r10 = 0x7FF
        emit(i_slli(5'd11, 5'd10, 5'd4));       // 0x7FF<<4 = 0x7FF0
        wait_done();
        check("SLLI shamt=0",  5'd3,  32'd1);
        check("SLLI shamt=31", 5'd4,  32'h80000000);
        check("SRLI shamt=0",  5'd5,  32'hFFFFFFFF);
        check("SRLI shamt=1",  5'd6,  32'h7FFFFFFF);
        check("SRLI shamt=31", 5'd7,  32'd1);
        check("SRAI shamt=1",  5'd8,  32'hFFFFFFFF);
        check("SRAI shamt=31", 5'd9,  32'hFFFFFFFF);
        check("SLLI 0x7FF<<4", 5'd11, 32'h00007FF0);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // ADD / SUB
    // ----------------------------------------------------------------
    task automatic test_add_sub();
        start_test("ADD / SUB");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd15));        // r1 = 15
        emit(i_addi(5'd2, 5'd0, 12'd10));        // r2 = 10
        emit(i_add (5'd3, 5'd1, 5'd2));          // 15 + 10 = 25
        emit(i_sub (5'd4, 5'd1, 5'd2));          // 15 - 10 = 5
        emit(i_sub (5'd5, 5'd2, 5'd1));          // 10 - 15 = -5
        emit(i_add (5'd6, 5'd0, 5'd0));          // 0 + 0   = 0
        emit(i_addi(5'd7, 5'd0, 12'h800));       // r7 = 0xFFFFF800
        emit(i_sub (5'd8, 5'd0, 5'd7));          // 0 - r7 = 0x00000800
        emit(i_add (5'd9, 5'd7, 5'd7));          // overflow wraps
        wait_done();
        check("ADD",         5'd3, 32'd25);
        check("SUB",         5'd4, 32'd5);
        check("SUB neg",     5'd5, 32'hFFFFFFFB);
        check("ADD 0+0",     5'd6, 32'd0);
        check("SUB negate",  5'd8, 32'h00000800);
        check("ADD wrap",    5'd9, 32'hFFFFF000);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // XOR / OR / AND
    // ----------------------------------------------------------------
    task automatic test_logical_r();
        start_test("XOR / OR / AND");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'h0F0));      // r1 = 0xF0
        emit(i_addi(5'd2, 5'd0, 12'h00F));      // r2 = 0x0F
        emit(i_xor (5'd3, 5'd1, 5'd2));         // 0xF0 ^ 0x0F = 0xFF
        emit(i_or  (5'd4, 5'd1, 5'd2));         // 0xF0 | 0x0F = 0xFF
        emit(i_and (5'd5, 5'd1, 5'd2));         // 0xF0 & 0x0F = 0x00
        emit(i_addi(5'd6, 5'd0, 12'hFFF));      // r6 = -1
        emit(i_xor (5'd7, 5'd6, 5'd6));         // x ^ x = 0
        emit(i_and (5'd8, 5'd6, 5'd1));         // -1 & 0xF0 = 0xF0
        emit(i_or  (5'd9, 5'd6, 5'd1));         // -1 | 0xF0 = -1
        wait_done();
        check("XOR",          5'd3, 32'h000000FF);
        check("OR",           5'd4, 32'h000000FF);
        check("AND",          5'd5, 32'h00000000);
        check("XOR self",     5'd7, 32'h00000000);
        check("AND -1,mask",  5'd8, 32'h000000F0);
        check("OR -1,mask",   5'd9, 32'hFFFFFFFF);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // SLL / SRL / SRA — rs2 shift amount is masked to lower 5 bits
    // ----------------------------------------------------------------
    task automatic test_shift_r();
        start_test("SLL / SRL / SRA");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd1));        // r1 = 1
        emit(i_addi(5'd2, 5'd0, 12'd4));        // r2 = 4
        emit(i_addi(5'd3, 5'd0, 12'hFFF));      // r3 = -1
        emit(i_addi(5'd4, 5'd0, 12'h0FF));      // r4 = 0xFF (incl high bits = 0x100 + 0x1F = 0x33)
        emit(i_sll (5'd5, 5'd1, 5'd2));         // 1 << 4 = 16
        emit(i_sll (5'd6, 5'd1, 5'd4));         // 1 << (0xFF & 0x1F) = 1 << 31
        emit(i_srl (5'd7, 5'd3, 5'd2));         // -1 >>u 4 = 0x0FFFFFFF
        emit(i_sra (5'd8, 5'd3, 5'd2));         // -1 >>s 4 = -1
        emit(i_addi(5'd9, 5'd0, 12'd0));        // r9 = 0
        emit(i_sll (5'd10,5'd1, 5'd9));         // 1 << 0 = 1 (shamt=0)
        wait_done();
        check("SLL by 4",      5'd5,  32'd16);
        check("SLL shamt mask",5'd6,  32'h80000000);
        check("SRL -1 by 4",   5'd7,  32'h0FFFFFFF);
        check("SRA -1 by 4",   5'd8,  32'hFFFFFFFF);
        check("SLL shamt=0",   5'd10, 32'd1);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // SLT / SLTU
    // ----------------------------------------------------------------
    task automatic test_slt_r();
        start_test("SLT / SLTU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd5));         // r1 = 5
        emit(i_addi(5'd2, 5'd0, 12'd10));        // r2 = 10
        emit(i_addi(5'd3, 5'd0, 12'hFFF));       // r3 = -1
        emit(i_slt (5'd4, 5'd1, 5'd2));          // 5  <  10 signed   -> 1
        emit(i_slt (5'd5, 5'd2, 5'd1));          // 10 <  5  signed   -> 0
        emit(i_slt (5'd6, 5'd3, 5'd0));          // -1 <  0  signed   -> 1
        emit(i_slt (5'd7, 5'd3, 5'd3));          // -1 <  -1          -> 0
        emit(i_sltu(5'd8, 5'd1, 5'd2));          // 5u <  10u         -> 1
        emit(i_sltu(5'd9, 5'd3, 5'd0));          // maxu < 0u         -> 0
        emit(i_sltu(5'd10,5'd0, 5'd3));          // 0u  < maxu        -> 1
        wait_done();
        check("SLT lt",   5'd4,  32'd1);
        check("SLT gt",   5'd5,  32'd0);
        check("SLT neg",  5'd6,  32'd1);
        check("SLT eq",   5'd7,  32'd0);
        check("SLTU lt",  5'd8,  32'd1);
        check("SLTU max", 5'd9,  32'd0);
        check("SLTU min", 5'd10, 32'd1);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // LW / SW — round-trip a word
    // ----------------------------------------------------------------
    task automatic test_lw_sw();
        start_test("LW / SW");
        pipeline_reset();
        emit(i_lui (5'd1, 20'h12345));            // r1 = 0x12345000
        emit(i_addi(5'd1, 5'd1, 12'h678));        // r1 = 0x12345678
        emit(i_addi(5'd2, 5'd0, 12'h100));        // r2 = 0x100 (base)
        emit(i_sw  (5'd2, 5'd1, 12'h000));        // mem[0x100] = r1
        emit(i_sw  (5'd2, 5'd1, 12'h008));        // mem[0x108] = r1
        emit(i_lw  (5'd3, 5'd2, 12'h000));        // r3 = mem[0x100]
        emit(i_addi(5'd4, 5'd0, 12'd0));          // separate the loads
        emit(i_lw  (5'd5, 5'd2, 12'h008));        // r5 = mem[0x108]
        wait_done();
        check("LW first",  5'd3, 32'h12345678);
        check("LW second", 5'd5, 32'h12345678);
        check_mem("SW first",  32'h100, 32'h12345678);
        check_mem("SW second", 32'h108, 32'h12345678);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // LH / SH / LHU — sign vs zero extension, both halves
    // ----------------------------------------------------------------
    task automatic test_lh_sh_lhu();
        start_test("LH / SH / LHU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'h7FF));        // r1 = 0x000007FF
        emit(i_addi(5'd2, 5'd0, 12'hFFF));        // r2 = 0xFFFFFFFF  (low half 0xFFFF, sign bit set)
        emit(i_addi(5'd3, 5'd0, 12'h200));        // base = 0x200
        emit(i_sh  (5'd3, 5'd1, 12'h000));        // mem[0x200][15:0] = 0x07FF
        emit(i_sh  (5'd3, 5'd2, 12'h002));        // mem[0x200][31:16] = 0xFFFF
        emit(i_addi(5'd4, 5'd0, 12'd0));
        emit(i_lh  (5'd5, 5'd3, 12'h000));        // signed half, low: 0x000007FF (bit 15 = 0)
        emit(i_lh  (5'd6, 5'd3, 12'h002));        // signed half, high: 0xFFFFFFFF
        emit(i_lhu (5'd7, 5'd3, 12'h002));        // unsigned: 0x0000FFFF
        emit(i_lhu (5'd8, 5'd3, 12'h000));        // unsigned: 0x000007FF
        wait_done();
        check("LH +",       5'd5, 32'h000007FF);
        check("LH -",       5'd6, 32'hFFFFFFFF);
        check("LHU high",   5'd7, 32'h0000FFFF);
        check("LHU low",    5'd8, 32'h000007FF);
        check_mem("SH packed", 32'h200, 32'hFFFF07FF);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // LB / SB / LBU — exercise all 4 byte offsets
    // ----------------------------------------------------------------
    task automatic test_lb_sb_lbu();
        start_test("LB / SB / LBU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'h0AB));         // value 1 = 0xAB (sign-extended pos byte? 0xAB MSB=1, signed=-85)
        emit(i_addi(5'd2, 5'd0, 12'h07F));         // value 2 = 0x7F (positive byte)
        emit(i_addi(5'd3, 5'd0, 12'h300));         // base = 0x300
        emit(i_sb  (5'd3, 5'd1, 12'h000));         // mem[0x300] byte0 = 0xAB
        emit(i_sb  (5'd3, 5'd2, 12'h001));         // mem[0x300] byte1 = 0x7F
        emit(i_sb  (5'd3, 5'd1, 12'h002));         // mem[0x300] byte2 = 0xAB
        emit(i_sb  (5'd3, 5'd2, 12'h003));         // mem[0x300] byte3 = 0x7F
        emit(i_addi(5'd4, 5'd0, 12'd0));
        emit(i_lb  (5'd5, 5'd3, 12'h000));         // LB byte0: 0xFFFFFFAB
        emit(i_lb  (5'd6, 5'd3, 12'h001));         // LB byte1: 0x0000007F
        emit(i_lbu (5'd7, 5'd3, 12'h002));         // LBU byte2: 0x000000AB
        emit(i_lbu (5'd8, 5'd3, 12'h003));         // LBU byte3: 0x0000007F
        wait_done();
        check("LB  byte0 neg", 5'd5, 32'hFFFFFFAB);
        check("LB  byte1 pos", 5'd6, 32'h0000007F);
        check("LBU byte2",     5'd7, 32'h000000AB);
        check("LBU byte3",     5'd8, 32'h0000007F);
        check_mem("SB packed", 32'h300, 32'h7FAB7FAB);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // BEQ / BNE — taken AND not-taken
    // 3 instructions emitted per branch site so the two-slot
    // shadow can be both filled (not-taken) and squashed (taken).
    // ----------------------------------------------------------------
    task automatic test_beq_bne();
        start_test("BEQ / BNE");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd7));            // pc=0  r1=7
        emit(i_addi(5'd2, 5'd0, 12'd7));            // pc=4  r2=7
        emit(i_addi(5'd3, 5'd0, 12'd9));            // pc=8  r3=9
        // BEQ taken: r1 == r2 -> skip the next 2 instructions
        emit(i_beq (5'd1, 5'd2, 13'd12));           // pc=12 BEQ +12
        emit(i_addi(5'd4, 5'd0, 12'd99));           // pc=16 (squashed)
        emit(i_addi(5'd4, 5'd0, 12'd99));           // pc=20 (squashed)
        emit(i_addi(5'd4, 5'd0, 12'd1));            // pc=24 r4=1 (landing)
        // BEQ not-taken: r1 != r3 -> fall through both shadow slots
        emit(i_beq (5'd1, 5'd3, 13'd12));           // pc=28
        emit(i_addi(5'd5, 5'd0, 12'd2));            // pc=32 r5=2  (executes)
        emit(i_addi(5'd6, 5'd0, 12'd3));            // pc=36 r6=3  (executes)
        emit(i_addi(5'd7, 5'd0, 12'd4));            // pc=40 r7=4
        // BNE taken: r1 != r3
        emit(i_bne (5'd1, 5'd3, 13'd12));           // pc=44 BNE +12
        emit(i_addi(5'd8, 5'd0, 12'd99));           // pc=48 (squashed)
        emit(i_addi(5'd8, 5'd0, 12'd99));           // pc=52 (squashed)
        emit(i_addi(5'd8, 5'd0, 12'd5));            // pc=56 r8=5 (landing)
        // BNE not-taken: r1 == r2
        emit(i_bne (5'd1, 5'd2, 13'd12));           // pc=60
        emit(i_addi(5'd9, 5'd0, 12'd6));            // pc=64 r9=6
        wait_done();
        check("BEQ taken r4",    5'd4, 32'd1);
        check("BEQ ntaken r5",   5'd5, 32'd2);
        check("BEQ ntaken r6",   5'd6, 32'd3);
        check("BNE taken r8",    5'd8, 32'd5);
        check("BNE ntaken r9",   5'd9, 32'd6);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // BLT / BGE — signed comparisons
    // ----------------------------------------------------------------
    task automatic test_blt_bge();
        start_test("BLT / BGE");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd5));             // r1 = 5
        emit(i_addi(5'd2, 5'd0, 12'd9));             // r2 = 9
        emit(i_addi(5'd3, 5'd0, 12'hFFF));           // r3 = -1
        emit(i_blt (5'd1, 5'd2, 13'd12));            // 5 < 9 -> taken
        emit(i_addi(5'd4, 5'd0, 12'd99));            // squashed
        emit(i_addi(5'd4, 5'd0, 12'd99));            // squashed
        emit(i_addi(5'd4, 5'd0, 12'd1));             // r4 = 1
        emit(i_blt (5'd2, 5'd1, 13'd12));            // 9 < 5 -> not taken
        emit(i_addi(5'd5, 5'd0, 12'd2));             // r5 = 2
        emit(i_addi(5'd6, 5'd0, 12'd3));             // r6 = 3
        emit(i_addi(5'd7, 5'd0, 12'd0));             // r7 = 0
        emit(i_blt (5'd3, 5'd0, 13'd12));            // -1 < 0 -> taken (signed)
        emit(i_addi(5'd7, 5'd0, 12'd99));            // squashed
        emit(i_addi(5'd7, 5'd0, 12'd99));            // squashed
        emit(i_addi(5'd7, 5'd0, 12'd4));             // r7 = 4
        emit(i_bge (5'd2, 5'd1, 13'd12));            // 9 >= 5 -> taken
        emit(i_addi(5'd8, 5'd0, 12'd99));            // squashed
        emit(i_addi(5'd8, 5'd0, 12'd99));            // squashed
        emit(i_addi(5'd8, 5'd0, 12'd5));             // r8 = 5
        emit(i_bge (5'd1, 5'd2, 13'd12));            // 5 >= 9 -> not taken
        emit(i_addi(5'd9, 5'd0, 12'd6));             // r9 = 6
        wait_done();
        check("BLT taken",      5'd4, 32'd1);
        check("BLT ntaken",     5'd5, 32'd2);
        check("BLT signed neg", 5'd7, 32'd4);
        check("BGE taken",      5'd8, 32'd5);
        check("BGE ntaken",     5'd9, 32'd6);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // BLTU / BGEU — unsigned comparisons
    // ----------------------------------------------------------------
    task automatic test_bltu_bgeu();
        start_test("BLTU / BGEU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd1));               // r1 = 1
        emit(i_addi(5'd2, 5'd0, 12'hFFF));             // r2 = 0xFFFFFFFF
        emit(i_bltu(5'd1, 5'd2, 13'd12));              // 1u < maxu -> taken
        emit(i_addi(5'd3, 5'd0, 12'd99));              // squashed
        emit(i_addi(5'd3, 5'd0, 12'd99));              // squashed
        emit(i_addi(5'd3, 5'd0, 12'd1));               // r3 = 1
        emit(i_bltu(5'd2, 5'd1, 13'd12));              // maxu < 1u -> not taken
        emit(i_addi(5'd4, 5'd0, 12'd2));               // r4 = 2
        emit(i_addi(5'd5, 5'd0, 12'd3));               // r5 = 3
        emit(i_bgeu(5'd2, 5'd1, 13'd12));              // maxu >= 1u -> taken
        emit(i_addi(5'd6, 5'd0, 12'd99));              // squashed
        emit(i_addi(5'd6, 5'd0, 12'd99));              // squashed
        emit(i_addi(5'd6, 5'd0, 12'd4));               // r6 = 4
        emit(i_bgeu(5'd1, 5'd2, 13'd12));              // 1u >= maxu -> not taken
        emit(i_addi(5'd7, 5'd0, 12'd5));               // r7 = 5
        wait_done();
        check("BLTU taken",  5'd3, 32'd1);
        check("BLTU ntaken", 5'd4, 32'd2);
        check("BGEU taken",  5'd6, 32'd4);
        check("BGEU ntaken", 5'd7, 32'd5);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // backward branch — count loop terminates and falls through to sentinel.
    // verifies branch + flush + forwarding around a tight loop.
    // ----------------------------------------------------------------
    task automatic test_branch_backward();
        start_test("Backward branch loop");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd0));            // pc=0   r1 = 0
        emit(i_addi(5'd2, 5'd0, 12'd5));            // pc=4   r2 = 5
        emit(i_addi(5'd1, 5'd1, 12'd1));            // pc=8   r1++           (LOOP)
        emit(i_blt (5'd1, 5'd2, 13'h1FFC));         // pc=12  if r1<r2 -> -4 (back to LOOP)
        emit(i_addi(5'd3, 5'd1, 12'd0));            // pc=16  r3 = r1 (after loop)
        wait_done();
        check("loop count", 5'd1, 32'd5);
        check("loop copy",  5'd3, 32'd5);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // JAL — writes pc+4 to rd and jumps to pc+imm
    // ----------------------------------------------------------------
    task automatic test_jal();
        start_test("JAL");
        pipeline_reset();
        emit(i_jal (5'd1, 21'd12));                  // pc=0  r1 = 4, jump to pc=12
        emit(i_addi(5'd2, 5'd0, 12'd99));            // pc=4  (squashed)
        emit(i_addi(5'd2, 5'd0, 12'd99));            // pc=8  (squashed)
        emit(i_addi(5'd3, 5'd0, 12'd55));            // pc=12 r3 = 55 (landing)
        wait_done();
        check("JAL rd",   5'd1, 32'd4);
        check("JAL skip", 5'd2, 32'd0);              // never wrote 99
        check("JAL land", 5'd3, 32'd55);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // JALR — target = rs1 + sext(imm). build target with AUIPC + ADDI so
    // we know the absolute landing pc and the return address.
    // ----------------------------------------------------------------
    task automatic test_jalr();
        start_test("JALR");
        pipeline_reset();
        emit(i_auipc(5'd10, 20'h00000));             // pc=0   r10 = 0
        emit(i_addi (5'd10, 5'd10, 12'd36));         // pc=4   r10 = 36 (forward target)
        emit(i_addi (5'd11, 5'd0, 12'd11));          // pc=8   r11 = 11
        emit(i_jalr (5'd1, 5'd10, 12'd0));           // pc=12  r1 = 16, jump to pc=36
        emit(i_addi (5'd12, 5'd0, 12'd99));          // pc=16  (squashed)
        emit(i_addi (5'd12, 5'd0, 12'd99));          // pc=20  (squashed)
        emit(i_nop  ());                              // pc=24
        emit(i_nop  ());                              // pc=28
        emit(i_nop  ());                              // pc=32
        emit(i_addi (5'd2, 5'd0, 12'd55));           // pc=36  r2 = 55 (landing)
        wait_done();
        check("JALR ra",      5'd1,  32'd16);        // return = pc(JALR)+4
        check("JALR pre",     5'd11, 32'd11);
        check("JALR skip",    5'd12, 32'd0);
        check("JALR land",    5'd2,  32'd55);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // RV32M — MUL: signed lower 32 bits of x*y
    // ----------------------------------------------------------------
    task automatic test_mul();
        start_test("MUL");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd7));             // r1 = 7
        emit(i_addi(5'd2, 5'd0, 12'd6));             // r2 = 6
        emit(i_addi(5'd3, 5'd0, 12'hFFF));           // r3 = -1
        emit(i_lui (5'd4, 20'h80000));               // r4 = 0x80000000 (most-negative)
        emit(i_mul (5'd5, 5'd1, 5'd2));              // 7 * 6
        emit(i_mul (5'd6, 5'd3, 5'd2));              // -1 * 6
        emit(i_mul (5'd7, 5'd3, 5'd3));              // -1 * -1
        emit(i_mul (5'd8, 5'd4, 5'd4));              // most-neg squared (low 32: 0)
        emit(i_mul (5'd9, 5'd0, 5'd1));              // 0 * 7
        wait_done();
        check("MUL 7*6",     5'd5, 32'd42);
        check("MUL -1*6",    5'd6, 32'hFFFFFFFA);
        check("MUL -1*-1",   5'd7, 32'd1);
        check("MUL min*min", 5'd8, 32'd0);
        check("MUL 0*x",     5'd9, 32'd0);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // RV32M — MULH / MULHSU / MULHU: upper 32 bits with various
    // operand signedness
    // ----------------------------------------------------------------
    task automatic test_mulh_variants();
        start_test("MULH / MULHSU / MULHU");
        pipeline_reset();
        emit(i_addi  (5'd1, 5'd0, 12'd6));              // r1 = 6
        emit(i_addi  (5'd2, 5'd0, 12'hFFF));            // r2 = -1
        emit(i_lui   (5'd3, 20'h80000));                // r3 = 0x80000000
        emit(i_mulh  (5'd4, 5'd2, 5'd2));               // (-1)*(-1) = 1, hi = 0
        emit(i_mulh  (5'd5, 5'd3, 5'd3));               // min*min   = 2^62, hi = 0x40000000
        emit(i_mulhu (5'd6, 5'd2, 5'd2));               // maxu*maxu hi = 0xFFFFFFFE
        emit(i_mulhsu(5'd7, 5'd2, 5'd1));               // (-1)signed * 6u, full=0xFFFFFFFA, hi=0xFFFFFFFF
        emit(i_mulhsu(5'd8, 5'd1, 5'd2));               // 6 * 0xFFFFFFFFu, full=0x5FFFFFFFA, hi=5
        wait_done();
        check("MULH   -1*-1",   5'd4, 32'd0);
        check("MULH   min*min", 5'd5, 32'h40000000);
        check("MULHU  max*max", 5'd6, 32'hFFFFFFFE);
        check("MULHSU -1s*6u",  5'd7, 32'hFFFFFFFF);
        check("MULHSU 6s*maxu", 5'd8, 32'd5);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // RV32M — DIV / DIVU
    // ----------------------------------------------------------------
    task automatic test_div_divu();
        start_test("DIV / DIVU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd20));               // r1 = 20
        emit(i_addi(5'd2, 5'd0, 12'd6));                // r2 = 6
        emit(i_addi(5'd3, 5'd0, 12'hFFF));              // r3 = -1
        emit(i_addi(5'd4, 5'd0, 12'hFB4));              // r4 = -76 (12'hFB4 sign-ext)
        emit(i_div (5'd5, 5'd1, 5'd2));                 // 20 / 6 = 3
        emit(i_div (5'd6, 5'd4, 5'd2));                 // -76 / 6 = -12
        emit(i_div (5'd7, 5'd4, 5'd3));                 // -76 / -1 = 76
        emit(i_divu(5'd8, 5'd1, 5'd2));                 // 20u / 6u = 3
        emit(i_divu(5'd9, 5'd3, 5'd2));                 // maxu / 6
        wait_done();
        check("DIV  20/6",      5'd5, 32'd3);
        check("DIV -76/6",      5'd6, 32'hFFFFFFF4); // -12
        check("DIV -76/-1",     5'd7, 32'd76);
        check("DIVU 20/6",      5'd8, 32'd3);
        check("DIVU maxu/6",    5'd9, 32'h2AAAAAAA);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // RV32M — REM / REMU
    // ----------------------------------------------------------------
    task automatic test_rem_remu();
        start_test("REM / REMU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd20));                // r1 = 20
        emit(i_addi(5'd2, 5'd0, 12'd6));                 // r2 = 6
        emit(i_addi(5'd3, 5'd0, 12'hFB4));               // r3 = -76
        emit(i_addi(5'd4, 5'd0, 12'hFFF));               // r4 = -1
        emit(i_rem (5'd5, 5'd1, 5'd2));                  // 20 % 6 = 2
        emit(i_rem (5'd6, 5'd3, 5'd2));                  // -76 % 6 = -4
        emit(i_rem (5'd7, 5'd3, 5'd4));                  // -76 % -1 = 0
        emit(i_remu(5'd8, 5'd1, 5'd2));                  // 20 %u 6 = 2
        emit(i_remu(5'd9, 5'd4, 5'd2));                  // maxu %u 6 = 3
        wait_done();
        check("REM  20%6",   5'd5, 32'd2);
        check("REM -76%6",   5'd6, 32'hFFFFFFFC); // -4
        check("REM -76/-1",  5'd7, 32'd0);
        check("REMU 20%6",   5'd8, 32'd2);
        check("REMU maxu%6", 5'd9, 32'd3);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // RV32M edge cases — divide by zero, signed overflow
    //   DIV   x/0   -> -1
    //   DIVU  x/0   -> 0xFFFFFFFF
    //   REM   x/0   -> x
    //   REMU  x/0   -> x
    //   DIV   INT_MIN/-1 -> INT_MIN  (no trap, no overflow exception)
    //   REM   INT_MIN/-1 -> 0
    // ----------------------------------------------------------------
    task automatic test_mdu_edges();
        start_test("MDU edge cases");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd20));                  // r1 = 20
        emit(i_addi(5'd2, 5'd0, 12'd0));                   // r2 = 0
        emit(i_addi(5'd3, 5'd0, 12'hFFF));                 // r3 = -1
        emit(i_lui (5'd4, 20'h80000));                     // r4 = INT_MIN
        emit(i_div (5'd5, 5'd1, 5'd2));                    // 20 / 0  -> -1
        emit(i_divu(5'd6, 5'd1, 5'd2));                    // 20 /u 0 -> maxu
        emit(i_rem (5'd7, 5'd1, 5'd2));                    // 20 % 0  -> 20
        emit(i_remu(5'd8, 5'd1, 5'd2));                    // 20 %u 0 -> 20
        emit(i_div (5'd9, 5'd4, 5'd3));                    // INT_MIN / -1 -> INT_MIN
        emit(i_rem (5'd10,5'd4, 5'd3));                    // INT_MIN % -1 -> 0
        wait_done();
        check("DIV  x/0",         5'd5,  32'hFFFFFFFF);
        check("DIVU x/0",         5'd6,  32'hFFFFFFFF);
        check("REM  x/0",         5'd7,  32'd20);
        check("REMU x/0",         5'd8,  32'd20);
        check("DIV  INT_MIN/-1",  5'd9,  32'h80000000);
        check("REM  INT_MIN/-1",  5'd10, 32'd0);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // Forwarding — EX/MA and MA/WB to EX, including chained dependencies
    // ----------------------------------------------------------------
    task automatic test_forwarding();
        start_test("Forwarding (EX->EX, MA->EX)");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd10));               // r1 = 10
        emit(i_addi(5'd2, 5'd1, 12'd5));                // r2 = 15  (EX->EX from r1)
        emit(i_add (5'd3, 5'd2, 5'd1));                 // r3 = 25  (EX->EX r2, MA->EX r1)
        emit(i_add (5'd4, 5'd3, 5'd3));                 // r4 = 50  (EX->EX both ops)
        emit(i_addi(5'd5, 5'd0, 12'd3));                // r5 = 3
        emit(i_nop ());                                  // gap
        emit(i_addi(5'd6, 5'd5, 12'd1));                // r6 = 4  (MA->EX)
        // Branch reading forwarded values
        emit(i_addi(5'd7, 5'd0, 12'd99));               // r7 = 99
        emit(i_beq (5'd5, 5'd5, 13'd12));               // r5==r5 -> taken (forwarded)
        emit(i_addi(5'd7, 5'd0, 12'd1));                // squashed
        emit(i_addi(5'd7, 5'd0, 12'd1));                // squashed
        emit(i_addi(5'd8, 5'd0, 12'd77));               // r8 = 77
        wait_done();
        check("FWD EX->EX 1",    5'd2, 32'd15);
        check("FWD EX->EX 2",    5'd3, 32'd25);
        check("FWD EX->EX 3",    5'd4, 32'd50);
        check("FWD MA->EX",      5'd6, 32'd4);
        check("FWD branch op",   5'd7, 32'd99);
        check("FWD land",        5'd8, 32'd77);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // Load-use stall — LW followed immediately by a dependent op must
    // produce the correct value (pipeline inserts a 1-cycle bubble).
    // ----------------------------------------------------------------
    task automatic test_load_use();
        start_test("Load-use stall");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd42));               // r1 = 42
        emit(i_addi(5'd2, 5'd0, 12'h400));              // r2 = 0x400 (base)
        emit(i_sw  (5'd2, 5'd1, 12'd0));                // mem[0x400] = 42
        emit(i_nop ());
        emit(i_nop ());
        emit(i_lw  (5'd3, 5'd2, 12'd0));                // r3 = 42
        emit(i_add (5'd4, 5'd3, 5'd1));                 // r4 = r3+r1 = 84  (load-use)
        // load-use against rs2
        emit(i_lw  (5'd5, 5'd2, 12'd0));                // r5 = 42
        emit(i_sub (5'd6, 5'd1, 5'd5));                 // r6 = r1 - r5 = 0 (load-use rs2)
        wait_done();
        check("LW load-use rs1",  5'd4, 32'd84);
        check("LW load-use rs2",  5'd6, 32'd0);
        check_mem("SW base",      32'h400, 32'd42);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // x0 special — writes to x0 ignored, reads from x0 always 0
    // ----------------------------------------------------------------
    task automatic test_x0();
        start_test("x0 special handling");
        pipeline_reset();
        emit(i_addi(5'd0, 5'd0, 12'd99));               // attempt to write x0 = 99 (must be ignored)
        emit(i_lui (5'd0, 20'hABCDE));                  // attempt LUI x0
        emit(i_add (5'd1, 5'd0, 5'd0));                 // r1 = x0 + x0 = 0
        emit(i_addi(5'd2, 5'd0, 12'd7));                // r2 = 7
        emit(i_sub (5'd3, 5'd0, 5'd2));                 // r3 = 0 - 7 = -7
        emit(i_or  (5'd4, 5'd0, 5'd2));                 // r4 = 0 | 7 = 7
        wait_done();
        check("x0 stays zero",  5'd0, 32'd0);
        check("read x0 is 0",   5'd1, 32'd0);
        check("0 - r2",         5'd3, 32'hFFFFFFF9);
        check("0 | r2",         5'd4, 32'd7);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // MDU -> branch — branch comparator must see the forwarded MDU result.
    // Exercises forwarding from MA/EX into the cond unit.
    // ----------------------------------------------------------------
    task automatic test_mdu_branch();
        start_test("MDU result drives branch");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd5));            // r1 = 5
        emit(i_addi(5'd2, 5'd0, 12'd4));            // r2 = 4
        emit(i_mul (5'd3, 5'd1, 5'd2));             // r3 = 20
        emit(i_addi(5'd4, 5'd0, 12'd20));           // r4 = 20
        emit(i_beq (5'd3, 5'd4, 13'd12));           // r3==r4 -> taken
        emit(i_addi(5'd5, 5'd0, 12'd99));           // squashed
        emit(i_addi(5'd5, 5'd0, 12'd99));           // squashed
        emit(i_addi(5'd5, 5'd0, 12'd1));            // r5 = 1 (landing)
        emit(i_div (5'd6, 5'd3, 5'd1));             // r6 = 20/5 = 4
        emit(i_addi(5'd7, 5'd0, 12'd5));            // r7 = 5
        emit(i_blt (5'd6, 5'd7, 13'd12));           // 4 < 5 -> taken
        emit(i_addi(5'd8, 5'd0, 12'd99));           // squashed
        emit(i_addi(5'd8, 5'd0, 12'd99));           // squashed
        emit(i_addi(5'd8, 5'd0, 12'd2));            // r8 = 2 (landing)
        wait_done();
        check("MUL result",    5'd3, 32'd20);
        check("BEQ on MUL",    5'd5, 32'd1);
        check("DIV result",    5'd6, 32'd4);
        check("BLT on DIV",    5'd8, 32'd2);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // Load-use into MDU — LW result is the MDU operand. The load-use
    // hazard detector must fire even when the consumer is an MDU op.
    // ----------------------------------------------------------------
    task automatic test_mdu_load_use();
        start_test("Load-use into MDU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'h500));          // r1 = 0x500 (base)
        emit(i_addi(5'd2, 5'd0, 12'd7));            // r2 = 7
        emit(i_addi(5'd3, 5'd0, 12'd6));            // r3 = 6
        emit(i_sw  (5'd1, 5'd2, 12'd0));            // mem[0x500] = 7
        emit(i_sw  (5'd1, 5'd3, 12'h004));          // mem[0x504] = 6
        emit(i_nop ());
        emit(i_lw  (5'd4, 5'd1, 12'd0));            // r4 = 7
        emit(i_mul (5'd5, 5'd4, 5'd3));             // r5 = r4*r3 = 42  (load-use rs1)
        emit(i_lw  (5'd6, 5'd1, 12'h004));          // r6 = 6
        emit(i_mul (5'd7, 5'd2, 5'd6));             // r7 = r2*r6 = 42  (load-use rs2)
        emit(i_lw  (5'd8, 5'd1, 12'd0));            // r8 = 7
        emit(i_div (5'd9, 5'd8, 5'd3));             // r9 = 7/6 = 1  (load-use into DIV)
        wait_done();
        check("MUL load-use rs1",  5'd5, 32'd42);
        check("MUL load-use rs2",  5'd7, 32'd42);
        check("DIV load-use rs1",  5'd9, 32'd1);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // JAL/JALR with rd=x0 — link is discarded. x0 must stay zero and
    // the jump itself must still take effect.
    // ----------------------------------------------------------------
    task automatic test_jal_jalr_no_link();
        start_test("JAL/JALR rd=x0 (no link)");
        pipeline_reset();
        emit(i_jal (5'd0, 21'd12));                 // pc=0  jump, discard link
        emit(i_addi(5'd1, 5'd0, 12'd99));           // pc=4  squashed
        emit(i_addi(5'd1, 5'd0, 12'd99));           // pc=8  squashed
        emit(i_addi(5'd1, 5'd0, 12'd7));            // pc=12 r1 = 7 (landing)
        emit(i_auipc(5'd10, 20'h00000));            // pc=16 r10 = 16
        emit(i_addi (5'd10, 5'd10, 12'd24));        // pc=20 r10 = 40 (target)
        emit(i_jalr (5'd0, 5'd10, 12'd0));          // pc=24 jump, discard link
        emit(i_addi (5'd2, 5'd0, 12'd99));          // pc=28 squashed
        emit(i_addi (5'd2, 5'd0, 12'd99));          // pc=32 squashed
        emit(i_addi (5'd2, 5'd0, 12'd0));           // pc=36 nop slot
        emit(i_addi (5'd3, 5'd0, 12'd9));           // pc=40 r3 = 9 (landing)
        wait_done();
        check("JAL  x0 stays 0",  5'd0,  32'd0);
        check("JAL  land r1",     5'd1,  32'd7);
        check("JALR x0 stays 0",  5'd0,  32'd0);
        check("JALR land r3",     5'd3,  32'd9);
        check("JAL  no spurious", 5'd2,  32'd0);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // Shift-amount masking — rs2 lower 5 bits only. rs2 = 32 should be
    // identity (shift by 0); rs2 = 33 should be shift by 1; rs2 = 64
    // also identity. Earlier shift_r test covered 0xFF; this nails the
    // exact wrap point.
    // ----------------------------------------------------------------
    task automatic test_shift_mask();
        start_test("Shift-amount masking");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd1));            // r1 = 1
        emit(i_addi(5'd2, 5'd0, 12'd32));           // r2 = 32 -> shamt = 0
        emit(i_addi(5'd3, 5'd0, 12'd33));           // r3 = 33 -> shamt = 1
        emit(i_addi(5'd4, 5'd0, 12'd64));           // r4 = 64 -> shamt = 0
        emit(i_addi(5'd5, 5'd0, 12'hFFF));          // r5 = -1 -> shamt = 31
        emit(i_sll (5'd10, 5'd1, 5'd2));            // 1 << 0  = 1
        emit(i_sll (5'd11, 5'd1, 5'd3));            // 1 << 1  = 2
        emit(i_sll (5'd12, 5'd1, 5'd4));            // 1 << 0  = 1
        emit(i_sll (5'd13, 5'd1, 5'd5));            // 1 << 31 = 0x80000000
        emit(i_srl (5'd14, 5'd13, 5'd2));           // 0x80000000 >>u 0  = same
        emit(i_sra (5'd15, 5'd13, 5'd5));           // 0x80000000 >>s 31 = -1
        wait_done();
        check("SLL shamt=32 (mask)", 5'd10, 32'd1);
        check("SLL shamt=33 (mask)", 5'd11, 32'd2);
        check("SLL shamt=64 (mask)", 5'd12, 32'd1);
        check("SLL shamt=-1 (mask)", 5'd13, 32'h80000000);
        check("SRL shamt=32 (mask)", 5'd14, 32'h80000000);
        check("SRA shamt=-1 (mask)", 5'd15, 32'hFFFFFFFF);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // Backward JAL — call+return pattern. JAL forward to a "function"
    // which returns via JALR through the link register.
    // ----------------------------------------------------------------
    task automatic test_jal_call_return();
        start_test("JAL/JALR call+return");
        pipeline_reset();
        // pc=0:  jump over the function body to the call site
        emit(i_jal (5'd0, 21'd16));                 // pc=0  jump to pc=16
        // pc=4:  the "function" — multiplies r5 by 2 into r6, returns
        emit(i_slli(5'd6, 5'd5, 5'd1));             // pc=4  r6 = r5 << 1
        emit(i_jalr(5'd0, 5'd1, 12'd0));            // pc=8  return via r1
        emit(i_nop ());                              // pc=12 padding
        // pc=16: call site
        emit(i_addi(5'd5, 5'd0, 12'd21));           // pc=16 r5 = 21
        emit(i_jal (5'd1, 21'h1FFFF0));             // pc=20 call pc=4 (-16), link in r1
        emit(i_addi(5'd7, 5'd6, 12'd0));            // pc=24 r7 = r6 = 42 (after return)
        wait_done();
        check("call result r6",  5'd6, 32'd42);
        check("post-return r7",  5'd7, 32'd42);
        check("link r1 = pc+4",  5'd1, 32'd24);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // Back-to-back MDU — verifies the busy/done handshake fully resets
    // between operations and that EX/MA forwarding bridges them.
    // ----------------------------------------------------------------
    task automatic test_mdu_back_to_back();
        start_test("Back-to-back MDU");
        pipeline_reset();
        emit(i_addi(5'd1, 5'd0, 12'd7));                // r1 = 7
        emit(i_addi(5'd2, 5'd0, 12'd6));                // r2 = 6
        emit(i_mul (5'd3, 5'd1, 5'd2));                 // r3 = 42
        emit(i_mul (5'd4, 5'd3, 5'd1));                 // r4 = r3*7 = 294 (forwards r3)
        emit(i_div (5'd5, 5'd4, 5'd2));                 // r5 = 294 / 6 = 49
        emit(i_mul (5'd6, 5'd5, 5'd5));                 // r6 = 49 * 49 = 2401
        emit(i_addi(5'd7, 5'd6, 12'd1));                // r7 = 2402 (forward from MUL)
        wait_done();
        check("MUL chain 1",  5'd3, 32'd42);
        check("MUL chain 2",  5'd4, 32'd294);
        check("DIV after MUL",5'd5, 32'd49);
        check("MUL squared",  5'd6, 32'd2401);
        check("ADDI after MUL",5'd7, 32'd2402);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // CSR basic round-trip: write a value to mscratch, read it back.
    // exercises EX-stage csr access, old-value-to-rd, write-commit edge.
    // ----------------------------------------------------------------
    task automatic test_csr_basic_rw();
        start_test("CSR basic mscratch");
        pipeline_reset();
        emit(i_addi (5'd1, 5'd0, 12'h7AB));            // r1 = 0x7AB
        emit(i_addi (5'd2, 5'd0, 12'h5A5));            // r2 preload (proves rd write happens)
        emit(i_csrrw(5'd2, 5'd1, A_MSCRATCH));         // mscratch <- r1, r2 <- old (0)
        emit(i_csrrs(5'd3, 5'd0, A_MSCRATCH));         // r3 <- mscratch (pure read)
        emit(i_csrrw(5'd0, 5'd0, A_MSCRATCH));         // mscratch <- 0
        emit(i_addi (5'd4, 5'd0, 12'h5A5));            // r4 preload
        emit(i_csrrs(5'd4, 5'd0, A_MSCRATCH));         // r4 <- mscratch (= 0)
        wait_done();
        check("rd gets old (0)",  5'd2, 32'h0);        // preload 0x5A5 -> 0 proves write
        check("read after write", 5'd3, 32'h7AB);
        check("clear via csrrw",  5'd4, 32'h0);        // preload 0x5A5 -> 0 proves write
        end_test();
    endtask

    // ----------------------------------------------------------------
    // CSRRS / CSRRC bit semantics on mscratch
    // ----------------------------------------------------------------
    task automatic test_csr_set_clear();
        start_test("CSR set/clear bits");
        pipeline_reset();
        emit(i_addi (5'd1, 5'd0, 12'h0FF));            // r1 = 0xFF
        emit(i_csrrw(5'd0, 5'd1, A_MSCRATCH));         // mscratch = 0xFF
        emit(i_addi (5'd2, 5'd0, 12'h7F0));            // r2 = 0x7F0
        emit(i_csrrs(5'd3, 5'd2, A_MSCRATCH));         // mscratch |= 0x7F0; r3 <- 0xFF
        emit(i_addi (5'd4, 5'd0, 12'h00F));            // r4 = 0x00F
        emit(i_csrrc(5'd5, 5'd4, A_MSCRATCH));         // mscratch &= ~0x00F; r5 <- 0x7FF
        emit(i_csrrs(5'd6, 5'd0, A_MSCRATCH));         // r6 <- mscratch
        wait_done();
        check("rs old",  5'd3, 32'h0FF);
        check("rc old",  5'd5, 32'h7FF);
        check("final",   5'd6, 32'h7F0);               // (0xFF|0x7F0) & ~0x00F = 0x7F0
        end_test();
    endtask

    // ----------------------------------------------------------------
    // immediate variants (5-bit uimm in rs1 field)
    // ----------------------------------------------------------------
    task automatic test_csr_imm_variants();
        start_test("CSR imm variants");
        pipeline_reset();
        emit(i_addi (5'd1, 5'd0, 12'h5A5));            // r1 preload (proves rd write)
        emit(i_csrrwi(5'd1, 5'd31, A_MSCRATCH));       // mscratch = 31; r1 <- 0
        emit(i_csrrsi(5'd2, 5'd0,  A_MSCRATCH));       // pure read; mscratch unchanged
        emit(i_csrrci(5'd3, 5'd1,  A_MSCRATCH));       // mscratch &= ~1 (uimm); r3 <- 31
        emit(i_csrrs (5'd4, 5'd0,  A_MSCRATCH));       // r4 <- mscratch (= 30)
        wait_done();
        check("rwi old",  5'd1, 32'h0);                // preload 0x5A5 -> 0 proves write
        check("rsi pure", 5'd2, 32'd31);
        check("rci old",  5'd3, 32'd31);
        check("final",    5'd4, 32'd30);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // pure read of RO and read-only-effectively CSRs (mhartid, misa)
    // must not trap (csrrs with rs1=x0)
    // ----------------------------------------------------------------
    task automatic test_csr_ro();
        start_test("CSR RO pure reads");
        pipeline_reset();
        emit(i_addi (5'd1, 5'd0, 12'h5A5));            // r1 preload (proves rd write)
        emit(i_csrrs(5'd1, 5'd0, A_MHARTID));          // r1 <- mhartid (= 0)
        emit(i_csrrs(5'd2, 5'd0, A_MISA));             // r2 <- misa
        wait_done();
        check("mhartid",  5'd1, 32'h00000000);         // preload 0x5A5 -> 0 proves write
        check("misa",     5'd2, 32'h40001100);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // forwarding: csr_rdata lands in ex_ma.data, then forwards to the
    // next insn's rs1 via the normal ex_ma->id_ex forwarding path.
    // ----------------------------------------------------------------
    task automatic test_csr_forwarding();
        start_test("CSR forward to dependent");
        pipeline_reset();
        emit(i_addi (5'd1, 5'd0, 12'h055));            // r1 = 0x55
        emit(i_csrrw(5'd0, 5'd1, A_MSCRATCH));         // mscratch = 0x55
        emit(i_csrrs(5'd2, 5'd0, A_MSCRATCH));         // r2 <- 0x55
        emit(i_addi (5'd3, 5'd2, 12'd1));              // r3 = r2 + 1 (forwards from CSR)
        wait_done();
        check("forward csr->add", 5'd3, 32'h56);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // trap entry + mret round-trip.
    //   pc 0x000..0x014 : user code (preload r2, trigger illegal CSR at pc=12)
    //   pc 0x200..0x210 : handler, captures mepc, advances by 4, mrets
    //   pc 0x300        : sentinel landing zone (jal here after mret return)
    // r2 is preloaded with 0x5A5 to verify that the trap suppresses the rd
    // write — without the preload, r2==0 either way (since mhartid is 0).
    // ----------------------------------------------------------------
    task automatic test_csr_trap_mret();
        start_test("CSR trap + mret");
        pipeline_reset();

        // user code
        emit(i_addi (5'd1, 5'd0, 12'h200));            // pc=0   r1 = 0x200
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));            // pc=4   mtvec = 0x200
        emit(i_addi (5'd2, 5'd0, 12'h5A5));            // pc=8   r2 preload (must survive trap)
        emit(i_csrrw(5'd2, 5'd1, A_MHARTID));          // pc=12  TRAP (write RO mhartid)
        emit(i_addi (5'd3, 5'd0, 12'd42));             // pc=16  r3 = 42 (after mret)
        emit(i_jal  (5'd0, 21'h2EC));                  // pc=20  jal to pc=0x300

        // pad to handler at pc=0x200
        while (iptr < 32'h80) emit(i_nop());

        // handler
        emit(i_addi (5'd10, 5'd0, 12'h7AA));           // r10 = marker
        emit(i_csrrs(5'd11, 5'd0, A_MEPC));            // r11 = mepc (= 12)
        emit(i_addi (5'd11, 5'd11, 12'd4));            // r11 += 4
        emit(i_csrrw(5'd0,  5'd11, A_MEPC));           // mepc = r11 (= 16)
        emit(i_mret());

        // pad to sentinel zone at pc=0x300
        while (iptr < 32'hC0) emit(i_nop());

        wait_done();
        check("post-mret r3",        5'd3,  32'd42);
        check("handler ran r10",     5'd10, 32'h7AA);
        check("mepc captured + 4",   5'd11, 32'd16);
        check("trap suppressed rd",  5'd2,  32'h5A5);  // preload survives
        end_test();
    endtask

    // ----------------------------------------------------------------
    // illegal-CSR trap drops the faulting instruction word into mtval.
    // csrrw r2, r1, mhartid writes a RO csr -> csr_illegal (cause=2).
    // I-type layout: {csr[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]}
    //   = {12'hF14, 5'd1, 3'b001, 5'd2, 7'b1110011} = 0xF1409173
    // ----------------------------------------------------------------
    task automatic test_csr_tval();
        start_test("CSR illegal: mtval = faulting insn");
        pipeline_reset();

        emit(i_addi (5'd1, 5'd0, 12'h200));            // pc=0   r1 = mtvec base
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));            // pc=4   mtvec = 0x200
        emit(i_csrrw(5'd2, 5'd1, A_MHARTID));          // pc=8   TRAP (write RO)
        emit(i_jal  (5'd0, 21'h2F4));                  // pc=12  jal +0x2F4 -> 0x300

        while (iptr < 32'h80) emit(i_nop());           // pad to handler at pc=0x200
        emit(i_csrrs(5'd11, 5'd0, A_MCAUSE));          // r11 = mcause
        emit(i_csrrs(5'd12, 5'd0, A_MTVAL));           // r12 = mtval
        emit(i_csrrs(5'd13, 5'd0, A_MEPC));            // r13 = mepc (= 8)
        emit(i_addi (5'd13, 5'd13, 12'd4));            // r13 += 4 -> 12
        emit(i_csrrw(5'd0, 5'd13, A_MEPC));            // mepc = 12 (resume past trap)
        emit(i_mret());

        while (iptr < 32'hC0) emit(i_nop());           // pad to sentinel zone at pc=0x300

        wait_done();
        check("illegal cause = 2",     5'd11, 32'd2);
        check("mtval = faulting insn", 5'd12, 32'hF1409173);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // ecall traps with mcause=11 (M-mode environment call), mtval=0.
    // Handler bumps mepc by 4 so mret resumes past the ecall.
    // ----------------------------------------------------------------
    task automatic test_ecall();
        start_test("ECALL trap (cause = 11)");
        pipeline_reset();

        emit(i_addi (5'd1, 5'd0, 12'h200));            // pc=0   r1 = mtvec base
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));            // pc=4   mtvec = 0x200
        emit(i_ecall());                               // pc=8   TRAP -> cause=11
        emit(i_addi (5'd5, 5'd0, 12'd99));             // pc=12  runs after mret
        emit(i_jal  (5'd0, 21'h2F0));                  // pc=16  jal to 0x300

        while (iptr < 32'h80) emit(i_nop());           // pad to handler at pc=0x200
        emit(i_csrrs(5'd11, 5'd0, A_MCAUSE));          // r11 = mcause (= 11)
        emit(i_csrrs(5'd12, 5'd0, A_MTVAL));           // r12 = mtval (= 0)
        emit(i_csrrs(5'd13, 5'd0, A_MEPC));            // r13 = mepc  (= 8)
        emit(i_addi (5'd13, 5'd13, 12'd4));            // r13 += 4    (= 12)
        emit(i_csrrw(5'd0, 5'd13, A_MEPC));            // mepc = 12
        emit(i_mret());

        while (iptr < 32'hC0) emit(i_nop());           // pad to sentinel zone at pc=0x300

        wait_done();
        check("ecall cause = 11",  5'd11, 32'd11);
        check("ecall mtval = 0",   5'd12, 32'd0);
        check("ecall mepc+4 = 12", 5'd13, 32'd12);
        check("post-mret r5",      5'd5,  32'd99);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // ebreak traps with mcause=3 (breakpoint), mtval=0 here.
    // Same resume pattern as ecall.
    // ----------------------------------------------------------------
    task automatic test_ebreak();
        start_test("EBREAK trap (cause = 3)");
        pipeline_reset();

        emit(i_addi (5'd1, 5'd0, 12'h200));            // pc=0
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));            // pc=4   mtvec = 0x200
        emit(i_ebreak());                              // pc=8   TRAP -> cause=3
        emit(i_addi (5'd5, 5'd0, 12'd77));             // pc=12  runs after mret
        emit(i_jal  (5'd0, 21'h2F0));                  // pc=16  jal to 0x300

        while (iptr < 32'h80) emit(i_nop());           // pad to handler at pc=0x200
        emit(i_csrrs(5'd11, 5'd0, A_MCAUSE));          // r11 = mcause (= 3)
        emit(i_csrrs(5'd13, 5'd0, A_MEPC));            // r13 = mepc
        emit(i_addi (5'd13, 5'd13, 12'd4));            // r13 += 4
        emit(i_csrrw(5'd0, 5'd13, A_MEPC));
        emit(i_mret());

        while (iptr < 32'hC0) emit(i_nop());

        wait_done();
        check("ebreak cause = 3",  5'd11, 32'd3);
        check("post-mret r5",      5'd5,  32'd77);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // shared MTI handler body — placed at the iptr matching mtvec_base
    // (direct mode) or mtvec_base + 4*cause (vectored mode).
    //   r10 <- 0x7AA       handler ran
    //   r11 <- mcause      should be 0x80000007 for MTI
    //   *IRQ_CLR_ADDR <- 0 tb drops irq_mti
    //   mret
    // ----------------------------------------------------------------
    task automatic emit_mti_handler();
        emit(i_addi (5'd10, 5'd0, 12'h7AA));
        emit(i_csrrs(5'd11, 5'd0, A_MCAUSE));
        emit(i_lui  (5'd12, 20'h10000));
        emit(i_sw   (5'd12, 5'd0, 12'd0));
        emit(i_nop());
        emit(i_nop());
        emit(i_mret());
    endtask

    // ----------------------------------------------------------------
    // irq direct mode: mtvec base only (mode=0), MTI source.
    // mepc lands on the first insn AFTER the csrrw that enabled MIE,
    // so r4..r6 are written when mret resumes the user code.
    // ----------------------------------------------------------------
    task automatic test_irq_direct();
        start_test("IRQ: MTI direct mode");
        pipeline_reset();

        emit(i_addi (5'd1, 5'd0, 12'h200));            // pc=0   r1 = mtvec base
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));            // pc=4   mtvec = 0x200 (direct)
        emit(i_addi (5'd1, 5'd0, 12'h080));            // pc=8   MTIE bit
        emit(i_csrrw(5'd0, 5'd1, A_MIE));              // pc=12  mie = MTIE
        emit(i_addi (5'd1, 5'd0, 12'h008));            // pc=16  MIE bit
        emit(i_csrrw(5'd0, 5'd1, A_MSTATUS));          // pc=20  mstatus.MIE = 1 -> trap next cycle
        emit(i_addi (5'd4, 5'd0, 12'h123));            // pc=24  squashed; reruns after mret
        emit(i_addi (5'd5, 5'd0, 12'h456));            // pc=28
        emit(i_addi (5'd6, 5'd0, 12'h789));            // pc=32
        emit(i_jal  (5'd0, 21'h2D8));                  // pc=36  jal +0x2D8 -> 0x300

        while (iptr < 32'h80) emit(i_nop());           // pad to handler at pc=0x200
        emit_mti_handler();
        while (iptr < 32'hC0) emit(i_nop());           // pad to sentinel zone at pc=0x300

        irq_mti = 1;                                   // pending before MIE is enabled
        wait_done();
        check("r4 ran post-mret",  5'd4,  32'h123);
        check("r5 ran post-mret",  5'd5,  32'h456);
        check("r6 ran post-mret",  5'd6,  32'h789);
        check("handler marker",    5'd10, 32'h7AA);
        check("mcause = mti",      5'd11, 32'h8000_0007);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // irq vectored mode: mtvec[0]=1, target = base + 4*cause.
    // For MTI (cause=7) -> base + 28 = 0x21C, so the handler lives there.
    // ----------------------------------------------------------------
    task automatic test_irq_vectored();
        start_test("IRQ: MTI vectored mode");
        pipeline_reset();

        emit(i_addi (5'd1, 5'd0, 12'h201));            // pc=0   mtvec base | vectored bit
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));            // pc=4   mtvec = 0x201
        emit(i_addi (5'd1, 5'd0, 12'h080));            // pc=8
        emit(i_csrrw(5'd0, 5'd1, A_MIE));              // pc=12  mie = MTIE
        emit(i_addi (5'd1, 5'd0, 12'h008));            // pc=16
        emit(i_csrrw(5'd0, 5'd1, A_MSTATUS));          // pc=20  MIE=1 -> trap next cycle
        emit(i_addi (5'd4, 5'd0, 12'h123));            // pc=24  squashed; reruns after mret
        emit(i_addi (5'd5, 5'd0, 12'h456));            // pc=28
        emit(i_addi (5'd6, 5'd0, 12'h789));            // pc=32
        emit(i_jal  (5'd0, 21'h2D8));                  // pc=36  jal to 0x300

        while (iptr < 32'h80) emit(i_nop());           // pad to mtvec base at pc=0x200
        emit(i_jal  (5'd0, 21'h0));                    // pc=0x200 jal-to-self traps direct misroute
        while (iptr < 32'h87) emit(i_nop());           // pad to vector slot 7 at pc=0x21C
        emit_mti_handler();
        while (iptr < 32'hC0) emit(i_nop());

        irq_mti = 1;
        wait_done();
        check("r4 ran post-mret",  5'd4,  32'h123);
        check("r5 ran post-mret",  5'd5,  32'h456);
        check("r6 ran post-mret",  5'd6,  32'h789);
        check("handler marker",    5'd10, 32'h7AA);
        check("mcause = mti",      5'd11, 32'h8000_0007);
        end_test();
    endtask

    // ----------------------------------------------------------------
    // mstatus.MIE=0 gates ALL interrupts even with mie.MTIE=1 and irq high.
    // Program should fall through to sentinel without ever taking a trap;
    // r10 stays 0 because the handler never runs.
    // ----------------------------------------------------------------
    task automatic test_irq_mie_gated();
        start_test("IRQ: MIE=0 masks");
        pipeline_reset();

        emit(i_addi (5'd1, 5'd0, 12'h200));
        emit(i_csrrw(5'd0, 5'd1, A_MTVEC));            // mtvec = 0x200
        emit(i_addi (5'd1, 5'd0, 12'h080));
        emit(i_csrrw(5'd0, 5'd1, A_MIE));              // mie = MTIE; mstatus.MIE intentionally 0
        emit(i_addi (5'd4, 5'd0, 12'h123));
        emit(i_addi (5'd5, 5'd0, 12'h456));
        emit(i_addi (5'd6, 5'd0, 12'h789));

        irq_mti = 1;
        wait_done();
        check("r4 ran",            5'd4,  32'h123);
        check("r5 ran",            5'd5,  32'h456);
        check("r6 ran",            5'd6,  32'h789);
        check("handler suppressed",5'd10, 32'h0);
        irq_mti = 0;                                   // drop so later tests start clean
        end_test();
    endtask

    // ================================================================
    // summary
    // ================================================================
    task automatic summary();
        $display("");
        $display("================================================");
        $display("  TOTAL PASSED : %0d", pass_count);
        $display("  TOTAL FAILED : %0d", fail_count);
        $display("================================================");
        if (fail_count == 0) $display("  ALL TESTS PASSED");
        else                 $display("  *** FAILURES DETECTED ***");
        $display("================================================");
    endtask

    // ================================================================
    // main
    // ================================================================
    initial begin
        $display("=========================================");
        $display("  RV32IM functional testbench");
        $display("=========================================");

        // upper immediates and PC-relative
        test_lui();
        test_auipc();

        // arithmetic-immediate
        test_addi();
        test_slti_sltiu();
        test_logical_i();
        test_shift_i();

        // arithmetic-register
        test_add_sub();
        test_logical_r();
        test_shift_r();
        test_slt_r();

        // memory
        test_lw_sw();
        test_lh_sh_lhu();
        test_lb_sb_lbu();

        // control flow
        test_beq_bne();
        test_blt_bge();
        test_bltu_bgeu();
        test_branch_backward();
        test_jal();
        test_jalr();

        // M-extension
        test_mul();
        test_mulh_variants();
        test_div_divu();
        test_rem_remu();
        test_mdu_edges();

        // hazards / forwarding
        test_forwarding();
        test_load_use();
        test_x0();
        test_mdu_back_to_back();

        // cross-feature interactions
        test_mdu_branch();
        test_mdu_load_use();
        test_jal_jalr_no_link();
        test_shift_mask();
        test_jal_call_return();

        // CSR + trap
        test_csr_basic_rw();
        test_csr_set_clear();
        test_csr_imm_variants();
        test_csr_ro();
        test_csr_forwarding();
        test_csr_trap_mret();
        test_csr_tval();
        test_ecall();
        test_ebreak();

        // interrupts
        test_irq_direct();
        test_irq_vectored();
        test_irq_mie_gated();

        summary();
        $finish;
    end

endmodule
