module csa_div #(
    parameter W = 32
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
    assign cout[W-1:2] = (a[W-2:1] & b_eff[W-2:1]) | 
                         (a[W-2:1] & cin[W-2:1]) | 
                         (b_eff[W-2:1] & cin[W-2:1]);
endmodule

module div #(
    parameter W = 32
)(
    input logic clk, reset, start, sign_x, sign_y,
    input logic [W-1:0] x, y,
    output logic [W-1:0] q, r,
    output logic busy, done, div_zero
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

    // lookahead
    wire [7:0] r8_next2;          // r8 from post-step rem/c
    wire [5:0] r6_next2;
    wire [1:0] qd_next2;
    wire q0_next2 = qd_next2[0];
    wire q1_next2 = qd_next2[1];
    wire q_sign_next2 = r6_next2[5] & (q1_next2 | q0_next2);

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

    // outputs
    wire negate_r = sign_x & x[W-1];
    wire negate_q = negate_r ^ (sign_y & y[W-1]);
    assign q = rxq[W-1:0];
    assign r = rxq[W2-1:W];

    // qsel instance
    qsel inst_qsel (
        .r5(r6[5] ? ~r6[4:0] : r6[4:0]),
        .y4(y_norm[W-1:W-4]),
        .q(qd)
    );

    // csa instances
    csa_div #(W+3) csa1 (.sub(1'b0), .a(rxq[W2+1:W-1]), .b({3'b0, y_norm}), .cin({c[W+1:0], 1'b0}), .s(sa1), .cout(ca1));
    csa_div #(W+3) css1 (.sub(1'b1), .a(rxq[W2+1:W-1]), .b({3'b0, y_norm}), .cin({c[W+1:0], 1'b0}), .s(ss1), .cout(cs1));
    csa_div #(W+3) csa  (.sub(1'b0), .a(rxq[W2:W-2]), .b({3'b0, y_norm}), .cin({c[W:0], 2'b0}), .s(sa), .cout(ca));
    csa_div #(W+3) css  (.sub(1'b1), .a(rxq[W2:W-2]), .b({3'b0, y_norm}), .cin({c[W:0], 2'b0}), .s(ss), .cout(cs));
    csa_div #(W+3) csa2 (.sub(1'b0), .a(rxq[W2:W-2]), .b({2'b0, y_norm, 1'b0}), .cin({c[W:0], 2'b0}), .s(sa2), .cout(ca2));
    csa_div #(W+3) css2 (.sub(1'b1), .a(rxq[W2:W-2]), .b({2'b0, y_norm, 1'b0}), .cin({c[W:0], 2'b0}), .s(ss2), .cout(cs2));

    // one-host mux
    wire [2:0] digit = {q_sign, q1, q0};
    wire [2:0] digit_r = {q_sign_r, q1_r, q0_r};
    wire sel_000 = (digit_r == 3'b000);
    wire sel_001 = (digit_r == 3'b001);
    wire sel_010 = (digit_r == 3'b010);
    wire sel_101 = (digit_r == 3'b101);
    wire sel_110 = (digit_r == 3'b110);
    wire sel_def = ~(sel_000|sel_001|sel_010|sel_101|sel_110);

    // rxq next state
    wire [W2+2:0] rxq_next_2 =
        ({(W2+3){sel_000}} & {rxq[W2:0],       2'b00}) |
        ({(W2+3){sel_001}} & {ss,  rxq[W-3:0], 2'b01}) |
        ({(W2+3){sel_010}} & {ss2, rxq[W-3:0], 2'b10}) |
        ({(W2+3){sel_101}} & {sa,  qn[W-3:0],  2'b11}) |
        ({(W2+3){sel_110}} & {sa2, qn[W-3:0],  2'b10}) |
        ({(W2+3){sel_def}} & rxq);

    wire [W+2:0] c_next_2 =
        ({(W+3){sel_000}} & {c[W:0],   2'b00}) |
        ({(W+3){sel_001}} & cs)                |
        ({(W+3){sel_010}} & cs2)               |
        ({(W+3){sel_101}} & ca)                |
        ({(W+3){sel_110}} & ca2)               |
        ({(W+3){sel_def}} & c);

    wire [W-1:0] qn_next_2 =
        ({W{sel_000}} & {qn[W-3:0],  2'b11}) |
        ({W{sel_001}} & {rxq[W-3:0], 2'b00}) |
        ({W{sel_010}} & {rxq[W-3:0], 2'b01}) |
        ({W{sel_101}} & {qn[W-3:0],  2'b10}) |
        ({W{sel_110}} & {qn[W-3:0],  2'b01}) |
        ({W{sel_def}} & qn);

    // one-hot mux
    wire sel1_000 = (digit_r == 3'b000);
    wire sel1_sub = ((digit_r == 3'b001) | (digit_r == 3'b010));
    wire sel1_add = ((digit_r == 3'b101) | (digit_r == 3'b110));
    wire sel1_def = ~(sel1_000 | sel1_sub | sel1_add);

    wire [W2+2:0] rxq_next_1 =
        ({(W2+3){sel1_000}} & {rxq[W2+1:0],    1'b0})  |
        ({(W2+3){sel1_sub}} & {ss1, rxq[W-2:0], 1'b1}) |
        ({(W2+3){sel1_add}} & {sa1, qn[W-2:0],  1'b1}) |
        ({(W2+3){sel1_def}} & rxq);

    wire [W+2:0] c_next_1 =
        ({(W+3){sel1_000}} & {c[W+1:0], 1'b0}) |
        ({(W+3){sel1_sub}} & cs1) |
        ({(W+3){sel1_add}} & ca1) |
        ({(W+3){sel1_def}} & c);

    wire [W-1:0] qn_next_1 =
        ({W{sel1_000}} & {qn[W-2:0], 1'b0}) |
        ({W{sel1_sub}} & {rxq[W-2:0], 1'b0}) |
        ({W{sel1_add}} & {qn[W-2:0], 1'b0}) |
        ({W{sel1_def}} & qn);

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
        .r5 (r6_next1[5] ? ~r6_next1[4:0] : r6_next1[4:0]),
        .y4 (y_norm[W-1:W-4]),
        .q  (qd_next1)
    );

    // fsm logic
    logic [WL2-1:0] counter;
    typedef enum logic [3:0] {IDLE, START, RUN, CORRECT1, CORRECT2, CORRECT3, CORRECT4, DONE} State;
    State state;

    always_ff @(posedge clk) begin : FSM
        if (reset) begin
            state <= IDLE;
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
            busy <= 1'b0;
            done <= 1'b0;
            div_zero <= 1'b0;
        end

        else begin
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    done <= 1'b0;

                    if (start) begin
                        busy     <= 1'b1;
                        div_zero <= 1'b0;
                        counter  <= '0;

                        if (y == '0) begin
                            // RV32M divide-by-zero results:
                            //   DIV/DIVU -> -1 (all-ones in quotient slot)
                            //   REM/REMU -> dividend x (in remainder slot)
                            rxq      <= {3'b0, x, {W{1'b1}}};
                            div_zero <= 1'b1;
                            state    <= DONE;
                        end

                        else if (y_eff == {{(W-1){1'b0}}, 1'b1}) begin
                            rxq[W-1:0]   <= negate_q ? -x_eff : x_eff;
                            rxq[W2+2:W]  <= '0;
                            state        <= DONE;
                        end

                        else begin
                            // Action 5: written once, stable through START+RUN.
                            shift_y <= shift_yc;
                            y_norm  <= W'(y_eff << shift_yc);
                            rxq     <= (W2+3)'(x_eff << shift_yc);
                            c       <= '0;
                            qn      <= '0;
                            state   <= START;
                        end
                    end
                end

                START: begin
                    q0_r <= q0;
                    q1_r <= q1;
                    q_sign_r <= q_sign;
                    state <= RUN;
                end

                RUN: begin
                    if (counter == WL2'(W/2 + (W%2))) begin
                        counter <= '0;
                        state <= CORRECT1;
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

                // correction states
                CORRECT1: begin
                    pr_r <= pr;
                    pr_corr_r <= pr_corr;
                    state <= CORRECT2;
                end

                CORRECT2: begin
                    r_unnorm_r <= r_unnorm;
                    state <= CORRECT3;
                end

                CORRECT3: begin
                    r_overshoot_r <= r_overshoot_c;
                    r_mag_r <= r_mag_c;
                    quot_pre_r <= quot_pre_c;
                    state <= CORRECT4;
                end

                CORRECT4: begin
                    rxq[W-1:0] <= negate_q ? -q_corr : q_corr;
                    rxq[W2-1:W] <= (negate_r && r_mag_final != '0) ? -r_mag_final : r_mag_final;
                    done <= 1'b1;
                    state <= DONE;
                end

                DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
