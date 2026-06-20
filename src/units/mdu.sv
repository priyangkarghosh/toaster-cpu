import riscv_pkg::*;

module mdu (
    input logic clk, reset,

    // handshake
    input logic valid_in,
    output logic busy,
    output logic valid_out,

    // params
    input logic [31:0] x, y,
    input mdu_op_t select,
    output logic [31:0] z
);
    // decode from select
    wire is_mul = (select == MDU_MUL) | (select == MDU_MULH) | (select == MDU_MULHSU) | (select == MDU_MULHU);
    wire is_rem = (select == MDU_REM) | (select == MDU_REMU);
    wire use_high = (select == MDU_MULH) | (select == MDU_MULHSU) | (select == MDU_MULHU);

    // sign selection
    wire mul_sign_x = (select == MDU_MUL) | (select == MDU_MULH) | (select == MDU_MULHSU);
    wire mul_sign_y = (select == MDU_MUL) | (select == MDU_MULH);
    wire div_sign_x = (select == MDU_DIV) | (select == MDU_REM);
    wire div_sign_y = (select == MDU_DIV) | (select == MDU_REM);

    // mul datapath
    logic [63:0] mul_p;
    logic mul_valid_out;

    // div datapath
    logic [31:0] div_q, div_r;
    logic div_busy_raw, div_done;

    // fsm
    typedef enum logic [1:0] { IDLE, MUL_WAIT, DIV_WAIT } state_t;
    state_t state;

    // combinational so the mul/div samples x,y on the same cycle the op enters EX
    wire mul_valid_in = (state == IDLE) & valid_in & is_mul;
    wire div_start = (state == IDLE) & valid_in & ~is_mul;

    mul u_mul (
        .clk(clk),
        .reset(reset),
        .sign_x(mul_sign_x),
        .sign_y(mul_sign_y),
        .valid_in(mul_valid_in),
        .x(x), .y(y), .p(mul_p),
        .valid_out(mul_valid_out)
    );

    div #(.W(32)) u_div (
        .clk(clk),
        .reset(reset),
        .start(div_start),
        .sign_x(div_sign_x),
        .sign_y(div_sign_y),
        .x(x), .y(y), .q(div_q), .r(div_r),
        .busy(div_busy_raw),
        .done(div_done)
    );

    logic is_rem_q;
    logic use_high_q;
    logic [31:0] result_q;
    assign busy = (state != IDLE);
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            valid_out <= 1'b0;
            result_q <= '0;
            is_rem_q <= 1'b0;
            use_high_q <= 1'b0;
        end

        else begin
            valid_out <= 1'b0;

            case (state)
                IDLE: begin
                    if (valid_in) begin
                        is_rem_q <= is_rem;
                        use_high_q <= use_high;
                        state <= is_mul ? MUL_WAIT : DIV_WAIT;
                    end
                end
 
                MUL_WAIT: begin
                    if (mul_valid_out) begin
                        result_q <= use_high_q ? mul_p[63:32] : mul_p[31:0];
                        valid_out <= 1'b1;
                        state <= IDLE;
                    end
                end
 
                DIV_WAIT: begin
                    if (div_done) begin
                        result_q <= is_rem_q ? div_r : div_q;
                        valid_out <= 1'b1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    assign z = result_q;
endmodule
