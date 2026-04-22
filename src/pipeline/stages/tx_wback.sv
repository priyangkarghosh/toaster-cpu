import riscv_pkg::*;

module tx_wback (
    input ma_wb_t ma_wb,

    // outputs to rf
    output logic [4:0]  rf_rd,
    output logic [31:0] rf_data,
    output logic        rf_en
);
    assign rf_rd = ma_wb.rd;
    assign rf_data = ma_wb.alu;
    assign rf_en = ma_wb.rf_en;
endmodule
