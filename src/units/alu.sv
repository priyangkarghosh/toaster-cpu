import riscv_pkg::*;

module alu (
    // inputs
    input logic [31:0] x, y,
    input alu_op_t select,

    // outputs
    output logic [31:0] z,
    output logic busy
);
    // calc shift
    wire [4:0] shift = y[4:0];

    // alu thing
    assign busy = 0;
    always_comb begin
        case (select)
            ALU_ADD:  z = x + y;
            ALU_SUB:  z = x - y;
            ALU_SLL:  z = x << shift;
            ALU_SLT:  z = $signed(x) < $signed(y);
            ALU_SLTU: z = x < y;
            ALU_XOR:  z = x ^ y;
            ALU_SRL:  z = x >> shift;
            ALU_SRA:  z = $signed(x) >>> shift;
            ALU_OR:   z = x | y;
            ALU_AND:  z = x & y;
            default:  z = '0;
        endcase
    end
endmodule
