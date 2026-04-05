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

    // instantiate 2^ADDR_BITS 32-bit registers
    // -> need a wire for each data out and enable signal
    wire [REG_COUNT-1:0] reg_enable;
    wire [WORD_LENGTH-1:0] reg_out[REG_COUNT-1:0];

    // instantiate each register
    genvar j;
	generate
		for (j = 0; j < REG_COUNT; j = j + 1) begin : regs
            register # (.WORD_LENGTH(WORD_LENGTH)) inst_reg (
                .clk(clk),
                .enable(reg_enable[j]),
                .reset(reset),
                .D(rf_in),
                .Q(reg_out[j])
            );
		end
	endgenerate

    // read logic decoding
    assign rf_outA = (rf_addrA == 0) ? 0 : reg_out[rf_addrA];
    assign rf_outB = (rf_addrB == 0) ? 0 : reg_out[rf_addrB];

    // write logic decoding
    assign reg_enable = (rf_enable && rf_addrW != 0) ? (1 << rf_addrW) : 0;
endmodule
