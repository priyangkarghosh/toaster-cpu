// 3:2 carry-save adder/subtractor shared by the multiplier
//   sub = 0 -> s = a + b + cin      (cout shifted left by one)
//   sub = 1 -> s = a + (-b) + cin   (b is xored with all-ones and a +1 is
//                                    injected at the LSB)
module csa #(
    parameter int W = 32
)(
    // inputs
    input logic sub,
    input logic [W-1:0] a,
    input logic [W-1:0] b,
    input logic [W-1:0] cin,

    // outputs
    output logic [W-1:0] s,
    output logic [W-1:0] cout
);
    // intermediates
    wire [W-1:0] b_eff   = b ^ {W{sub}};
    wire [W-1:0] cin_eff = {cin[W-1:1], cin[0] | sub};
    wire [W-1:0] c       = (a & b_eff) | (a & cin_eff) | (b_eff & cin_eff);

    // outputs
    assign s = a ^ b_eff ^ cin_eff;
    assign cout = {c[W-2:0], 1'b0};
endmodule
