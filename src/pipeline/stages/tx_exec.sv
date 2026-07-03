import riscv_pkg::*;

module tx_exec (
    input clk, reset, en, bubble, load_use,

    // inputs from prev stage
    input id_ex_t id_ex,
    input logic [31:0] fwd_rr1,
    input logic [31:0] fwd_rr2,

    // m-mode interrupt-pending wires
    input logic irq_msi,
    input logic irq_mti,
    input logic irq_mei,

    // redirect + trap entry
    output logic [31:0] pc_target,
    output logic pc_en,
    output logic trap_en,

    // output signals
    output ex_busy,

    // outputs to next stage
    output ex_ma_t ex_ma
);
    // side effects (redirect/trap/csr/mret/mdu) only fire on a cycle the
    // instruction can advance, else held instructions re-fire them
    wire ex_commit = en & ~load_use;

    // alu
    wire [31:0] alu_x = id_ex.use_pc ? id_ex.pc : fwd_rr1;
    wire [31:0] alu_y = id_ex.use_imm ? id_ex.imm : fwd_rr2;
    logic [31:0] alu_out;
    alu u_alu (
        .x(alu_x),
        .y(alu_y),
        .select(id_ex.alu_op),
        .z(alu_out)
    );

    // mdu: starting pulses the cycle an op is accepted
    logic [31:0] mdu_out;
    logic mdu_busy, mdu_valid_out;
    wire mdu_starting = id_ex.mdu_en & ex_commit & ~mdu_busy & ~mdu_valid_out;
    mdu u_mdu (
        .clk(clk),
        .reset(reset),
        .valid_in(mdu_starting),
        .busy(mdu_busy),
        .valid_out(mdu_valid_out),
        .x(fwd_rr1),
        .y(fwd_rr2),
        .select(id_ex.mdu_op),
        .z(mdu_out)
    );
    // OR in mdu_starting so the pipeline freezes the same cycle the op is accepted
    assign ex_busy = mdu_busy | mdu_starting;

    // branch condition
    logic cond_ff;
    cond u_cond (
        .rr1(fwd_rr1),
        .rr2(fwd_rr2),
        .br_type(id_ex.br_type),
        .cond_ff(cond_ff)
    );

    // csr write operands
    wire [31:0] csr_wdata = id_ex.use_imm ? {27'd0, id_ex.rs1} : fwd_rr1;
    wire csr_wmask = (id_ex.csr_op == CSR_RW) || (id_ex.rs1 != 5'd0);

    // only take irq when EX holds a real instruction
    logic irq_en;
    logic [31:0] irq_cause;
    wire irq_taken = irq_en & id_ex.valid;

    // fold EX-detected csr_illegal into the incoming exc tag
    logic csr_illegal;
    exc_t ex_exc;
    assign ex_exc.valid = id_ex.exc.valid | csr_illegal;
    assign ex_exc.cause = id_ex.exc.valid ? id_ex.exc.cause : EXC_ILLEGAL;
    assign ex_exc.tval  = id_ex.exc.valid ? id_ex.exc.tval  : id_ex.ir;

    wire [31:0] trap_cause_w = ex_exc.valid ? {28'd0, ex_exc.cause} : irq_cause;
    wire [31:0] trap_tval_w = ex_exc.valid ? ex_exc.tval : 32'd0;
    // en not ex_commit: traps may fire during a load-use stall, never mid-bus-transaction
    assign trap_en = (ex_exc.valid | irq_taken) & en;

    logic [31:0] csr_rdata, mtvec_w, mepc_w;
    csr u_csr (
        .clk(clk),
        .reset(reset),
        .csr_en(id_ex.csr_en & ex_commit),
        .csr_op(id_ex.csr_op),
        .csr_addr(id_ex.imm[11:0]),
        .csr_wdata(csr_wdata),
        .csr_wmask(csr_wmask),
        .csr_rdata(csr_rdata),
        .csr_illegal(csr_illegal),
        .trap_en(trap_en),
        .trap_pc(id_ex.pc),
        .trap_cause(trap_cause_w),
        .trap_tval(trap_tval_w),
        .mret_en(id_ex.mret_en & ex_commit),
        .irq_msi(irq_msi),
        .irq_mti(irq_mti),
        .irq_mei(irq_mei),
        .mstatus_o(),
        .mtvec_o(mtvec_w),
        .mepc_o(mepc_w),
        .mie_o(),
        .mip_o(),
        .irq_en(irq_en),
        .irq_cause(irq_cause)
    );

    // vectored mtvec: only interrupts get an offset; exceptions always to base
    wire [31:0] mtvec_base = {mtvec_w[31:2], 2'b00};
    wire [31:0] vec_offset = (irq_taken & ~ex_exc.valid & mtvec_w[0]) ? {26'd0, irq_cause[3:0], 2'b00} : 32'd0;

    // trap > mret > branch
    assign pc_en = ((id_ex.jal_en | (id_ex.branch_en & cond_ff) | id_ex.mret_en) & ex_commit) | trap_en;
    assign pc_target = trap_en ? (mtvec_base + vec_offset) :
                       id_ex.mret_en ? mepc_w :
                       {alu_out[31:1], 1'b0};

    // stage result
    wire [31:0] exec = id_ex.jal_en ? id_ex.pc + 32'd4 :
                       id_ex.mdu_en ? mdu_out :
                       id_ex.csr_en ? csr_rdata :
                       alu_out;

    always_ff @(posedge clk) begin
        if (reset | bubble) begin
            ex_ma <= '0;
        end

        else if (en) begin
            ex_ma.valid <= id_ex.valid;
            ex_ma.exc <= ex_exc;
            ex_ma.pc <= id_ex.pc;
            ex_ma.mem_width <= id_ex.mem_width;
            ex_ma.data <= exec;
            ex_ma.rr2 <= fwd_rr2;
            ex_ma.rd <= id_ex.rd;
            ex_ma.rf_en <= id_ex.rf_en;
            ex_ma.load_en <= id_ex.load_en;
            ex_ma.store_en <= id_ex.store_en;
        end
    end
endmodule
