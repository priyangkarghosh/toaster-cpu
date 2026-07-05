import riscv_pkg::*;

module tx_exec (
    input clk, reset, en, bubble, load_use,

    // an older instruction trapping at ma squashes this one
    input logic trap_en,

    // inputs from prev stage
    input id_ex_t id_ex,
    input logic [31:0] fwd_rr1,
    input logic [31:0] fwd_rr2,

    // csr op port + live status
    output csr_req_t csr_req,
    input csr_rsp_t csr_rsp,
    input csr_stat_t csr_stat,

    // redirect
    output logic [31:0] pc_target,
    output logic pc_en,

    // output signals
    output ex_busy,

    // outputs to next stage
    output ex_ma_t ex_ma
);
    // side effects can only occur if there's no stall or trap (and is a normal inst)
    wire ex_commit = en & ~load_use & ~trap_en;

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

    // mdu
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
    assign ex_busy = mdu_busy | mdu_starting;

    // branch condition
    logic cond_ff;
    cond u_cond (
        .rr1(fwd_rr1),
        .rr2(fwd_rr2),
        .br_type(id_ex.br_type),
        .cond_ff(cond_ff)
    );

    // csr op port
    assign csr_req.en = id_ex.csr_en & ex_commit;
    assign csr_req.op = id_ex.csr_op;
    assign csr_req.addr = id_ex.imm[11:0];
    assign csr_req.wdata = id_ex.use_imm ? {27'd0, id_ex.rs1} : fwd_rr1;
    assign csr_req.wmask = (id_ex.csr_op == CSR_RW) || (id_ex.rs1 != 5'd0);
    assign csr_req.mret = id_ex.mret_en & ex_commit;

    // update the exception port to reflect current inst
    exc_t ex_exc;
    assign ex_exc.valid = id_ex.exc.valid | csr_rsp.illegal;
    assign ex_exc.cause = id_ex.exc.valid ? id_ex.exc.cause : EXC_ILLEGAL;
    assign ex_exc.tval = (ex_exc.cause == EXC_ILLEGAL) ? id_ex.ir : '0;

    // mret has priority over a branch branch
    assign pc_en = (id_ex.jal_en | (id_ex.branch_en & cond_ff) | id_ex.mret_en) & ex_commit;
    assign pc_target = id_ex.mret_en ? csr_stat.mepc : {alu_out[31:1], 1'b0};

    // stage result
    wire [31:0] exec = id_ex.jal_en ? id_ex.pc + 32'd4 :
                       id_ex.mdu_en ? mdu_out :
                       id_ex.csr_en ? csr_rsp.rdata :
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
            ex_ma.csr_en <= id_ex.csr_en;
            ex_ma.mret_en <= id_ex.mret_en;
        end
    end
endmodule
