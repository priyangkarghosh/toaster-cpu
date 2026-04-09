module srt4_divider # (
    parameter WORD_LENGTH = 32
)(
    input logic clk, reset, start, signed_in,
    input logic [WORD_LENGTH-1:0] x, y,
    output logic [WORD_LENGTH-1:0] q, r,
    output logic busy, done, div_zero
);
    localparam W = WORD_LENGTH;
    localparam W2 = WORD_LENGTH * 2;
    localparam WL2 = $clog2(WORD_LENGTH);

    // calculate shift
    function [WL2-1:0] count_zeroMSB(input [W-1:0] x);
        integer i;
        begin
            count_zeroMSB = WL2'(0);
            for (i = W-1; i >= 0; i--) begin
                if (x[i]) count_zeroMSB = WL2'(W - 1 - i);
            end
        end
    endfunction

    // prep inputs
    wire negate_q = signed_in & (x[W-1] ^ y[W-1]);
    wire [W-1:0] x_eff = (x[W-1] & signed_in) ? -x : x;
    wire [W-1:0] y_eff = (y[W-1] & signed_in) ? -y : y;
    wire [WL2-1:0] zero_MSB = count_zeroMSB(y_eff);

    // set up internal reg logic
    logic [WL2-1:0] counter;
    logic [W-1:0] y_norm;
    logic [WL2-1:0] shift_y;
    logic [W2+2:0] rxq; // partial remainder
    logic [W+2:0] rxqc; // carry for partial remainder

    // csa outputs
    logic [W+2:0] ca,  sa;    // +y  (shift-by-2 path)
    logic [W+2:0] cs,  ss;    // -y  (shift-by-2 path)
    logic [W+2:0] ca2, sa2;   // +2y (shift-by-2 path)
    logic [W+2:0] cs2, ss2;   // -2y (shift-by-2 path)
    logic [W+2:0] ca1, sa1;   // +y  (shift-by-1 path, odd-N last iteration)
    logic [W+2:0] cs1, ss1;   // -y  (shift-by-1 path, odd-N last iteration)

    // quotient digit selection
    logic q0, q1; // pla outputs
    wire [7:0] r8 = rxq[W2:W2-7] + rxqc[W:W-7];
    wire [5:0] r6 = r8[7:2];
    wire qs = r6[5] & (q0 | q1);

    // assign outputs
    assign q = rxq[W-1:0];
    assign r = rxq[W2-1:W];

    // fsm
    typedef enum {RESET, START, RUN, DONE} State;
    State state;

    always_ff @(posedge clk) begin : FSM
        if (reset) state <= RESET;
        else begin
            case (state)
                RESET: begin
                    counter <= 0;

                    rxq <= 0;
                    rxqc <= 0;

                    busy <= 0;
                    done <= 0;
                    div_zero <= 0;

                    if (start) state <= START;
                end

                START: begin
                    busy <= 1;
                    
                    // div by 0 error
                    if (y == 0) begin
                        rxq <= 0;
                        div_zero <= 1;
                        state <= DONE;
                    end

                    // div by 1
                    else if (y_eff == 1) begin
                        rxq <= negate_q ? W'(-x_eff) : x_eff;
                        state <= DONE;
                    end
                    
                    // default case
                    else begin
                        shift_y <= zero_MSB;
                        y_norm <= y_eff << zero_MSB;
                        rxq <= x_eff << zero_MSB;
                        state <= RUN;
                    end
                end

                DONE: begin
                    busy <= 0;
                    done <= 1;
                end
            endcase
        end
    end
endmodule