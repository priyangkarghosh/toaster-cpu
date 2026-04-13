module regfile # (
    parameter W=32,
    parameter RF_ADDR_BITS=5
)(
    // base parameters
    input clk, reset,

    // read properties
    input [RF_ADDR_BITS-1:0] rf_rs1,
    input [RF_ADDR_BITS-1:0] rf_rs2,

    // write properties
    input rf_write,
    input [RF_ADDR_BITS-1:0] rf_rd,
    input [W-1:0] rf_in,

    // outputs
    output [W-1:0] rf_rr1,
    output [W-1:0] rf_rr1
);
    // calculate # of registers from addr bits
    localparam REG_COUNT = 1 << RF_ADDR_BITS;

    // create registers
    integer i;
    reg [W-1:0] regs [REG_COUNT-1:0];
    always @(posedge clk) begin
        if (reset) for (i = 0; i < REG_COUNT; i = i + 1) regs[i] <= 0;        
        else if (rf_write && rf_rd != 0) regs[rf_rd] <= rf_in;
    end

    // read logic decoding
    assign rf_rr1 = (rf_rs1 == 0) ? 0 : regs[rf_rs1];
    assign rf_rr1 = (rf_rs2 == 0) ? 0 : regs[rf_rs2];
endmodule
