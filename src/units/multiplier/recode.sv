import unit_pkg::*;

module recode #(
    parameter W = 32
)(
    input logic [W+2:0] q, // should already be 
    output booth_recode_t r [0:(W/2)-1]
);
    // mapping table
    function booth_recode_t map(input [2:0] qb);
        case (qb)
            3'b000: return ZERO;
            3'b001: return ONE_POS;
            3'b010: return ONE_POS;
            3'b011: return TWO_POS;
            3'b100: return TWO_NEG;
            3'b101: return ONE_NEG;
            3'b110: return ONE_NEG;
            3'b111: return ZERO;
            default: return ZERO;
        endcase
    endfunction

    // sign extend and append implicit 0
    wire [W+1:0] q_ext = {q[W-1], q, 1'b0};

    // do the recoding
    genvar i;
    generate
        for (i = 0; i < W/2; i++) begin
            assign r[i] = map(q_ext[2*i+2 : 2*i]);
        end
    endgenerate
endmodule