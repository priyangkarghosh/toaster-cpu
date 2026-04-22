import riscv_pkg::*;

module tx_exec # (
    parameter W=32,
    parameter RF_ADDR_BITS=5
)(
    input clk, reset, bubble,

    // inputs
    input logic [W-1:0] ex_pc,
    input logic [W-1:0] ex_imm,

    input logic [RF_ADDR_BITS-1:0] ex_rs1,
    input logic [RF_ADDR_BITS-1:0] ex_rs2,
    input logic [RF_ADDR_BITS-1:0] ex_rd,
    input logic [W-1:0] fwd_rr1,
    input logic [W-1:0] fwd_rr2,

    // control signals
    input alu_op_t ex_alu_op,
    input logic ex_use_imm,
    input logic ex_rf_en,

    // outputs to mem stage
    output logic [RF_ADDR_BITS-1:0] mem_rd,
    output logic [W-1:0] mem_alu,
    output logic mem_rf_en
);
    // wire alu
    wire [W-1:0] alu_b = ex_use_imm ? ex_imm : fwd_rr2;
    wire [W-1:0] alu_out;
    alu # (.W(W)) inst_alu (
        .A(fwd_rr1),
        .B(alu_b),
        .select(ex_alu_op),
        .Z(alu_out)
    );

    // latch stage registers
    always_ff @(posedge clk) begin
        if (reset | bubble) begin
            mem_alu <= 0;
            mem_rd <= 0;
            mem_rf_en <= 0;
        end 

        else begin
            mem_rd <= ex_rd;
            mem_alu <= alu_out;
            mem_rf_en <= ex_rf_en;
        end
    end
endmodule
