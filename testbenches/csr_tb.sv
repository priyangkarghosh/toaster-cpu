`timescale 1ns/10ps

import riscv_pkg::*;

module csr_tb;

localparam PERIOD = 10;

logic clk, reset;
logic        csr_en;
csr_op_t     csr_op;
logic [11:0] csr_addr;
logic [31:0] csr_wdata;
logic        csr_wmask;
logic [31:0] csr_rdata;
logic        csr_illegal;

logic irq_msi, irq_mti, irq_mei;

logic        trap_en;
logic [31:0] trap_pc, trap_cause, trap_tval;
logic        mret_en;

logic [31:0] mstatus_o, mtvec_o, mepc_o, mie_o, mip_o;
logic        irq_en;
logic [31:0] irq_cause;

logic passed;

// captured by do_csr for later checks
logic [31:0] last_rdata;
logic        last_illegal;

csr dut (
    .clk        (clk),
    .reset      (reset),
    .csr_en     (csr_en),
    .csr_op     (csr_op),
    .csr_addr   (csr_addr),
    .csr_wdata  (csr_wdata),
    .csr_wmask  (csr_wmask),
    .csr_rdata  (csr_rdata),
    .csr_illegal(csr_illegal),
    .trap_en    (trap_en),
    .trap_pc    (trap_pc),
    .trap_cause (trap_cause),
    .trap_tval  (trap_tval),
    .mret_en    (mret_en),
    .irq_msi    (irq_msi),
    .irq_mti    (irq_mti),
    .irq_mei    (irq_mei),
    .mstatus_o  (mstatus_o),
    .mtvec_o    (mtvec_o),
    .mepc_o     (mepc_o),
    .mie_o      (mie_o),
    .mip_o      (mip_o),
    .irq_en     (irq_en),
    .irq_cause  (irq_cause)
);

always #(PERIOD / 2) clk = ~clk;

// addresses (mirror of dut)
localparam logic [11:0] A_MVENDORID = 12'hF11;
localparam logic [11:0] A_MARCHID   = 12'hF12;
localparam logic [11:0] A_MIMPID    = 12'hF13;
localparam logic [11:0] A_MHARTID   = 12'hF14;
localparam logic [11:0] A_MISA      = 12'h301;
localparam logic [11:0] A_MSTATUS   = 12'h300;
localparam logic [11:0] A_MIE       = 12'h304;
localparam logic [11:0] A_MTVEC     = 12'h305;
localparam logic [11:0] A_MSCRATCH  = 12'h340;
localparam logic [11:0] A_MEPC      = 12'h341;
localparam logic [11:0] A_MCAUSE    = 12'h342;
localparam logic [11:0] A_MTVAL     = 12'h343;
localparam logic [11:0] A_MIP       = 12'h344;
localparam logic [11:0] A_BAD       = 12'hFFF;

// drive one csr op for one clk; samples rdata/illegal mid-cycle
task automatic do_csr(
    input csr_op_t      op,
    input logic [11:0]  addr,
    input logic [31:0]  wdata,
    input logic         wmask
);
    @(posedge clk); #1;
    csr_en    = 1'b1;
    csr_op    = op;
    csr_addr  = addr;
    csr_wdata = wdata;
    csr_wmask = wmask;
    @(negedge clk);            // combinational outputs stable
    last_rdata   = csr_rdata;
    last_illegal = csr_illegal;
    @(posedge clk); #1;        // commit edge
    csr_en    = 1'b0;
    csr_wmask = 1'b0;
endtask

// pure read via csrrs rs1=x0 — never traps a valid RO
task automatic peek(
    input logic [11:0] addr,
    input logic [31:0] expected,
    input string       name
);
    do_csr(CSR_RS, addr, 32'd0, 1'b0);
    if (last_rdata !== expected) begin
        passed = 1'b0;
        $display("FAIL [%s] rdata=%h exp=%h", name, last_rdata, expected);
    end else if (last_illegal !== 1'b0) begin
        passed = 1'b0;
        $display("FAIL [%s] illegal=1 (peek should not trap)", name);
    end else begin
        $display("PASS [%s] rdata=%h", name, last_rdata);
    end
endtask

task automatic check_rdata(input logic [31:0] expected, input string name);
    if (last_rdata !== expected) begin
        passed = 1'b0;
        $display("FAIL [%s] rdata=%h exp=%h", name, last_rdata, expected);
    end else begin
        $display("PASS [%s] rdata=%h", name, last_rdata);
    end
endtask

// sample combinational irq outputs after irq lines / mie / mstatus stabilize
task automatic check_irq(input logic exp_take, input logic [31:0] exp_cause, input string name);
    @(negedge clk);
    if (irq_en !== exp_take) begin
        passed = 1'b0;
        $display("FAIL [%s] irq_en=%b exp=%b", name, irq_en, exp_take);
    end else if (exp_take && irq_cause !== exp_cause) begin
        passed = 1'b0;
        $display("FAIL [%s] cause=%h exp=%h", name, irq_cause, exp_cause);
    end else begin
        $display("PASS [%s] irq_en=%b cause=%h", name, irq_en, irq_cause);
    end
endtask

task automatic check_illegal(input logic expected, input string name);
    if (last_illegal !== expected) begin
        passed = 1'b0;
        $display("FAIL [%s] illegal=%b exp=%b", name, last_illegal, expected);
    end else begin
        $display("PASS [%s] illegal=%b", name, last_illegal);
    end
endtask

task automatic do_reset;
    @(posedge clk); #1;
    reset      = 1'b1;
    csr_en     = 1'b0;
    csr_op     = CSR_RW;
    csr_addr   = '0;
    csr_wdata  = '0;
    csr_wmask  = 1'b0;
    trap_en    = 1'b0;
    trap_pc    = '0;
    trap_cause = '0;
    trap_tval  = '0;
    mret_en    = 1'b0;
    irq_msi    = 1'b0;
    irq_mti    = 1'b0;
    irq_mei    = 1'b0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    reset = 1'b0;
endtask

task automatic do_mret;
    @(posedge clk); #1;
    mret_en = 1'b1;
    @(posedge clk); #1;
    mret_en = 1'b0;
endtask

task automatic do_trap(
    input logic [31:0] pc,
    input logic [31:0] cause,
    input logic [31:0] tval
);
    @(posedge clk); #1;
    trap_en    = 1'b1;
    trap_pc    = pc;
    trap_cause = cause;
    trap_tval  = tval;
    @(posedge clk); #1;
    trap_en    = 1'b0;
    trap_pc    = '0;
    trap_cause = '0;
    trap_tval  = '0;
endtask

initial begin
    clk    = 0;
    passed = 1;

    do_reset();

    // reset values
    $display("\n-- reset values --");
    peek(A_MSTATUS,  32'h0000_1800, "mstatus reset");   // MPP=11
    peek(A_MISA,     32'h4000_1100, "misa reset");      // mxl=01, M, I
    peek(A_MSCRATCH, 32'h0000_0000, "mscratch reset");
    peek(A_MTVEC,    32'h0000_0000, "mtvec reset");
    peek(A_MIE,      32'h0000_0000, "mie reset");
    peek(A_MEPC,     32'h0000_0000, "mepc reset");
    peek(A_MCAUSE,   32'h0000_0000, "mcause reset");
    peek(A_MTVAL,    32'h0000_0000, "mtval reset");
    peek(A_MHARTID,  32'h0000_0000, "mhartid reset");
    peek(A_MVENDORID,32'h0000_0000, "mvendorid reset");

    // mscratch round-trip
    $display("\n-- mscratch round-trip --");
    do_csr(CSR_RW, A_MSCRATCH, 32'hDEAD_BEEF, 1'b1);
    check_rdata(32'h0000_0000, "csrrw mscratch old");
    check_illegal(1'b0,        "csrrw mscratch trap");
    peek(A_MSCRATCH, 32'hDEAD_BEEF, "mscratch after write");

    // csrrs bit-set
    $display("\n-- csrrs/csrrc on mscratch --");
    do_csr(CSR_RW, A_MSCRATCH, 32'h0000_FFFF, 1'b1);
    do_csr(CSR_RS, A_MSCRATCH, 32'h00FF_0000, 1'b1);
    check_rdata(32'h0000_FFFF, "csrrs old");
    peek(A_MSCRATCH, 32'h00FF_FFFF, "csrrs result");

    // csrrc bit-clear
    do_csr(CSR_RW, A_MSCRATCH, 32'hFFFF_FFFF, 1'b1);
    do_csr(CSR_RC, A_MSCRATCH, 32'h0000_FF00, 1'b1);
    check_rdata(32'hFFFF_FFFF, "csrrc old");
    peek(A_MSCRATCH, 32'hFFFF_00FF, "csrrc result");

    // mstatus WARL: only bits 3 and 7 writeable, MPP must stay 11
    $display("\n-- mstatus WARL --");
    do_csr(CSR_RW, A_MSTATUS, 32'hFFFF_FFFF, 1'b1);
    peek(A_MSTATUS, 32'h0000_1888, "mstatus warl (MIE+MPIE set, MPP preserved)");

    // mie WARL: only bits 3/7/11
    $display("\n-- mie WARL --");
    do_csr(CSR_RW, A_MIE, 32'hFFFF_FFFF, 1'b1);
    peek(A_MIE, 32'h0000_0888, "mie warl");

    // mtvec WARL: bit 1 reserved at 0
    $display("\n-- mtvec WARL --");
    do_csr(CSR_RW, A_MTVEC, 32'hFFFF_FFFF, 1'b1);
    peek(A_MTVEC, 32'hFFFF_FFFD, "mtvec warl bit1=0");
    do_csr(CSR_RW, A_MTVEC, 32'h1234_5678, 1'b1);
    peek(A_MTVEC, 32'h1234_5678, "mtvec aligned write");

    // mepc WARL: low 2 bits forced 0
    $display("\n-- mepc WARL --");
    do_csr(CSR_RW, A_MEPC, 32'hFFFF_FFFF, 1'b1);
    peek(A_MEPC, 32'hFFFF_FFFC, "mepc warl low2=0");
    do_csr(CSR_RW, A_MEPC, 32'h1234_5678, 1'b1);
    peek(A_MEPC, 32'h1234_5678, "mepc aligned");
    do_csr(CSR_RW, A_MEPC, 32'h1234_5679, 1'b1);
    peek(A_MEPC, 32'h1234_5678, "mepc unalign trimmed");

    // mhartid RO — pure read OK, real write traps
    $display("\n-- mhartid RO --");
    do_csr(CSR_RS, A_MHARTID, 32'h0, 1'b0);   // pure read
    check_rdata(32'h0000_0000, "mhartid read");
    check_illegal(1'b0,        "mhartid pure-read no trap");

    do_csr(CSR_RS, A_MHARTID, 32'h1, 1'b1);   // attempted set bit 0
    check_illegal(1'b1, "mhartid csrrs nonzero traps");

    do_csr(CSR_RW, A_MHARTID, 32'h1, 1'b1);
    check_illegal(1'b1, "mhartid csrrw traps");

    peek(A_MHARTID, 32'h0, "mhartid unchanged");

    // unknown address — both reads and writes trap
    $display("\n-- unknown addr --");
    do_csr(CSR_RS, A_BAD, 32'h0, 1'b0);
    check_illegal(1'b1, "unknown addr pure-read traps");

    do_csr(CSR_RW, A_BAD, 32'hAA, 1'b1);
    check_illegal(1'b1, "unknown addr write traps");

    // mip from irq wires
    $display("\n-- mip from irq wires --");
    irq_msi = 1; irq_mti = 0; irq_mei = 0;
    peek(A_MIP, 32'h0000_0008, "mip msi");

    irq_msi = 0; irq_mti = 1; irq_mei = 0;
    peek(A_MIP, 32'h0000_0080, "mip mti");

    irq_msi = 0; irq_mti = 0; irq_mei = 1;
    peek(A_MIP, 32'h0000_0800, "mip mei");

    irq_msi = 1; irq_mti = 1; irq_mei = 1;
    peek(A_MIP, 32'h0000_0888, "mip all");

    irq_msi = 0; irq_mti = 0; irq_mei = 0;

    // mip writes silently ignored
    $display("\n-- mip write ignored --");
    do_csr(CSR_RW, A_MIP, 32'hFFFF_FFFF, 1'b1);
    check_illegal(1'b0, "mip write no trap");
    peek(A_MIP, 32'h0000_0000, "mip still wire-driven");

    // misa write ignored, no trap (WARL no-op)
    $display("\n-- misa write ignored --");
    do_csr(CSR_RW, A_MISA, 32'h0, 1'b1);
    check_illegal(1'b0, "misa write no trap");
    peek(A_MISA, 32'h4000_1100, "misa unchanged");

    // csr_en=0 gates everything (no trap on RO addr if not enabled)
    $display("\n-- csr_en=0 gates --");
    @(posedge clk); #1;
    csr_en    = 1'b0;
    csr_op    = CSR_RW;
    csr_addr  = A_MHARTID;
    csr_wdata = 32'hDEAD;
    csr_wmask = 1'b1;
    @(negedge clk);
    if (csr_illegal !== 1'b0) begin
        passed = 0;
        $display("FAIL [gate] illegal=1 with csr_en=0");
    end else begin
        $display("PASS [gate] csr_en=0 suppresses trap");
    end
    @(posedge clk); #1;
    csr_wmask = 1'b0;
    peek(A_MHARTID, 32'h0, "mhartid still 0 after gated attempt");

    // mscratch survives across mstatus write (regs independent)
    $display("\n-- independence sanity --");
    do_csr(CSR_RW, A_MSCRATCH, 32'h1234_5678, 1'b1);
    do_csr(CSR_RW, A_MSTATUS,  32'h0000_0000, 1'b1);
    peek(A_MSCRATCH, 32'h1234_5678, "mscratch unaffected");

    // trap entry: from MIE=1, expect MIE->0, MPIE->1
    $display("\n-- trap entry --");
    do_csr(CSR_RW, A_MSTATUS, 32'h0000_0008, 1'b1);   // set MIE
    peek(A_MSTATUS, 32'h0000_1808, "mstatus MIE=1 before trap");
    do_trap(32'hDEAD_BEEF, 32'd2, 32'h1234_5678);
    peek(A_MEPC,    32'hDEAD_BEEC, "mepc captured (low-2 trimmed)");
    peek(A_MCAUSE,  32'h0000_0002, "mcause = illegal");
    peek(A_MTVAL,   32'h1234_5678, "mtval captured");
    peek(A_MSTATUS, 32'h0000_1880, "mstatus MIE->0 MPIE<-old MIE");

    // trap entry with MIE=0 should propagate MPIE=0
    do_csr(CSR_RW, A_MSTATUS, 32'h0000_0000, 1'b1);   // clear MIE
    peek(A_MSTATUS, 32'h0000_1800, "mstatus cleared back");
    do_trap(32'h0000_0040, 32'd11, 32'd0);
    peek(A_MEPC,    32'h0000_0040, "mepc 2nd trap");
    peek(A_MCAUSE,  32'h0000_000B, "mcause = ext-int");
    peek(A_MSTATUS, 32'h0000_1800, "mstatus MPIE<-0 (MIE was 0)");

    // mret round-trip: trap from MIE=1, mret restores it
    $display("\n-- mret round-trip --");
    do_csr(CSR_RW, A_MSTATUS, 32'h0000_0008, 1'b1);   // MIE=1
    do_trap(32'h0000_1000, 32'd2, 32'd0);
    peek(A_MSTATUS, 32'h0000_1880, "after trap: MIE=0 MPIE=1");
    do_mret();
    peek(A_MSTATUS, 32'h0000_1888, "after mret: MIE=1 MPIE=1");

    // mret from MIE=0/MPIE=0 keeps MIE=0, sets MPIE=1
    do_csr(CSR_RW, A_MSTATUS, 32'h0000_0000, 1'b1);   // clear
    peek(A_MSTATUS, 32'h0000_1800, "mstatus cleared");
    do_mret();
    peek(A_MSTATUS, 32'h0000_1880, "mret from 0/0: MIE=0 MPIE=1");

    // irq_en priority + gating
    $display("\n-- irq_en gating + priority --");
    do_csr(CSR_RW, A_MSTATUS, 32'h0000_0000, 1'b1);   // clear MIE
    do_csr(CSR_RW, A_MIE,     32'h0000_0888, 1'b1);   // enable all 3
    irq_msi = 1; irq_mti = 1; irq_mei = 1;
    check_irq(1'b0, 32'd0, "MIE=0 masks all");

    do_csr(CSR_RW, A_MSTATUS, 32'h0000_0008, 1'b1);   // MIE=1
    check_irq(1'b1, 32'h8000_000B, "all pending: mei wins");

    irq_mei = 0;
    check_irq(1'b1, 32'h8000_0003, "mti+msi pending: msi wins");

    irq_msi = 0;
    check_irq(1'b1, 32'h8000_0007, "only mti pending");

    irq_mti = 0;
    check_irq(1'b0, 32'd0, "no sources -> idle");

    // mie bit-level masking
    do_csr(CSR_RW, A_MIE, 32'h0000_0080, 1'b1);       // only MTIE
    irq_mti = 1; irq_mei = 1;
    check_irq(1'b1, 32'h8000_0007, "mei pending but MEIE=0 -> mti");
    irq_mti = 0; irq_mei = 0;

    // restore MIE/mstatus to known
    do_csr(CSR_RW, A_MSTATUS, 32'h0000_0000, 1'b1);
    do_csr(CSR_RW, A_MIE,     32'h0000_0000, 1'b1);

    $display("\n========================================");
    if (passed) $display(" ALL TESTS PASSED");
    else        $display(" *** FAILURES DETECTED ***");
    $display("========================================");
    $stop;
end

initial begin
    #(PERIOD * 5000);
    $display("WATCHDOG: csr_tb hung at %0t ns", $time);
    $stop;
end

endmodule
