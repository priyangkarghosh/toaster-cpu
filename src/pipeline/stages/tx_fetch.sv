import riscv_pkg::*;

module tx_fetch (
    input clk, reset, en, bubble,

    input [31:0] pc_in,
    input [31:0] inst_in,
    output if_id_t if_id
);
    // latch stage registers
    always_ff @(posedge clk) begin
        if (reset | bubble) begin
            if_id <= 0;
            if_id.ir <= 32'h13; // nop
        end

        else if (en) begin
            if_id.valid <= 1'b1;
            if_id.pc <= pc_in;
            if_id.ir <= inst_in;
        end
    end
endmodule
