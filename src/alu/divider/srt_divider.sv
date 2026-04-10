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

    // declare data
    wire [W-1:0] x_eff = (x[W-1] & signed_in) ? -x : x;
    wire [W-1:0] y_eff = (y[W-1] & signed_in) ? -y : y;

    logic [W2+2:0] rxq; // main data reg with partial remainder and quotient
    logic [W+2:0] c; // carry for partial remainder
    logic [WL2-1:0] shift_y;
    logic [W-1:0] y_norm;
    logic [W-1:0] qs1; // quotient sub 1
    
    // csa outputs
    logic [W+2:0] ca,  sa;    // +y  (shift-by-2 path)
    logic [W+2:0] cs,  ss;    // -y  (shift-by-2 path)
    logic [W+2:0] ca2, sa2;   // +2y (shift-by-2 path)
    logic [W+2:0] cs2, ss2;   // -2y (shift-by-2 path)
    logic [W+2:0] ca1, sa1;   // +y  (shift-by-1 path, odd-N last iteration)
    logic [W+2:0] cs1, ss1;   // -y  (shift-by-1 path, odd-N last iteration)

    // digit select
    wire q0, q1;
    wire [7:0] r8 = rxq[W2:W2-7] + c[W:W-7];
    wire [5:0] r6 = r8[7:2];
    wire qs = r6[5] & (q0 | q1);

    // final corrections
    wire [W+2:0] s = rxq[W2+2:W] + {c[W+2:0]};
    wire negate_q = signed_in & (x[W-1] ^ y[W-1]);
    wire r_unnorm = s[W+2] ? N'((s + y_norm) >> shift_y) : N'(s >> shift_y);

    // assign outputs
    assign q = rxq[W-1:0];
    assign r = rxq[W2-1:W];

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
    wire shift_yc = count_zeroMSB(y_eff); // combinational shift

    // wire modules
    qsel inst_qsel (.r5(r6[5] ? ~r6[4:0]: r6[4:0]), .y4(y_norm[W-1:W-4]), .q({q1, q0}));
    csadd # (W + 3) csa1(.sub(0), .a({rxq[W2+1:W-1]}), .b({3'b000, y_norm}), .cin({c[W+1:0], 1'b0}), .s(sa1), .cout(ca1));
    csadd # (W + 3) css1(.sub(1), .a({rxq[W2+1:W-1]}), .b({3'b000, y_norm}), .cin({c[W+1:0], 1'b0}), .s(ss1), .cout(cs1));
    csadd # (W + 3) csa(.sub(0), .a({rxq[W2:W-2]}), .b({3'b000, y_norm}), .cin({c[W+1:0], 2'b0}), .s(sa), .cout(ca));
    csadd # (W + 3) css(.sub(1), .a({rxq[W2:W-2]}), .b({3'b000, y_norm}), .cin({c[W+1:0], 2'b0}), .s(ss), .cout(cs));
    csadd # (W + 3) csa2(.sub(0), .a({rxq[W2:W-2]}), .b({2'b00, y_norm, 1'b0}), .cin({c[W:0], 2'b0}), .s(sa2), .cout(ca2));
    csadd # (W + 3) css2(.sub(1), .a({rxq[W2:W-2]}), .b({2'b00, y_norm, 1'b0}), .cin({c[W:0], 2'b0}), .s(ss2), .cout(cs2));

    // fsm
    logic [WL2-1:0] counter; // for counting cycles
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
                    counter <= 0;
                    
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

                RUN: begin
                    if (counter == ((W/2) + (W%2))) begin
                        rxq[W2-1:W] <= nnr >= y_eff ? nnr - y_eff : nnr;
                        rxq[W-1:0] <= negate_q ? sum[W+2] - rxq[W-1:0] + (nnr >= y_eff): rxq[W-1:0] - sum[W+2] + (nnr >= y_eff);   
                        state <= DONE;
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
