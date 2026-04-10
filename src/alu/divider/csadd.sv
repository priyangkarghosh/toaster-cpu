module csadd # (
    parameter W=32
)(
    input logic sub,
    input logic [W-1:0] a, b, cin,
    output logic [W-1:0] s, cout
);
    logic [W-1:0] b_eff = sub ? ~b : b;
    assign s = a ^ b_eff ^ cin;
    assign cout = ((a & b_eff) | (b_eff & cin) | (a & cin)) << 1;
endmodule
