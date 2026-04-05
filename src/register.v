module register # (
    parameter WORD_LENGTH = 32, 
)(
    input clk, enable, reset,
    input [REG_BITS-1:0] D,
    output reg [REG_BITS-1:0] Q
);
    initial Q = {WORD_LENGTH{1'b0}};
    always @ (posedge clk) begin 
        if (reset) Q <= {REG_BITS{1'b0}};
        else if (enable) Q <= D;
    end
endmodule
