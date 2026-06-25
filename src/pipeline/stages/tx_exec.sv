import riscv_pkg::*;

module tx_exec (
    input clk, reset, bubble, load_use,

    // output signals
    output exec_busy,

    // inputs
    input id_ex_t id_ex,
    input logic [31:0] fwd_rr1,
    input logic [31:0] fwd_rr2,

    // interrupt-pending wires
    input logic irq_msi,
    input logic irq_mti,
    input logic irq_mei,

    // branch/jump outputs
    output logic [31:0] pc_target,
    output logic pc_en,

    // trap entry
    output logic trap_en,

    // latched output
    output ex_ma_t ex_ma
);
    // wire alu
    logic [31:0] alu_x, alu_y, alu_out;
    assign alu_x = id_ex.use_pc ? id_ex.pc : fwd_rr1;
    assign alu_y = id_ex.use_imm ? id_ex.imm : fwd_rr2;
    alu inst_alu (
        .x(alu_x),
        .y(alu_y),
        .select(id_ex.alu_op),
        .z(alu_out)
    );

    // wire mdu
    logic [31:0] mdu_out;
    logic mdu_busy, mdu_valid_out;

    // pulses the cycle an mdu op is accepted
    wire mdu_starting = id_ex.mdu_en & ~load_use & ~mdu_busy & ~mdu_valid_out;
    mdu inst_mdu (
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
    // OR when mdu_starting so the pipeline freezes the same cycle the op is
    assign exec_busy = mdu_busy | mdu_starting;

    // branch conditionals
    logic cond_ff;
    cond inst_cond (
        .rr1(fwd_rr1),
        .rr2(fwd_rr2),
        .br_type(id_ex.br_type),
        .cond_ff(cond_ff)
    );
    
    // wire csr
    logic csr_illegal, irq_en;
    logic [31:0] csr_rdata, mtvec_w, mepc_w, irq_cause;
    wire [31:0] csr_wdata = id_ex.use_imm ? {27'd0, id_ex.rs1} : fwd_rr1;
    wire csr_wmask = (id_ex.csr_op == CSR_RW) || (id_ex.rs1 != 5'd0);

    // only take irq when EX holds a real instruction
    wire irq_taken = irq_en & id_ex.valid;

    // sync exceptions: csr_illegal > ebreak > ecall. interrupts deferred behind them
    wire exc_pending = csr_illegal | id_ex.ebreak_en | id_ex.ecall_en;
    wire [31:0] exc_cause = csr_illegal ? 32'd2 :
                            id_ex.ebreak_en ? 32'd3 :
                            32'd11;
    
    wire [31:0] trap_cause_w = exc_pending ? exc_cause : irq_cause;
    wire [31:0] trap_tval_w = csr_illegal ? id_ex.ir : 32'd0;
    assign trap_en = exc_pending | irq_taken;

    csr inst_csr (
        .clk(clk),
        .reset(reset),
        .csr_en(id_ex.csr_en),
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
        .mret_en(id_ex.mret_en),
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
    wire [31:0] vec_offset = (irq_taken & ~exc_pending & mtvec_w[0]) ? {26'd0, irq_cause[3:0], 2'b00} : 32'd0;

    // suppress branches/jumps while MDU is mid-operation; trap > mret > branch
    assign pc_en = ((id_ex.jal_en | (id_ex.branch_en & cond_ff)) & ~mdu_busy) | trap_en | id_ex.mret_en;
    assign pc_target = trap_en ? (mtvec_base + vec_offset) :
                       id_ex.mret_en ? mepc_w :
                       {alu_out[31:1], 1'b0};
    wire [31:0] exec = id_ex.jal_en ? id_ex.pc_next :
                       id_ex.mdu_en ? mdu_out :
                       id_ex.csr_en ? csr_rdata :
                       alu_out;

    always_ff @(posedge clk) begin
        if (reset | bubble) begin
            ex_ma <= '0;
        end 
        
        else begin
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
