module tx_decode # (
    parameter W=32,
    parameter RF_ADDR_BITS=5
)(
    input clk, reset, stall, flush,

    // from fetch
    input [REG_BITS-1:0] id_ir,
    input [REG_BITS-1:0] id_pc,

    // from regfile
    input [REG_BITS-1:0] rf_rr1,
    input [REG_BITS-1:0] rf_rr2,

    // to regfile
    output [REG_ADDR_BITS-1:0] rf_rs1,
    output [REG_ADDR_BITS-1:0] rf_rs2,

    // latched outputs
    output logic [W-1:0] ex_pc,
    output logic [W-1:0] ex_imm,

    output logic [RF_ADDR_BITS-1:0] ex_rs1,
    output logic [RF_ADDR_BITS-1:0] ex_rs2,
    output logic [RF_ADDR_BITS-1:0] ex_rd,
    output logic [W-1:0] ex_rr1,
    output logic [W-1:0] ex_rr2,

    // control signals
    output alu_op_t ex_alu_op,
    output logic ex_use_imm,
    output logic ex_rf_write
);
    // declare decoder outputs
    logic [RF_ADDR_BITS-1:0] rs1, rs2, rd;
    logic [W-1:0] imm;
    alu_op_t alu_op;
    logic use_imm;
    logic rf_write;

    // inst decoder
    decoder (
        // inputs
        .ir(id_ir),

        // outputs
        .rs1(rs1), .rs2(rs1), .rd(rd),
        .alu_op(alu_op),
        .use_imm(use_imm),
        .rf_write(rf_write)
    )

    // assign stuff
    assign rf_rs1 = rs1;
    assign rf_rs2 = rs2;

    // latch stage registers
    always_ff @(posedge clk) begin
        if (reset || flush) begin
            ex_pc <= '0;
            ex_imm <= '0;
            ex_rs1 <= '0;
            ex_rs2 <= '0;
            ex_rd <= '0;
            ex_rr1 <= '0;
            ex_rr2 <= '0;
            ex_alu_op <= ALU_ADD;
            ex_use_imm <= '0;
            ex_rf_write <= '0;
        end 
        
        else if (!stall) begin
            ex_pc <= id_pc;
            ex_imm <= imm;
            ex_rs1 <= rs1;
            ex_rs2 <= rs2;
            ex_rd <= rd;
            ex_rr1 <= rf_rr1;
            ex_rr2 <= rf_rr2;
            ex_alu_op <= alu_op;
            ex_use_imm <= use_imm;
            ex_rf_write <= rf_write;
        end
    end
endmodule
