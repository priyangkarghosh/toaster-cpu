import riscv_pkg::*;

module cond (
    input [31:0] rr1,
    input [31:0] rr2,
    input branch_t br_type,
    output logic cond_ff
);
    always_comb begin
        case (br_type)
            BR_BEQ:  cond_ff = rr1 == rr2;
            BR_BNE:  cond_ff = rr1 != rr2;
            BR_BLT:  cond_ff = $signed(rr1) < $signed(rr2);
            BR_BGE:  cond_ff = $signed(rr1) >= $signed(rr2);
            BR_BLTU: cond_ff = rr1 < rr2;
            BR_BGEU: cond_ff = rr1 >= rr2;
            default: cond_ff = 0;
        endcase
    end
endmodule
