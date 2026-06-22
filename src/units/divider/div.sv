module div #(
    parameter W = 32
)(
    // sync
    input logic clk, reset,

    // inputs
    input logic start, sign_x, sign_y,
    input logic [W-1:0] x, y,

    // outputs
    output logic [W-1:0] q, r,
    output logic busy, done
);
    localparam W2 = W * 2;
    localparam WL2 = $clog2(W);

    // normalize signs
    wire [W-1:0] x_eff = (x[W-1] & sign_x) ? -x : x;
    wire [W-1:0] y_eff = (y[W-1] & sign_y) ? -y : y;

    // state registers
    logic [W2+2:0] rxq; // partial remainder (upper) + quotient (lower)
    logic [W+2:0] c; // csa carries
    logic [WL2-1:0] shift_y;
    logic [W-1:0] y_norm;
    logic [W-1:0] qn;

    // csa outputs
    wire [W+2:0] sa,  ca;   // add y
    wire [W+2:0] ss,  cs;   // sub y
    wire [W+2:0] sa2, ca2;  // add 2y
    wire [W+2:0] ss2, cs2;  // sub 2y
    wire [W+2:0] sa1, ca1;  // add y (odd)
    wire [W+2:0] ss1, cs1;  // sub y (odd)

    // digit selection
    wire [7:0] r8 = rxq[W2:W2-7] + c[W:W-7];
    wire [5:0] r6 = r8[7:2];

    wire [1:0] qd;
    wire q0 = qd[0];
    wire q1 = qd[1];
    wire q_sign = r6[5] & (q0 | q1);

    // pipeline registers
    logic q0_r, q1_r, q_sign_r;
    wire  q0_c = q0_r; // registered digit drives the mux
    wire  q1_c = q1_r;
    wire  q_sign_c = q_sign_r;

    // predicts the next iteration's qsel digit one cycle ahead so
    // the qsel lookup is off the critical path
    wire [7:0] r8_next2;          // 8-bit prediction window from post-step rem+c
    wire [5:0] r6_next2;          // truncated form fed to qsel
    wire [1:0] qd_next2;          // predicted digit magnitude (0/1/2)
    wire q0_next2 = qd_next2[0];
    wire q1_next2 = qd_next2[1];
    wire q_sign_next2 = r6_next2[5] & (q1_next2 | q0_next2);  // negative-digit flag

    wire [7:0] r8_next1;
    wire [5:0] r6_next1;
    wire [1:0] qd_next1;
    wire q0_next1 = qd_next1[0];
    wire q1_next1 = qd_next1[1];
    wire q_sign_next1 = r6_next1[5] & (q1_next1 | q0_next1);

    // leading zero counts
    function automatic [WL2-1:0] count_zeroMSB(input [W-1:0] v);
        integer i;
        begin
            count_zeroMSB = WL2'(W);
            for (i = 0; i < W; i++)
                if (v[i]) count_zeroMSB = WL2'(W - 1 - i);
        end
    endfunction
    wire [WL2-1:0] shift_yc = count_zeroMSB(y_eff);

    // correction logic
    // -> correct1 in
    wire [W+2:0] pr = rxq[W2+2:W] + c[W+2:0];
    wire [W+2:0] pr_corr = pr[W+2] ? pr + {{3{1'b0}}, y_norm} : pr;

    // -> correct1 out
    logic [W+2:0] pr_r;
    logic [W+2:0] pr_corr_r;

    // -> correct2 in
    wire [W-1:0]  r_unnorm = W'(pr_corr_r >> shift_y);

    // -> correct2 out
    logic [W-1:0] r_unnorm_r;  // registered at end of CORRECT2

    // -> correct3 out
    wire r_overshoot_c = (r_unnorm_r >= y_eff);
    wire [W-1:0] r_mag_c = r_unnorm_r - y_eff;
    wire [W-1:0] quot_pre_c = rxq[W-1:0] - {{(W-1){1'b0}}, pr_r[W+2]};

    // -> correct3 out
    logic r_overshoot_r;
    logic [W-1:0] r_mag_r;
    logic [W-1:0] quot_pre_r;

    // -> correct4 in
    wire [W-1:0] q_corr = quot_pre_r + {{(W-1){1'b0}}, r_overshoot_r};
    wire [W-1:0] r_mag_final = r_overshoot_r ? r_mag_r : r_unnorm_r;

    // sign-correction bits
    logic negate_r, negate_q;
    wire negate_r_c = sign_x & x[W-1];
    wire negate_q_c = negate_r_c ^ (sign_y & y[W-1]);

    // outputs
    assign q = rxq[W-1:0];
    assign r = rxq[W2-1:W];

    // qsel instance
    qsel inst_qsel (
        .r5(r6[5] ? ~r6[4:0] : r6[4:0]),
        .y4(y_norm[W-1:W-4]),
        .q(qd)
    );

    // csa instances
    csa #(.W(W+3)) csa1 (.sub(1'b0), .a(rxq[W2+1:W-1]), .b({3'b0, y_norm}),       .cin({c[W+1:0], 1'b0}), .s(sa1), .cout(ca1));
    csa #(.W(W+3)) css1 (.sub(1'b1), .a(rxq[W2+1:W-1]), .b({3'b0, y_norm}),       .cin({c[W+1:0], 1'b0}), .s(ss1), .cout(cs1));
    csa #(.W(W+3)) csa_ (.sub(1'b0), .a(rxq[W2:W-2]),   .b({3'b0, y_norm}),       .cin({c[W:0],   2'b0}), .s(sa),  .cout(ca));
    csa #(.W(W+3)) css_ (.sub(1'b1), .a(rxq[W2:W-2]),   .b({3'b0, y_norm}),       .cin({c[W:0],   2'b0}), .s(ss),  .cout(cs));
    csa #(.W(W+3)) csa2 (.sub(1'b0), .a(rxq[W2:W-2]),   .b({2'b0, y_norm, 1'b0}), .cin({c[W:0],   2'b0}), .s(sa2), .cout(ca2));
    csa #(.W(W+3)) css2 (.sub(1'b1), .a(rxq[W2:W-2]),   .b({2'b0, y_norm, 1'b0}), .cin({c[W:0],   2'b0}), .s(ss2), .cout(cs2));

    // current and registered SRT4 digit. encoding: {q_sign, q1, q0}
    //   000 = +0    001 = +1    010 = +2
    //   101 = -1    110 = -2    others = unused
    wire [2:0] digit   = {q_sign,   q1,   q0};
    wire [2:0] digit_r = {q_sign_r, q1_r, q0_r};

    // 2-digit step
    logic [W2+2:0] rxq_next_2;
    logic [W+2:0] c_next_2;
    logic [W-1:0] qn_next_2;
    always_comb begin
        unique case (digit_r)
            3'b000: begin
                rxq_next_2 = {rxq[W2:0],       2'b00};
                c_next_2   = {c[W:0],          2'b00};
                qn_next_2  = {qn[W-3:0],       2'b11};
            end
            3'b001: begin
                rxq_next_2 = {ss,  rxq[W-3:0], 2'b01};
                c_next_2   = cs;
                qn_next_2  = {rxq[W-3:0],      2'b00};
            end
            3'b010: begin
                rxq_next_2 = {ss2, rxq[W-3:0], 2'b10};
                c_next_2   = cs2;
                qn_next_2  = {rxq[W-3:0],      2'b01};
            end
            3'b101: begin
                rxq_next_2 = {sa,  qn[W-3:0],  2'b11};
                c_next_2   = ca;
                qn_next_2  = {qn[W-3:0],       2'b10};
            end
            3'b110: begin
                rxq_next_2 = {sa2, qn[W-3:0],  2'b10};
                c_next_2   = ca2;
                qn_next_2  = {qn[W-3:0],       2'b01};
            end
            default: begin
                rxq_next_2 = rxq;
                c_next_2   = c;
                qn_next_2  = qn;
            end
        endcase
    end

    // 1-digit step
    logic [W2+2:0] rxq_next_1;
    logic [W+2:0] c_next_1;
    logic [W-1:0] qn_next_1;
    always_comb begin
        unique case (digit_r)
            3'b000: begin
                rxq_next_1 = {rxq[W2+1:0],     1'b0};
                c_next_1   = {c[W+1:0],        1'b0};
                qn_next_1  = {qn[W-2:0],       1'b0};
            end
            3'b001, 3'b010: begin
                rxq_next_1 = {ss1, rxq[W-2:0], 1'b1};
                c_next_1   = cs1;
                qn_next_1  = {rxq[W-2:0],      1'b0};
            end
            3'b101, 3'b110: begin
                rxq_next_1 = {sa1, qn[W-2:0],  1'b1};
                c_next_1   = ca1;
                qn_next_1  = {qn[W-2:0],       1'b0};
            end
            default: begin
                rxq_next_1 = rxq;
                c_next_1   = c;
                qn_next_1  = qn;
            end
        endcase
    end

    // lookahead computation
    assign r8_next2 = rxq_next_2[W2:W2-7] + c_next_2[W:W-7];
    assign r6_next2 = r8_next2[7:2];
    qsel u_qsel_next2 (
        .r5(r6_next2[5] ? ~r6_next2[4:0] : r6_next2[4:0]),
        .y4(y_norm[W-1:W-4]),
        .q(qd_next2)
    );

    assign r8_next1 = rxq_next_1[W2:W2-7] + c_next_1[W:W-7];
    assign r6_next1 = r8_next1[7:2];
    qsel u_qsel_next1 (
        .r5(r6_next1[5] ? ~r6_next1[4:0] : r6_next1[4:0]),
        .y4(y_norm[W-1:W-4]),
        .q(qd_next1)
    );

    // fsm logic
    logic [WL2-1:0] counter;
    typedef enum logic [3:0] {IDLE, START, RUN, CORRECT1, CORRECT2, CORRECT3, CORRECT4, DONE} State;
    State state, next_state;

    assign busy = (state != IDLE);
    assign done = (state == DONE);

    // y=0 and |y|=1 are handled with single-cycle shortcuts
    wire run_done    = (counter == WL2'(W/2 + (W%2)));
    wire div_zero    = (y == '0);
    wire div_unit    = (y_eff == {{(W-1){1'b0}}, 1'b1});

    always_comb begin
        next_state = state;
        unique case (state)
            IDLE: if (start)      next_state = (div_zero | div_unit) ? DONE : START;
            START:                next_state = RUN;
            RUN:  if (run_done)   next_state = CORRECT1;
            CORRECT1:             next_state = CORRECT2;
            CORRECT2:             next_state = CORRECT3;
            CORRECT3:             next_state = CORRECT4;
            CORRECT4:             next_state = DONE;
            DONE:                 next_state = IDLE;
            default:              next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) state <= IDLE;
        else state <= next_state;
    end

    always_ff @(posedge clk) begin : datapath
        if (reset) begin
            counter <= '0;
            rxq <= '0;
            c <= '0;
            qn <= '0;
            q0_r <= 1'b0;
            q1_r <= 1'b0;
            q_sign_r <= 1'b0;
            pr_r <= '0;
            pr_corr_r <= '0;
            r_unnorm_r <= '0;
            r_overshoot_r <= 1'b0;
            r_mag_r <= '0;
            quot_pre_r <= '0;
            negate_r <= 1'b0;
            negate_q <= 1'b0;
        end

        else begin
            case (state)
                IDLE: if (start) begin
                    counter  <= '0;
                    negate_r <= negate_r_c;
                    negate_q <= negate_q_c;

                    if (div_zero) begin
                        // RV32M divide-by-zero: 
                        // DIV/DIVU -> -1 (in quotient slot)
                        // REM/REMU -> dividend (in remainder slot)
                        rxq <= {3'b0, x, {W{1'b1}}};
                    end

                    else if (div_unit) begin
                        rxq[W-1:0]  <= negate_q_c ? -x_eff : x_eff;
                        rxq[W2+2:W] <= '0;
                    end

                    else begin
                        shift_y <= shift_yc;
                        y_norm  <= W'(y_eff << shift_yc);
                        rxq     <= (W2+3)'(x_eff << shift_yc);
                        c       <= '0;
                        qn      <= '0;
                    end
                end

                START: begin
                    q0_r <= q0;
                    q1_r <= q1;
                    q_sign_r <= q_sign;
                end

                RUN: begin
                    if (run_done) begin
                        counter <= '0;
                    end

                    // 1-digit step
                    else if ((W % 2 == 1) && (counter == WL2'(W/2))) begin
                        rxq <= rxq_next_1;
                        c <= c_next_1;
                        qn <= qn_next_1;
                        q0_r <= q0_next1;
                        q1_r <= q1_next1;
                        q_sign_r <= q_sign_next1;
                        counter <= counter + 1'b1;
                    end

                    // 2-digit step
                    else begin
                        rxq <= rxq_next_2;
                        c <= c_next_2;
                        qn <= qn_next_2;
                        q0_r <= q0_next2;
                        q1_r <= q1_next2;
                        q_sign_r <= q_sign_next2;
                        counter <= counter + 1'b1;
                    end
                end

                CORRECT1: begin
                    pr_r <= pr;
                    pr_corr_r <= pr_corr;
                end

                CORRECT2: r_unnorm_r <= r_unnorm;

                CORRECT3: begin
                    r_overshoot_r <= r_overshoot_c;
                    r_mag_r <= r_mag_c;
                    quot_pre_r <= quot_pre_c;
                end

                CORRECT4: begin
                    rxq[W-1:0]  <= negate_q ? -q_corr : q_corr;
                    rxq[W2-1:W] <= (negate_r && r_mag_final != '0) ? -r_mag_final : r_mag_final;
                end

                default: ;
            endcase
        end
    end
endmodule
