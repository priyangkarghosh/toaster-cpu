import riscv_pkg::*;

module forward (
    input logic [4:0] ex_rs1,
    input logic [4:0] ex_rs2,
    input logic [31:0] ex_rr1,
    input logic [31:0] ex_rr2,
    input ex_ma_t ex_ma,
    input ma_wb_t ma_wb,
    output logic [31:0] fwd_rr1,
    output logic [31:0] fwd_rr2
);
    assign fwd_rr1 = (ex_ma.rf_en && ex_rs1 == ex_ma.rd) ? ex_ma.data :
                     (ma_wb.rf_en && ex_rs1 == ma_wb.rd) ? ma_wb.data : ex_rr1;

    assign fwd_rr2 = (ex_ma.rf_en && ex_rs2 == ex_ma.rd) ? ex_ma.data :
                     (ma_wb.rf_en && ex_rs2 == ma_wb.rd) ? ma_wb.data : ex_rr2;
endmodule
