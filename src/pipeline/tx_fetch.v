module tx_fetch # (
    parameter WORD_LENGTH=32,
    parameter RF_ADDR_BITS=5
)(
    input clk, reset, stall, flush,

    input [WORD_LENGTH-1:0] pc_in,
    input [WORD_LENGTH-1:0] inst_in,

    // outputs to id
    output reg [WORD_LENGTH-1:0] id_ir,
    output reg [WORD_LENGTH-1:0] id_pc
);
    // latch stage registers
    always @(posedge clk) begin
        if (reset | flush) begin
            id_pc <= 0;
            id_ir <= 32'h00000013; // nop instruction
        end 

        else if (!stall) begin
            id_pc <= pc_in;
            id_ir <= inst_in;
        end
    end
endmodule
