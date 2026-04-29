module cla4 (
    input logic [3:0] a,
    input logic [3:0] b,
    input logic cin,
    output logic [3:0] sum,
    output logic cout,
    output logic G, P
);
    // bit level g/p
    wire [3:0] g = a & b;
    wire [3:0] p = a ^ b;
    
    // carries
    logic [3:0] c;
    assign c[0] = cin;
    assign c[1] = g[0] | (p[0] & cin);
    assign c[2] = g[1] | (p[1] & g[0])
                       | (p[1] & p[0] & cin);
    assign c[3] = g[2] | (p[2] & g[1])
                       | (p[2] & p[1] & g[0])
                       | (p[2] & p[1] & p[0] & cin);
    
    // final sum
    assign sum = p ^ c;
    assign cout = g[3] | (p[3] & g[2])
                       | (p[3] & p[2] & g[1])
                       | (p[3] & p[2] & p[1] & g[0])
                       | (p[3] & p[2] & p[1] & p[0] & cin);

    // group level generates
    assign G = g[3] | (p[3] & g[2])
                    | (p[3] & p[2] & g[1])
                    | (p[3] & p[2] & p[1] & g[0]);
    assign P = p[3] & p[2] & p[1] & p[0];
endmodule
