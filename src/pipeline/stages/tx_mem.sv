module tx_mem # (
    parameter W=32,
    parameter RF_ADDR_BITS=5
)(
    input clk, reset,

    input logic [RF_ADDR_BITS-1:0] mem_rd,
    input logic [W-1:0] mem_alu,
    input logic mem_rf_en,

    output logic [RF_ADDR_BITS-1:0] wb_rd,
    output logic [W-1:0] wb_alu,
    output logic wb_rf_en
);
    // latch stage registers
    always_ff @(posedge clk) begin
        if (reset) begin
            wb_alu <= 0;
            wb_rd <= 0;
            wb_rf_en <= 0;
        end 

        else begin
            wb_rd <= mem_rd;
            wb_alu <= mem_alu;
            wb_rf_en <= mem_rf_en;
        end
    end
endmodule
