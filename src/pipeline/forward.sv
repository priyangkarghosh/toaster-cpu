module forward # (
    parameter W=32,
    parameter RF_ADDR_BITS=5
)(
    // from decode stage
    input logic [RF_ADDR_BITS-1:0] ex_rs1,
    input logic [RF_ADDR_BITS-1:0] ex_rs2,
    input logic [W-1:0] ex_rr1,
    input logic [W-1:0] ex_rr2,

    // from exec stage
    input logic [RF_ADDR_BITS-1:0] mem_rd,
    input logic [W-1:0] mem_alu,
    input logic mem_rf_en,

    // from mem stage
    input logic [RF_ADDR_BITS-1:0] wb_rd,
    input logic [W-1:0] wb_alu,
    input logic wb_rf_en,

    // forwarded outputs
    output logic [W-1:0] fwd_rr1,
    output logic [W-1:0] fwd_rr2
);
    assign fwd_rr1 = (
        (mem_rf_en && (ex_rs1 == mem_rd)) ? mem_alu :
        (wb_rf_en && (ex_rs1 == wb_rd)) ? wb_alu : ex_rr1
    );

    assign fwd_rr2 = (
        (mem_rf_en && (ex_rs2 == mem_rd)) ? mem_alu :
        (wb_rf_en && (ex_rs2 == wb_rd)) ? wb_alu : ex_rr2
    );
endmodule