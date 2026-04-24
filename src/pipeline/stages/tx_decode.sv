import riscv_pkg::*;

module tx_decode (
    input clk, reset, stall, flush,

    // from fetch
    input if_id_t if_id,

    // from regfile
    input [31:0] rf_rr1,
    input [31:0] rf_rr2,

    // from pc
    input [31:0] pc_next,

    // to regfile
    output [4:0] rf_rs1,
    output [4:0] rf_rs2,

    // latched output
    output id_ex_t id_ex
);
    id_ex_t dec;
    control u_ctl (
        .ir(if_id.ir),
        .rs1(dec.rs1), 
        .rs2(dec.rs2), 
        .rd(dec.rd), 
        .imm(dec.imm),
        .mem_width(dec.mem_width),
        .alu_op(dec.alu_op),
        .br_type(dec.br_type),
        .use_imm(dec.use_imm),
        .use_pc(dec.use_pc),
        .rf_en(dec.rf_en),
        .load_en(dec.load_en),
        .store_en(dec.store_en),
        .branch_en(dec.branch_en),
        .jal_en(dec.jal_en)
    );

    // assign stuff
    assign rf_rs1 = dec.rs1;
    assign rf_rs2 = dec.rs2;

    // latch stage registers
    always_ff @(posedge clk) begin
        if (reset || flush) begin
            id_ex <= '0;
            id_ex.alu_op <= ALU_ADD;
        end 
        
        else if (!stall) begin
            id_ex <= dec;
            id_ex.pc <= if_id.pc;
            id_ex.pc_next <= pc_next;
            id_ex.rr1 <= rf_rr1;
            id_ex.rr2 <= rf_rr2;
        end
    end
endmodule
