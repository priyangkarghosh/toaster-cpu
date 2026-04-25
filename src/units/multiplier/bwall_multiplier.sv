import unit_pkg::*;

module bwall_multiplier (
    input logic clk, reset,
    input logic signed_in,
    input logic valid_in,
    input logic [31:0] x, y,
    output logic [63:0] p,
    output logic valid_out
);
    localparam W  = 32;
    localparam WE = 34;
    localparam NP = 17;
    localparam PW = 64;

    // sign extend inputs
    wire [WE-1:0] x_eff = {2{signed_in & x[W-1]}, x};
    wire [WE-1:0] y_eff = {2{signed_in & y[W-1]}, y};

    // partial products
    wire [33:0] pos1 = x_eff;
    wire [33:0] neg1 = -x_eff;
    wire [33:0] pos2 = pos1 << 1;
    wire [33:0] neg2 = neg1 << 1;

    // recode y
    booth_recode_t rc [0:NP-1];
    recode #(.W(WE)) u_recode (.q(y_eff), .r(rc));

    // wallace tree
    // > inputs
    logic [67:0] a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q;

    // > layer 1
    logic [67:0] s1, s2, s3, s4, s5;
    logic [68:0] c1, c2, c3, c4, c5;
    csa #(68) csa1(.a(a), .b(b), .cin(c), .s(s1), .cout(c1));
    csa #(68) csa2(.a(d), .b(e), .cin(f), .s(s2), .cout(c2));
    csa #(68) csa3(.a(g), .b(h), .cin(i), .s(s3), .cout(c3));
    csa #(68) csa4(.a(j), .b(k), .cin(l), .s(s4), .cout(c4));
    csa #(68) csa5(.a(m), .b(n), .cin(o), .s(s5), .cout(c5));

    // > layer 2
    logic [68:0] s6, s7, s8, s9;
    logic [69:0] c6, c7, c8, c9;
    csa #(69) csa6(.a(c1), .b({1'b0,s1}), .cin({1'b0,s2}), .s(s6), .cout(c6));
    csa #(69) csa7(.a(c2), .b(c3), .cin({1'b0,s3}), .s(s7), .cout(c7));
    csa #(69) csa8(.a({1'b0,s4}), .b(c4), .cin({1'b0,s5}), .s(s8), .cout(c8));
    csa #(69) csa9(.a(c5), .b({1'b0,p}), .cin({1'b0,q}), .s(s9), .cout(c9));

    // > layer 3
    logic [69:0] s10, s11;
    logic [70:0] c10, c11;
    csa #(70) csa10(.a(c6), .b({1'b0,s6}), .cin({1'b0,s7}), .s(s10), .cout(c10));
    csa #(70) csa11(.a(c7), .b(c8), .cin({1'b0,s8}), .s(s11), .cout(c11));

    // > layer 4
    logic [70:0] s12, s13;
    logic [71:0] c12, c13;
    csa #(71) csa12(.a(c10), .b({1'b0,s10}), .cin({1'b0,s11}), .s(s12), .cout(c12));
    csa #(71) csa13(.a(c11), .b({1'b0,s9}), .cin({1'b0,c9}), .s(s13), .cout(c13));

    // > layer 5
    logic [71:0] s14;
    logic [72:0] c14;
    csa #(72) csa14(.a(c12), .b({1'b0,s12}), .cin({1'b0,s13}), .s(s14), .cout(c14));

    // > layer 6
    logic [72:0] s15;
    logic [73:0] c15;
    csa #(73) csa15(.a(c14), .b({1'b0,s14}), .cin({1'b0,c13}), .s(s15), .cout(c15));

    // stage 1 (recoding)
    logic valid_s1;
    logic [PW-1:0] pp [0:NP-1];
    always_ff @(posedge clk) begin
        if (reset) valid_s1 <= 0; 
        else begin
            valid_s1 <= valid_in;
        end
    end
endmodule