import riscv_pkg::*;

module tx_exec (
    input clk, reset, bubble,
    
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
    logic [31:0] alu_a, alu_b, alu_out;
    assign alu_a = id_ex.branch_en | id_ex.jal_en ? id_ex.pc : fwd_rr1;
    assign alu_b = id_ex.use_imm ? id_ex.imm : fwd_rr2;
    alu inst_alu (
        .A(alu_a),
        .B(alu_b),
        .select(id_ex.alu_op),
        .Z(alu_out)
    );
    assign pc_target = alu_out;

    // branch conditionals
    logic cond_ff;
    cond inst_cond (
        .rr1(fwd_rr1),
        .rr2(fwd_rr2),
        .br_type(id_ex.br_type),
        .cond_ff(cond_ff)
    );
    assign pc_en = id_ex.jal_en | id_ex.jalr_en | (id_ex.branch_en & cond_ff);

    always_ff @(posedge clk) begin
        if (reset | bubble) begin
            ex_ma <= '0;
        end 
        
        else begin
            ex_ma.mem_width <= id_ex.mem_width;
            ex_ma.data <= (id_ex.jal_en | id_ex.jalr_en) ? id_ex.pc_next : alu_out;
            ex_ma.rr2 <= fwd_rr2;
            ex_ma.rd <= id_ex.rd;
            ex_ma.rf_en <= id_ex.rf_en;
            ex_ma.load_en <= id_ex.load_en;
            ex_ma.store_en <= id_ex.store_en;
        end
    end
endmodule
