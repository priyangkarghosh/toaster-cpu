import riscv_pkg::*;

module tx_exec (
    input clk, reset, bubble,
    
    // inputs
    input id_ex_t id_ex,
    input logic [31:0] fwd_rr1,
    input logic [31:0] fwd_rr2,

    // latched output
    output ex_ma_t ex_ma
);
    // wire alu
    logic [31:0] alu_b, alu_out;
    assign alu_b = id_ex.use_imm ? id_ex.imm : fwd_rr2;
    alu inst_alu (
        .A(fwd_rr1),
        .B(alu_b),
        .select(id_ex.alu_op),
        .Z(alu_out)
    );

    always_ff @(posedge clk) begin
        if (reset | bubble) begin
            ex_ma <= '0;
        end 
        
        else begin
            ex_ma.alu <= alu_out;
            ex_ma.rr2 <= fwd_rr2;
            ex_ma.rd <= id_ex.rd;
            ex_ma.rf_en <= id_ex.rf_en;
            ex_ma.load_en <= id_ex.load_en;
            ex_ma.store_en <= id_ex.store_en;
        end
    end
endmodule
