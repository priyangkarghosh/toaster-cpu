module regfile # (
    parameter WORD_LENGTH=32,
    parameter RF_ADDR_BITS=5
)(
    // base parameters
    input clk, reset,

    // read properties
    input [RF_ADDR_BITS-1:0] rf_addrA,
    input [RF_ADDR_BITS-1:0] rf_addrB,

    // write properties
    input rf_enable,
    input [RF_ADDR_BITS-1:0] rf_addrW,
    input [WORD_LENGTH-1:0] rf_in,

    // outputs
    output [WORD_LENGTH-1:0] rf_outA,
    output [WORD_LENGTH-1:0] rf_outB
);
    // calculate # of registers from addr bits
    localparam REG_COUNT = 1 << RF_ADDR_BITS;

    // create registers
    integer i;
    reg [WORD_LENGTH-1:0] regs [REG_COUNT-1:0];
    always @(posedge clk) begin
        if (reset) for (i = 0; i < REG_COUNT; i = i + 1) regs[i] <= 0;        
        else if (rf_enable && rf_addrW != 0) regs[rf_addrW] <= rf_in;
    end

    // read logic decoding
    assign rf_outA = (rf_addrA == 0) ? 0 : regs[rf_addrA];
    assign rf_outB = (rf_addrB == 0) ? 0 : regs[rf_addrB];
endmodule
