module tx_wback # (
    parameter W=32,
    parameter RF_ADDR_BITS=5
)(
    input clk, reset,

    input logic [RF_ADDR_BITS-1:0] wb_rd,
    input logic [W-1:0] wb_alu,
    input logic wb_rf_write,

    // outputs to rf
    output logic [RF_ADDR_BITS-1:0] rf_rd,
    output logic [W-1:0] rf_data,
    output logic rf_write,
);
    assign rf_rd = wb_rd;
    assign rf_data = wb_alu;
    assign rf_write = wb_rf_write;
endmodule