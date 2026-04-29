import unit_pkg::*;

module ksa64 (
    input logic [63:0] a, b,
    input logic cin,
    output logic [63:0] sum,
    output logic cout
);
    // initial gen and prop
    wire [63:0] g0 = a & b;
    wire [63:0] p0 = a ^ b;

    // level 1
    wire [63:0] g1, p1;
    assign g1[0] = g0[0] | (p0[0] & cin);
    assign p1[0] = p0[0];
    generate
        genvar i;
        for (i = 1; i < 64; i++) begin : lvl1
            assign g1[i] = g0[i] | (p0[i] & g0[i-1]);
            assign p1[i] = p0[i] & p0[i-1];
        end
    endgenerate

    // level 2
    wire [63:0] g2, p2;
    assign g2[1:0] = g1[1:0];
    assign p2[1:0] = p1[1:0];
    generate
        for (i = 2; i < 64; i++) begin : lvl2
            assign g2[i] = g1[i] | (p1[i] & g1[i-2]);
            assign p2[i] = p1[i] & p1[i-2];
        end
    endgenerate

    // levle 3
    wire [63:0] g3, p3;
    assign g3[3:0] = g2[3:0];
    assign p3[3:0] = p2[3:0];
    generate
        for (i = 4; i < 64; i++) begin : lvl3
            assign g3[i] = g2[i] | (p2[i] & g2[i-4]);
            assign p3[i] = p2[i] & p2[i-4];
        end
    endgenerate

    // level 4
    wire [63:0] g4, p4;
    assign g4[7:0] = g3[7:0];
    assign p4[7:0] = p3[7:0];
    generate
        for (i = 8; i < 64; i++) begin : lvl4
            assign g4[i] = g3[i] | (p3[i] & g3[i-8]);
            assign p4[i] = p3[i] & p3[i-8];
        end
    endgenerate

    // level 5
    wire [63:0] g5, p5;
    assign g5[15:0] = g4[15:0];
    assign p5[15:0] = p4[15:0];
    generate
        for (i = 16; i < 64; i++) begin : lvl5
            assign g5[i] = g4[i] | (p4[i] & g4[i-16]);
            assign p5[i] = p4[i] & p4[i-16];
        end
    endgenerate

    // level 6
    wire [63:0] g6, p6;
    assign g6[31:0] = g5[31:0];
    assign p6[31:0] = p5[31:0];
    generate
        for (i = 32; i < 64; i++) begin : lvl6
            assign g6[i] = g5[i] | (p5[i] & g5[i-32]);
            assign p6[i] = p5[i] & p5[i-32];
        end
    endgenerate

    // final sum and carry
    wire [63:0] carry = {g6[62:0], cin};
    assign sum  = p0 ^ carry;
    assign cout = g6[63];
endmodule