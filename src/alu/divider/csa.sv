module csa # (
    parameter WORD_LENGTH = 32
)(
    input logic sub,
    input logic [WORD_LENGTH-1:0] a, b, cin,
    output logic [WORD_LENGTH-1:0] s, cout
);
    logic b_eff = sub ? ~b : b;
    assign s = a ^ b_eff ^ cin;
    assign c = ((a & b_eff) | (b_eff & cin) | (a & cin)) << 1;
endmodule
