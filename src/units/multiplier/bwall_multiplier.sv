import unit_pkg::*;

module bwall_multiplier (
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

    // function to turn recoding into a partial product
    function [33:0] rec_to_pp;
        input booth_recode_t rec;
        begin
            case (rec)
                BOOTH_ZERO: rec_to_pp = '0;
                BOOTH_POS1: rec_to_pp = pos1;
                BOOTH_NEG1: rec_to_pp = neg1;
                BOOTH_POS2: rec_to_pp = pos2;
                BOOTH_NEG2: rec_to_pp = neg2;
                default: rec_to_pp = '0;
            endcase
        end
    endfunction

    // wallace tree
    // > inputs
    logic [67:0] wa, wb, wc, wd, we, wf, wg, wh, wi, wj, wk, wl, wm, wn, wo, wp, wq;

    // > layer 1
    logic [67:0] ws1, ws2, ws3, ws4, ws5;
    logic [68:0] wc1, wc2, wc3, wc4, wc5;
    csa #(68) csa1(.a(wa), .b(wb), .cin(wc), .s(ws1), .cout(wc1));
    csa #(68) csa2(.a(wd), .b(we), .cin(wf), .s(ws2), .cout(wc2));
    csa #(68) csa3(.a(wg), .b(wh), .cin(wi), .s(ws3), .cout(wc3));
    csa #(68) csa4(.a(wj), .b(wk), .cin(wl), .s(ws4), .cout(wc4));
    csa #(68) csa5(.a(wm), .b(wn), .cin(wo), .s(ws5), .cout(wc5));

    // > layer 2
    logic [68:0] ws6, ws7, ws8, ws9;
    logic [69:0] wc6, wc7, wc8, wc9;
    csa #(69) csa6(.a({ws1[67], ws1}), .b(wc1), .cin({ws2[67], ws2}), .s(ws6), .cout(wc6));
    csa #(69) csa7(.a(wc2), .b({ws3[67], ws3}), .cin(wc3), .s(ws7), .cout(wc7));
    csa #(69) csa8(.a({ws4[67], ws4}), .b(wc4), .cin({ws5[67], ws5}), .s(ws8), .cout(wc8));
    csa #(69) csa9(.a(wc5), .b({wp[67], wp}), .cin({wq[67], wq}), .s(ws9), .cout(wc9));

    // > layer 3
    logic [69:0] ws10, ws11;
    logic [70:0] wc10, wc11;
    csa #(70) csa10(.a({ws6[68], ws6}), .b(wc6), .cin({ws7[68], ws7}), .s(ws10), .cout(wc10));
    csa #(70) csa11(.a(wc7), .b({ws8[68], ws8}), .cin(wc8), .s(ws11), .cout(wc11));

    // > layer 4
    logic [70:0] ws12, ws13;
    logic [71:0] wc12, wc13;
    csa #(71) csa12(.a({ws10[69], ws10}), .b(wc10), .cin({ws11[69], ws11}), .s(ws12), .cout(wc12));
    csa #(71) csa13(.a(wc11), .b({{2{ws9[68]}}, ws9}), .cin({1'b0, wc9}), .s(ws13), .cout(wc13));

    // > layer 5
    logic [71:0] ws14;
    logic [72:0] wc14;
    csa #(72) csa14(.a({ws12[70], ws12}), .b(wc12), .cin({ws13[70], ws13}), .s(ws14), .cout(wc14));

    // > layer 6
    logic [72:0] ws15;
    logic [73:0] wc15;
    csa #(73) csa15(.a({ws14[71], ws14}), .b(wc14), .cin({1'b0, wc13}), .s(ws15), .cout(wc15));

    // stage 1 (recoding)
    logic valid_s1;
    always_ff @(posedge clk) begin
        if (reset) valid_s1 <= 0;
        else begin
            valid_s1 <= valid_in;
            wa <= 68'(signed'(rec_to_pp(rc[0])));
            wb <= 68'(signed'({rec_to_pp(rc[1]),  2'b0}));
            wc <= 68'(signed'({rec_to_pp(rc[2]),  4'b0}));
            wd <= 68'(signed'({rec_to_pp(rc[3]),  6'b0}));
            we <= 68'(signed'({rec_to_pp(rc[4]),  8'b0}));
            wf <= 68'(signed'({rec_to_pp(rc[5]),  10'b0}));
            wg <= 68'(signed'({rec_to_pp(rc[6]),  12'b0}));
            wh <= 68'(signed'({rec_to_pp(rc[7]),  14'b0}));
            wi <= 68'(signed'({rec_to_pp(rc[8]),  16'b0}));
            wj <= 68'(signed'({rec_to_pp(rc[9]),  18'b0}));
            wk <= 68'(signed'({rec_to_pp(rc[10]), 20'b0}));
            wl <= 68'(signed'({rec_to_pp(rc[11]), 22'b0}));
            wm <= 68'(signed'({rec_to_pp(rc[12]), 24'b0}));
            wn <= 68'(signed'({rec_to_pp(rc[13]), 26'b0}));
            wo <= 68'(signed'({rec_to_pp(rc[14]), 28'b0}));
            wp <= 68'(signed'({rec_to_pp(rc[15]), 30'b0}));
            wq <= 68'(signed'({rec_to_pp(rc[16]), 32'b0}));
        end
    end

    // stage 2 (tree)
    logic valid_s2;
    logic [72:0] s2_s;
    logic [73:0] s2_c;
    always_ff @(posedge clk) begin
        if (reset) valid_s2 <= 0;
        else begin
            valid_s2 <= valid_s1;
            s2_s <= ws15;
            s2_c <= wc15;
        end
    end

    // stage 3 (final sum)
    logic [73:0] final_sum;
    assign final_sum = {s2_s[72], s2_s} + s2_c;
    assign p = final_sum[63:0];
    always_ff @(posedge clk) begin
        if (reset) valid_out <= 0;
        else valid_out <= valid_s2;
    end
endmodule
