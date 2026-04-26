import unit_pkg::*;

module recode #(
    parameter W = 32
)(
    input logic [W-1:0] q,
    output booth_recode_t r [0:(W/2)-1]
);
    // mapping table
    function booth_recode_t map(input [2:0] qb);
        case (qb)
            3'b000: return BOOTH_ZERO;
            3'b001: return BOOTH_POS1;
            3'b010: return BOOTH_POS1;
            3'b011: return BOOTH_POS2;
            3'b100: return BOOTH_NEG2;
            3'b101: return BOOTH_NEG1;
            3'b110: return BOOTH_NEG1;
            3'b111: return BOOTH_ZERO;
            default: return BOOTH_ZERO;
        endcase
    endfunction

    // sign extend and append implicit 0
    wire [W+1:0] q_ext = {q[W-1], q, 1'b0};

    // do the recoding
    genvar i;
    generate
        for (i = 0; i < W/2; i++) begin : gen_r
            assign r[i] = map(q_ext[2*i+2 : 2*i]);
        end
    endgenerate
endmodule
