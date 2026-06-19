import riscv_pkg::*;

module tx_exec (
    input clk, reset, bubble, load_use,

    // output signals
    output exec_busy,

    // inputs
    input id_ex_t id_ex,
    input logic [31:0] fwd_rr1,
    input logic [31:0] fwd_rr2,

    // branch/jump outputs
    output logic [31:0] pc_target,
    output logic pc_en,

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

    // JALR clears the LSB of (rs1+imm)
    assign pc_target = {alu_out[31:1], 1'b0};

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
        .div_zero(),
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
    
    // suppress branches/jumps while MDU is mid-operation
    assign pc_en = (id_ex.jal_en | (id_ex.branch_en & cond_ff)) & ~mdu_busy;
    wire [31:0] exec = id_ex.jal_en ? id_ex.pc_next :
                       id_ex.mdu_en ? mdu_out :
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
