import alu_pkg::*;

module alu # (
    parameter W=32
)(
    // inputs
    input logic [W-1:0] A, B,
    input logic [2:0] select,
    input logic alt, // switch to alt function (i.e sub)

    // outputs
    output logic [W-1:0] Z
);
    // calc shift
    localparam WL2 = $clog2(W);
    wire [WL2-1:0] shift = B[WL2-1:0];

    // alu thing
    always_comb begin
        case (select)
            ADD:  Z = alt ? A - B : A + B;
            SLL:  Z = A << shift;
            SLT:  Z = W'($signed(A) < $signed(B));
            SLTU: Z = W'(A < B);
            XOR:  Z = A ^ B;
            SRL:  Z = alt ? W'($signed(A) >>> shift)  : A >> shift;
            OR:   Z = A | B;
            AND:  Z = A & B;
            default: Z = '0;
        endcase
    end
endmodule