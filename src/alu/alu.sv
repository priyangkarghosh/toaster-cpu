import riscv_pkg::*;

module alu (
    // inputs
    input logic [31:0] A, B,
    input alu_op_t select,

    // outputs
    output logic [31:0] Z
);
    // calc shift
    wire [4:0] shift = B[4:0];

    // alu thing
    always_comb begin
        case (select)
            ALU_ADD:  Z = A + B;
            ALU_SUB:  Z = A - B;
            ALU_SLL:  Z = A << shift;
            ALU_SLT:  Z = $signed(A) < $signed(B);
            ALU_SLTU: Z = A < B;
            ALU_XOR:  Z = A ^ B;
            ALU_SRL:  Z = A >> shift;
            ALU_SRA:  Z = $signed(A) >>> shift;
            ALU_OR:   Z = A | B;
            ALU_AND:  Z = A & B;
            default:  Z = '0;
        endcase
    end
endmodule
