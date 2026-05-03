module csa_div # (
    parameter W=32
)(
    input logic sub,
    input logic [W-1:0] a, b, cin,
    output logic [W-1:0] s, cout
);
    wire [W-1:0] b_eff = b ^ {W{sub}};
    assign cout[0] = 1'b0;
    assign s[0] = a[0] ^ b_eff[0] ^ sub;
    assign cout[1] = (a[0] & b_eff[0]) | (a[0] & sub) | (b_eff[0] & sub);
    assign s[W-1:1] = a[W-1:1] ^ b_eff[W-1:1] ^ cin[W-1:1];
    assign cout[W-1:2] = (
        (a[W-2:1] & b_eff[W-2:1]) |
        (a[W-2:1] & cin[W-2:1]) |
        (b_eff[W-2:1] & cin[W-2:1])
    );
endmodule

module div # (
    parameter W = 32
)(
    input logic clk, reset, start, signed_in,
    input logic [W-1:0] x, y,
    output logic [W-1:0] q, r,
    output logic busy, done, div_zero
);
    localparam W2 = W * 2;
    localparam WL2 = $clog2(W);

    // convert to unsigned
    wire [W-1:0] x_eff = (x[W-1] & signed_in) ? -x : x;
    wire [W-1:0] y_eff = (y[W-1] & signed_in) ? -y : y;

    //
    logic [W2+2:0] rxq; // remainder + quotient
    logic [W+2:0] c;
    logic [WL2-1:0] shift_y;
    logic [W-1:0] y_norm;
    logic [W-1:0] qn;

    // csa outputs
    logic [W+2:0] ca,  sa;
    logic [W+2:0] cs,  ss;
    logic [W+2:0] ca2, sa2;
    logic [W+2:0] cs2, ss2;
    logic [W+2:0] ca1, sa1;
    logic [W+2:0] cs1, ss1;

    // digit select
    wire q0, q1;
    wire [7:0] r8 = rxq[W2:W2-7] + c[W:W-7];
    wire [5:0] r6 = r8[7:2];
    wire q_sign = r6[5] & (q0 | q1);

    // remainder correction
    wire [W+2:0] pr = rxq[W2+2:W] + c[W+2:0];
    wire [W+2:0] pr_corr  = pr[W+2] ? pr + {{3{1'b0}}, y_norm} : pr;
    wire [W-1:0] r_unnorm = W'(pr_corr >> shift_y);
    wire r_overshoot = (r_unnorm >= y_eff);
    wire [W-1:0] r_mag = r_overshoot ? r_unnorm - y_eff : r_unnorm;
    wire [W-1:0] q_corr = rxq[W-1:0] - {{(W-1){1'b0}}, pr[W+2]} + {{(W-1){1'b0}}, r_overshoot};

    // fix signs
    wire negate_q = signed_in & (x[W-1] ^ y[W-1]);
    wire negate_r = signed_in & x[W-1];
    assign q = rxq[W-1:0];
    assign r = rxq[W2-1:W];

    // leading zeroes
    function [WL2-1:0] count_zeroMSB(input [W-1:0] v);
        integer i;
        begin
            count_zeroMSB = WL2'(W);
            for (i = 0; i < W; i++)
                if (v[i]) count_zeroMSB = WL2'(W - 1 - i);
        end
    endfunction
    wire [WL2-1:0] shift_yc = count_zeroMSB(y_eff);

    // csa instances
    qsel inst_qsel (.r5(r6[5] ? ~r6[4:0] : r6[4:0]), .y4(y_norm[W-1:W-4]), .q({q1, q0}));
    csa_div #(W+3) csa1 (.sub(1'b0), .a(rxq[W2+1:W-1]), .b({3'b0, y_norm}), .cin({c[W+1:0], 1'b0}), .s(sa1), .cout(ca1));
    csa_div #(W+3) css1 (.sub(1'b1), .a(rxq[W2+1:W-1]), .b({3'b0, y_norm}), .cin({c[W+1:0], 1'b0}), .s(ss1), .cout(cs1));
    csa_div #(W+3) csa  (.sub(1'b0), .a(rxq[W2:W-2]), .b({3'b0, y_norm}), .cin({c[W:0], 2'b0}), .s(sa), .cout(ca));
    csa_div #(W+3) css  (.sub(1'b1), .a(rxq[W2:W-2]), .b({3'b0, y_norm}), .cin({c[W:0], 2'b0}), .s(ss), .cout(cs));
    csa_div #(W+3) csa2 (.sub(1'b0), .a(rxq[W2:W-2]), .b({2'b0, y_norm, 1'b0}), .cin({c[W:0], 2'b0}), .s(sa2), .cout(ca2));
    csa_div #(W+3) css2 (.sub(1'b1), .a(rxq[W2:W-2]), .b({2'b0, y_norm, 1'b0}), .cin({c[W:0], 2'b0}), .s(ss2), .cout(cs2));

    // fsm
    logic [WL2-1:0] counter;
    typedef enum logic [1:0] {IDLE, RUN, DONE} State;
    State state;

    always_ff @(posedge clk) begin : FSM
        if (reset) begin
            state <= IDLE;
            counter <= 0;
            rxq <= 0;
            c <= 0;
            qn <= 0;
            busy <= 0;
            done <= 0;
            div_zero <= 0;
        end 
        
        else begin
            case (state)
                IDLE: begin
                    busy <= 0;
                    done <= 0;

                    if (start) begin
                        busy <= 1;
                        div_zero <= 0;
                        counter <= 0;

                        if (y == 0) begin
                            rxq <= 0;
                            div_zero <= 1;
                            state <= DONE;
                        end 
                        
                        else if (y_eff == 1) begin
                            rxq[W-1:0] <= negate_q ? -x_eff : x_eff;
                            rxq[W2+2:W] <= '0;
                            state <= DONE;
                        end 
                        
                        else begin
                            shift_y <= shift_yc;
                            y_norm <= W'(y_eff << shift_yc);
                            rxq <= (W2+3)'(x_eff << shift_yc);
                            c <= 0;
                            qn <= 0;
                            state <= RUN;
                        end
                    end
                end

                RUN: begin
                    if (counter == ((W/2) + (W%2))) begin
                        rxq[W-1:0] <= negate_q ? -q_corr : q_corr;
                        rxq[W2-1:W] <= (negate_r && r_mag != 0) ? -r_mag : r_mag;
                        done <= 1;
                        counter <= 0;
                        state <= DONE;
                    end

                    else if (counter == W/2 && (W%2)) begin
                        case ({q_sign, q1, q0})
                            3'b000: begin
                                rxq <= {rxq[W2+1:0], 1'b0};
                                c <= {c[W+1:0], 1'b0};
                                qn <= {qn[W-2:0], 1'b1};
                            end

                            3'b001, 3'b010: begin
                                rxq <= {ss1, rxq[W-2:0], 1'b1};
                                c <= cs1;
                                qn <= {rxq[W-2:0], 1'b0};
                            end

                            3'b101, 3'b110: begin
                                rxq <= {sa1, qn[W-2:0], 1'b1};
                                c <= ca1;
                                qn <= {qn[W-2:0], 1'b0};
                            end

                            default: begin
                                rxq <= rxq;
                                c <= c;
                                qn <= qn;
                            end
                        endcase

                        state <= RUN;
                        counter <= counter + 1;
                    end

                    else begin
                        case ({q_sign, q1, q0})
                            3'b000: begin
                                rxq <= {rxq[W2:0], 2'b00};
                                c <= {c[W:0], 2'b00};
                                qn <= {qn[W-3:0], 2'b11};
                            end

                            3'b001: begin
                                rxq <= {ss,  rxq[W-3:0], 2'b01};
                                c <= cs;
                                qn <= {rxq[W-3:0], 2'b00};
                            end

                            3'b010: begin
                                rxq <= {ss2, rxq[W-3:0], 2'b10};
                                c <= cs2;
                                qn <= {rxq[W-3:0], 2'b01};
                            end

                            3'b101: begin
                                rxq <= {sa,  qn[W-3:0], 2'b11};
                                c <= ca;
                                qn <= {qn[W-3:0], 2'b10};
                            end

                            3'b110: begin
                                rxq <= {sa2, qn[W-3:0], 2'b10};
                                c <= ca2;
                                qn <= {qn[W-3:0], 2'b01};
                            end

                            default: begin
                                rxq <= rxq;
                                c <= c;
                                qn <= qn;
                            end
                        endcase

                        counter <= counter + 1;
                    end
                end

                DONE: begin
                    busy <= 0;
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
