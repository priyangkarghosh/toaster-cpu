module csa #(
    parameter W = 68
)(
    input logic [W-1:0] a, b, cin,
    output logic [W-1:0] s,
    output logic [W-1:0] cout
);
    logic [W-1:0] c;
    assign s = a ^ b ^ cin;
    assign c = (a & b) | (a & cin) | (b & cin);
    assign cout = {c[W-2:0], 1'b0};
endmodule
