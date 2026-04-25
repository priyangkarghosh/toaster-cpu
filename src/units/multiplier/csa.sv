module csa # (
    parameter W = 32
)(
    input logic [W-1:0] a, b, cin,
    output logic [W-1:0] s,
    output logic [W:0] cout
);
    logic [W-1:0] c;
    assign s = a ^ b ^ cin;
    assign c = (a & b) | (a & cin) | (b & cin);
    assign cout = {c, 1'b0};
endmodule
