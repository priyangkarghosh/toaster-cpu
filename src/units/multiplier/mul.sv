import unit_pkg::*;

module mul (
    input logic clk, reset,
    input logic signed_in,
    input logic valid_in,
    input logic [31:0] x, y,
    output logic [63:0] p,
    output logic valid_out
);
    // sign extend inputs
    wire [33:0] x_eff = {{2{signed_in & x[31]}}, x};
    wire [33:0] y_eff = {{2{signed_in & y[31]}}, y};

    // partial products
    wire [33:0] pos1 = x_eff;
    wire [33:0] neg1 = -x_eff;
    wire [33:0] pos2 = pos1 << 1;
    wire [33:0] neg2 = neg1 << 1;

    // recode y
    booth_recode_t rc [0:16];
    recode #(.W(34)) u_recode (.q(y_eff), .r(rc));

    // partial product generation
    logic [33:0] pp [0:16];
    always_comb begin
        for (int i = 0; i <= 16; i++) begin
            unique case (rc[i])
                BOOTH_POS1: pp[i] = pos1;
                BOOTH_NEG1: pp[i] = neg1;
                BOOTH_POS2: pp[i] = pos2;
                BOOTH_NEG2: pp[i] = neg2;
                default:    pp[i] = '0;
            endcase
        end
    end

    // wallace tree
    // > inputs
    logic [67:0] wa, wb, wc, wd, we, wf, wg, wh, wi, wj, wk, wl, wm, wn, wo, wp, wq;

    // > layer 1
    logic [67:0] ws1, ws2, ws3, ws4, ws5;
    logic [67:0] wc1, wc2, wc3, wc4, wc5;
    csa csa1(.a(wa), .b(wb), .cin(wc), .s(ws1), .cout(wc1));
    csa csa2(.a(wd), .b(we), .cin(wf), .s(ws2), .cout(wc2));
    csa csa3(.a(wg), .b(wh), .cin(wi), .s(ws3), .cout(wc3));
    csa csa4(.a(wj), .b(wk), .cin(wl), .s(ws4), .cout(wc4));
    csa csa5(.a(wm), .b(wn), .cin(wo), .s(ws5), .cout(wc5));

    // > layer 2
    logic [67:0] ws6, ws7, ws8, ws9;
    logic [67:0] wc6, wc7, wc8, wc9;
    csa csa6(.a(ws1), .b(wc1), .cin(ws2), .s(ws6), .cout(wc6));
    csa csa7(.a(wc2), .b(ws3), .cin(wc3), .s(ws7), .cout(wc7));
    csa csa8(.a(ws4), .b(wc4), .cin(ws5), .s(ws8), .cout(wc8));
    csa csa9(.a(wc5), .b(wp),  .cin(wq),  .s(ws9), .cout(wc9));

    // stage 1 (recoding)
    logic s1_valid;
    always_ff @(posedge clk) begin
        if (reset) s1_valid <= 0;
        else begin
            s1_valid <= valid_in;
            wa <= 68'(signed'(pp[0]));
            wb <= 68'(signed'({pp[1],  2'b0}));
            wc <= 68'(signed'({pp[2],  4'b0}));
            wd <= 68'(signed'({pp[3],  6'b0}));
            we <= 68'(signed'({pp[4],  8'b0}));
            wf <= 68'(signed'({pp[5],  10'b0}));
            wg <= 68'(signed'({pp[6],  12'b0}));
            wh <= 68'(signed'({pp[7],  14'b0}));
            wi <= 68'(signed'({pp[8],  16'b0}));
            wj <= 68'(signed'({pp[9],  18'b0}));
            wk <= 68'(signed'({pp[10], 20'b0}));
            wl <= 68'(signed'({pp[11], 22'b0}));
            wm <= 68'(signed'({pp[12], 24'b0}));
            wn <= 68'(signed'({pp[13], 26'b0}));
            wo <= 68'(signed'({pp[14], 28'b0}));
            wp <= 68'(signed'({pp[15], 30'b0}));
            wq <= 68'(signed'({pp[16], 32'b0}));
        end
    end

    // stage 2 (tree layers 1-2)
    logic s2_valid;
    logic [67:0] s2_ws6, s2_wc6, s2_ws7, s2_wc7, s2_ws8, s2_wc8, s2_ws9, s2_wc9;
    always_ff @(posedge clk) begin
        if (reset) s2_valid <= 0;
        else begin
            s2_valid <= s1_valid;
            s2_ws6 <= ws6;
            s2_wc6 <= wc6;
            s2_ws7 <= ws7;
            s2_wc7 <= wc7;
            s2_ws8 <= ws8;
            s2_wc8 <= wc8;
            s2_ws9 <= ws9;
            s2_wc9 <= wc9;
        end
    end

    // > layer 3
    logic [67:0] ws10, ws11;
    logic [67:0] wc10, wc11;
    csa csa10(.a(s2_ws6), .b(s2_wc6), .cin(s2_ws7), .s(ws10), .cout(wc10));
    csa csa11(.a(s2_wc7), .b(s2_ws8), .cin(s2_wc8), .s(ws11), .cout(wc11));

    // > layer 4
    logic [67:0] ws12, ws13;
    logic [67:0] wc12, wc13;
    csa csa12(.a(ws10),   .b(wc10),   .cin(ws11),   .s(ws12), .cout(wc12));
    csa csa13(.a(wc11),   .b(s2_ws9), .cin(s2_wc9), .s(ws13), .cout(wc13));

    // stage 3 (tree layers 3-4)
    logic s3_valid;
    logic [67:0] s3_ws12, s3_wc12, s3_ws13, s3_wc13;
    always_ff @(posedge clk) begin
        if (reset) s3_valid <= 0;
        else begin
            s3_valid <= s2_valid;
            s3_ws12 <= ws12;
            s3_wc12 <= wc12;
            s3_ws13 <= ws13;
            s3_wc13 <= wc13;
        end
    end

    // > layer 5
    logic [67:0] ws14;
    logic [67:0] wc14;
    csa csa14(.a(s3_ws12), .b(s3_wc12), .cin(s3_ws13), .s(ws14), .cout(wc14));

    // > layer 6
    logic [67:0] ws15;
    logic [67:0] wc15;
    csa csa15(.a(ws14), .b(wc14), .cin(s3_wc13), .s(ws15), .cout(wc15));

    // stage 4 (tree layers 5-6)
    logic s4_valid;
    logic [67:0] s4_s;
    logic [67:0] s4_c;
    always_ff @(posedge clk) begin
        if (reset) s4_valid <= 0;
        else begin
            s4_valid <= s3_valid;
            s4_s <= ws15;
            s4_c <= wc15;
        end
    end

    // stage 5 (final sum)
    wire [67:0] sum = s4_s + s4_c;
    always_ff @(posedge clk) begin
        if (reset) valid_out <= 0;
        else begin
            valid_out <= s4_valid;
            p <= sum[63:0];
        end
    end
endmodule