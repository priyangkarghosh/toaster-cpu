import riscv_pkg::*;

module tx_mem (
    input clk, reset,

    input ex_ma_t ex_ma,
    output ma_wb_t ma_wb
);
    always_ff @(posedge clk) begin
        if (reset) begin
            ma_wb <= '0;
        end 

        else begin
            ma_wb.alu <= ex_ma.alu;
            ma_wb.rd <= ex_ma.rd;
            ma_wb.rf_en <= ex_ma.rf_en;
        end
    end
endmodule
