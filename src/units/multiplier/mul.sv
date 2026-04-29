import unit_pkg::*;

module mul_csa #(
    parameter W = 68
)(
    input logic [W-1:0] a, b, cin,
    output logic [W-1:0] s,
    output logic [W-1:0] cout
);
    logic [W-1:0] c;
    assign s = a ^ b ^ cin;
    assign c = (a & b) | (a & cin) | (b & cin);
    assign cout = {c[W-2:0], 1'b0};
endmodule

module mul (
    input logic clk, reset,
    input logic signed_in,
    input logic valid_in,
    input logic [31:0] x, y,
    output logic [63:0] p,
    output logic valid_out
);
    wire [33:0] x_eff = {{2{signed_in & x[31]}}, x};
    wire [33:0] y_eff = {{2{signed_in & y[31]}}, y};

    // magnitudes
    wire [33:0] mag1 = x_eff;
    wire [33:0] mag2 = x_eff << 1;

    // recode
    booth_recode_t rc [0:16];
    recode #(.W(34)) u_recode (.q(y_eff), .r(rc));

    // partial products
    logic pp_neg [0:16];
    logic [33:0] pp [0:16];
    always_comb begin
        for (int i = 0; i <= 16; i++) begin
            unique case (rc[i])
                BOOTH_POS1: begin 
                    pp[i] = mag1; 
                    pp_neg[i] = 0; 
                end

                BOOTH_NEG1: begin 
                    pp[i] = ~mag1; 
                    pp_neg[i] = 1; 
                end

                BOOTH_POS2: begin 
                    pp[i] = mag2; 
                    pp_neg[i] = 0; 
                end

                BOOTH_NEG2: begin 
                    pp[i] = ~mag2; 
                    pp_neg[i] = 1; 
                end

                default: begin 
                    pp[i] = '0;
                    pp_neg[i] = 0; 
                end
            endcase
        end
    end

    // correction vector
    wire [67:0] corr = (
        (68'(pp_neg[0]) << 0) | (68'(pp_neg[1]) << 2) |
        (68'(pp_neg[2]) << 4) | (68'(pp_neg[3]) << 6) |
        (68'(pp_neg[4]) << 8) | (68'(pp_neg[5]) << 10) |
        (68'(pp_neg[6]) << 12) | (68'(pp_neg[7]) << 14) |
        (68'(pp_neg[8]) << 16) | (68'(pp_neg[9]) << 18) |
        (68'(pp_neg[10]) << 20) | (68'(pp_neg[11]) << 22) |
        (68'(pp_neg[12]) << 24) | (68'(pp_neg[13]) << 26) |
        (68'(pp_neg[14]) << 28) | (68'(pp_neg[15]) << 30) |
        (68'(pp_neg[16]) << 32)
    );

    // wallace tree inputs
    logic [67:0] wa, wb, wc, wd, we, wf, wg, wh, wi, wj, wk, wl, wm, wn, wo, wp, wq, wcorr;

    // stage 1 — recode + expand partial products
    logic s1_valid;
    always_ff @(posedge clk) begin
        if (reset) s1_valid <= 0;
        else begin
            s1_valid <= valid_in;
            wa <= 68'(signed'(pp[0]));
            wb <= 68'(signed'({pp[1], 2'b0}));
            wc <= 68'(signed'({pp[2], 4'b0}));
            wd <= 68'(signed'({pp[3], 6'b0}));
            we <= 68'(signed'({pp[4], 8'b0}));
            wf <= 68'(signed'({pp[5], 10'b0}));
            wg <= 68'(signed'({pp[6], 12'b0}));
            wh <= 68'(signed'({pp[7], 14'b0}));
            wi <= 68'(signed'({pp[8], 16'b0}));
            wj <= 68'(signed'({pp[9], 18'b0}));
            wk <= 68'(signed'({pp[10], 20'b0}));
            wl <= 68'(signed'({pp[11], 22'b0}));
            wm <= 68'(signed'({pp[12], 24'b0}));
            wn <= 68'(signed'({pp[13], 26'b0}));
            wo <= 68'(signed'({pp[14], 28'b0}));
            wp <= 68'(signed'({pp[15], 30'b0}));
            wq <= 68'(signed'({pp[16], 32'b0}));
            wcorr <= corr;
        end
    end

    // layer 1
    logic [67:0] ws1, wc1, ws2, wc2, ws3, wc3, ws4, wc4, ws5, wc5, ws6, wc6;
    mul_csa csa1 (.a(wa), .b(wb), .cin(wc), .s(ws1), .cout(wc1));
    mul_csa csa2 (.a(wd), .b(we), .cin(wf), .s(ws2), .cout(wc2));
    mul_csa csa3 (.a(wg), .b(wh), .cin(wi), .s(ws3), .cout(wc3));
    mul_csa csa4 (.a(wj), .b(wk), .cin(wl), .s(ws4), .cout(wc4));
    mul_csa csa5 (.a(wm), .b(wn), .cin(wo), .s(ws5), .cout(wc5));
    mul_csa csa6 (.a(wp), .b(wq), .cin(wcorr), .s(ws6), .cout(wc6));

    // layer 2
    logic [67:0] ws7, wc7, ws8, wc8, ws9, wc9, ws10, wc10;
    mul_csa csa7 (.a(ws1), .b(wc1), .cin(ws2), .s(ws7), .cout(wc7));
    mul_csa csa8 (.a(wc2), .b(ws3), .cin(wc3), .s(ws8), .cout(wc8));
    mul_csa csa9 (.a(ws4), .b(wc4), .cin(ws5), .s(ws9), .cout(wc9));
    mul_csa csa10 (.a(wc5), .b(ws6), .cin(wc6), .s(ws10), .cout(wc10));

    // stage 2 register
    logic s2_valid;
    logic [67:0] s2_ws7, s2_wc7, s2_ws8, s2_wc8, s2_ws9, s2_wc9, s2_ws10, s2_wc10;
    always_ff @(posedge clk) begin
        if (reset) s2_valid <= 0;
        else begin
            s2_valid <= s1_valid;
            s2_ws7 <= ws7;
            s2_wc7 <= wc7;
            s2_ws8 <= ws8;  
            s2_wc8 <= wc8;
            s2_ws9 <= ws9;  
            s2_wc9 <= wc9;
            s2_ws10 <= ws10; 
            s2_wc10 <= wc10;
        end
    end

    // layer 3
    logic [67:0] ws11, wc11, ws12, wc12;
    mul_csa csa11 (.a(s2_ws7), .b(s2_wc7), .cin(s2_ws8), .s(ws11), .cout(wc11));
    mul_csa csa12 (.a(s2_wc8), .b(s2_ws9), .cin(s2_wc9), .s(ws12), .cout(wc12));

    // layer 4
    logic [67:0] ws13, wc13, ws14, wc14;
    mul_csa csa13 (.a(ws11), .b(wc11), .cin(ws12), .s(ws13), .cout(wc13));
    mul_csa csa14 (.a(wc12), .b(s2_ws10), .cin(s2_wc10), .s(ws14), .cout(wc14));

    // stage 3 register
    logic s3_valid;
    logic [67:0] s3_ws13, s3_wc13, s3_ws14, s3_wc14;
    always_ff @(posedge clk) begin
        if (reset) s3_valid <= 0;
        else begin
            s3_valid <= s2_valid;
            s3_ws13 <= ws13; 
            s3_wc13 <= wc13;
            s3_ws14 <= ws14; 
            s3_wc14 <= wc14;
        end
    end

    // layer 5
    logic [67:0] ws15, wc15;
    mul_csa csa15 (.a(s3_ws13), .b(s3_wc13), .cin(s3_ws14), .s(ws15), .cout(wc15));

    // layer 6
    logic [67:0] ws16, wc16;
    mul_csa csa16 (.a(ws15), .b(wc15), .cin(s3_wc14), .s(ws16), .cout(wc16));

    // stage 4 register
    logic s4_valid;
    logic [67:0] s4_s, s4_c;
    always_ff @(posedge clk) begin
        if (reset) s4_valid <= 0;
        else begin
            s4_valid <= s3_valid;
            s4_s <= ws16;
            s4_c <= wc16;
        end
    end

    // stage 5 (adder)
    wire [63:0] sum = s4_s[63:0] + s4_c[63:0];
    always_ff @(posedge clk) begin
        if (reset) valid_out <= 0;
        else p <= sum;
    end
endmodule
