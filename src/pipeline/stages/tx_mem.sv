import riscv_pkg::*;

module tx_mem (
    input clk, reset,

    // inputs from prev stage
    input ex_ma_t ex_ma,

    // data memory port
    output [31:0] d_addr,
    input [31:0] d_rdata,
    output [31:0] d_wdata,
    output mem_width_t d_width,
    output logic d_write,
    
    // outputs to next stage
    output ma_wb_t ma_wb
);
    assign d_addr = ex_ma.data;
    assign d_wdata = ex_ma.rr2;
    assign d_width = ex_ma.mem_width;
    assign d_write = ex_ma.store_en;

    always_ff @(posedge clk) begin
        if (reset) begin
            ma_wb <= '0;
        end

        else begin
            ma_wb.data <= ex_ma.load_en ? d_rdata : ex_ma.data;
            ma_wb.rd <= ex_ma.rd;
            ma_wb.rf_en <= ex_ma.rf_en;
        end
    end
endmodule
