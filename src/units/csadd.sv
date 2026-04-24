module csadd # (
    parameter W=32
)(
    input logic sub,
    input logic [W-1:0] a, b, cin,
    output logic [W-1:0] s, cout
);
    wire [W-1:0] b_eff = b ^ {W{sub}};
    assign cout[0] = 1'b0;
    assign s[0] = a[0] ^ b_eff[0] ^ sub;
    assign cout[1] = (a[0] & b_eff[0]) | (a[0] & sub) | (b_eff[0] & sub);
    assign s[W-1:1] = a[W-1:1] ^ b_eff[W-1:1] ^ cin[W-1:1];
    assign cout[W-1:2] = (
        (a[W-2:1] & b_eff[W-2:1]) | 
        (a[W-2:1] & cin[W-2:1]) | 
        (b_eff[W-2:1] & cin[W-2:1])
    );
endmodule
