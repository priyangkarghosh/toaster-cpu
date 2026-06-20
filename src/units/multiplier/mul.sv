import unit_pkg::*;

// pipelined 32x32 signed/unsigned multiplier
//   stage 1: booth-recode + sign-extend partial products
//   stage 2: layers 1+2 of the Wallace tree (18 -> 8)
//   stage 3: layers 3+4 of the Wallace tree (8 -> 4)
//   stage 4: layers 5+6 (4 -> 2)
//   stage 5: final carry-propagate add (2 -> 1)
module mul (
    // sync
    input logic clk, reset,

    // inputs
    input logic valid_in,
    input logic sign_x, sign_y,
    input logic [31:0] x, y,
    
    // outputs
    output logic [63:0] p,
    output logic valid_out
);
    localparam int N_PP = 17;  // number of partial products
    localparam int WW   = 68;  // wallace tree width

    // sign-extended 34-bit operands
    wire [33:0] x_eff = {{2{sign_x & x[31]}}, x};
    wire [33:0] y_eff = {{2{sign_y & y[31]}}, y};

    // partial-product magnitudes (±1*x and ±2*x)
    wire [33:0] mag1 = x_eff;
    wire [33:0] mag2 = x_eff << 1;

    // booth recode of y
    booth_recode_t rc [0:N_PP-1];
    recode #(.W(34)) u_recode (.q(y_eff), .r(rc));

    // partial products: magnitude (possibly inverted) + a sign-correction bit (used for csa)
    logic pp_neg [0:N_PP-1];
    logic [33:0] pp[0:N_PP-1];
    always_comb begin
        for (int i = 0; i < N_PP; i++) begin
            unique case (rc[i])
                BOOTH_POS1: begin pp[i] =  mag1; pp_neg[i] = 1'b0; end
                BOOTH_NEG1: begin pp[i] = ~mag1; pp_neg[i] = 1'b1; end
                BOOTH_POS2: begin pp[i] =  mag2; pp_neg[i] = 1'b0; end
                BOOTH_NEG2: begin pp[i] = ~mag2; pp_neg[i] = 1'b1; end
                default:    begin pp[i] = '0;    pp_neg[i] = 1'b0; end
            endcase
        end
    end

    // correction vector: a '+1' at bit 2*i for every inverted partial product
    logic [WW-1:0] corr;
    always_comb begin
        corr = '0;
        for (int i = 0; i < N_PP; i++) corr[2*i] = pp_neg[i];
    end

    // sign ext each partial product to WW bits and shift it into position
    logic [WW-1:0] pp_shifted [0:N_PP-1];
    generate
        for (genvar gi = 0; gi < N_PP; gi++) begin : gen_pp_shift
            assign pp_shifted[gi] = WW'(signed'(pp[gi])) << (2*gi);
        end
    endgenerate

    // ------------------------------------------------------------------
    // stage 1: latch the 17 shifted partial products + correction vector
    // ------------------------------------------------------------------
    logic s1_valid;
    logic [WW-1:0] s1 [0:N_PP];  // [0..16] = partial products, [17] = corr vec
    always_ff @(posedge clk) begin
        if (reset) s1_valid <= 1'b0;
        else begin
            s1_valid <= valid_in;
            for (int i = 0; i < N_PP; i++) s1[i] <= pp_shifted[i];
            s1[N_PP] <= corr;
        end
    end

    // ------------------------------------------------------------------
    // wallace layer 1: 18 inputs -> 6 (s,c) pairs
    // ------------------------------------------------------------------
    logic [WW-1:0] l1_s [0:5], l1_c [0:5];
    generate
        for (genvar g = 0; g < 6; g++) begin : gen_l1
            csa #(.W(WW)) u (
                .sub(1'b0),
                .a(s1[3*g]),
                .b(s1[3*g + 1]),
                .cin(s1[3*g + 2]),
                .s(l1_s[g]),
                .cout(l1_c[g])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // wallace layer 2: 12 inputs (6 s,c pairs interleaved) -> 4 (s,c) pairs
    // ------------------------------------------------------------------
    logic [WW-1:0] l1_out [0:11];
    generate
        for (genvar g = 0; g < 6; g++) begin : gen_l1_flat
            assign l1_out[2*g] = l1_s[g];
            assign l1_out[2*g + 1] = l1_c[g];
        end
    endgenerate

    logic [WW-1:0] l2_s [0:3], l2_c [0:3];
    generate
        for (genvar g = 0; g < 4; g++) begin : gen_l2
            csa #(.W(WW)) u (
                .sub (1'b0),
                .a(l1_out[3*g]),
                .b(l1_out[3*g + 1]),
                .cin(l1_out[3*g + 2]),
                .s(l2_s[g]),
                .cout(l2_c[g])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // stage 2 register: 8 vectors out of layer 2
    // ------------------------------------------------------------------
    logic s2_valid;
    logic [WW-1:0] s2 [0:7];  // [s7, c7, s8, c8, s9, c9, s10, c10]
    always_ff @(posedge clk) begin
        if (reset) s2_valid <= 1'b0;
        else begin
            s2_valid <= s1_valid;
            for (int k = 0; k < 4; k++) begin
                s2[2*k] <= l2_s[k];
                s2[2*k + 1] <= l2_c[k];
            end
        end
    end

    // ------------------------------------------------------------------
    // wallace layer 3: 8 inputs -> 2 (s,c) pairs + 2 pass-through
    // ------------------------------------------------------------------
    logic [WW-1:0] l3_s [0:1], l3_c [0:1];
    generate
        for (genvar g = 0; g < 2; g++) begin : gen_l3
            csa #(.W(WW)) u (
                .sub(1'b0),
                .a(s2[3*g]),
                .b(s2[3*g + 1]),
                .cin(s2[3*g + 2]),
                .s(l3_s[g]),
                .cout(l3_c[g])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // wallace layer 4: layer-3 outputs (4) + 2 stage-2 pass-throughs (s2[6..7])
    // -> 2 (s,c) pairs
    // ------------------------------------------------------------------
    logic [WW-1:0] l34_out [0:5];
    assign l34_out[0] = l3_s[0];
    assign l34_out[1] = l3_c[0];
    assign l34_out[2] = l3_s[1];
    assign l34_out[3] = l3_c[1];
    assign l34_out[4] = s2[6];
    assign l34_out[5] = s2[7];

    logic [WW-1:0] l4_s [0:1], l4_c [0:1];
    generate
        for (genvar g = 0; g < 2; g++) begin : gen_l4
            csa #(.W(WW)) u (
                .sub (1'b0),
                .a(l34_out[3*g]),
                .b(l34_out[3*g + 1]),
                .cin(l34_out[3*g + 2]),
                .s(l4_s[g]),
                .cout(l4_c[g])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // stage 3 register: 4 vectors out of layer 4
    // ------------------------------------------------------------------
    logic s3_valid;
    logic [WW-1:0] s3 [0:3];  // [s13, c13, s14, c14]
    always_ff @(posedge clk) begin
        if (reset) s3_valid <= 1'b0;
        else begin
            s3_valid <= s2_valid;
            s3[0] <= l4_s[0]; s3[1] <= l4_c[0];
            s3[2] <= l4_s[1]; s3[3] <= l4_c[1];
        end
    end

    // ------------------------------------------------------------------
    // wallace layers 5 + 6: 4 -> 2
    // ------------------------------------------------------------------
    logic [WW-1:0] l5_s, l5_c, l6_s, l6_c;
    csa #(.W(WW)) u_l5 (.sub(1'b0), .a(s3[0]), .b(s3[1]), .cin(s3[2]), .s(l5_s), .cout(l5_c));
    csa #(.W(WW)) u_l6 (.sub(1'b0), .a(l5_s),  .b(l5_c),  .cin(s3[3]), .s(l6_s), .cout(l6_c));

    // ------------------------------------------------------------------
    // stage 4 register: final (s, c) pair feeding the CPA
    // ------------------------------------------------------------------
    logic s4_valid;
    logic [WW-1:0] s4_s, s4_c;
    always_ff @(posedge clk) begin
        if (reset) s4_valid <= 1'b0;
        else begin
            s4_valid <= s3_valid;
            s4_s <= l6_s;
            s4_c <= l6_c;
        end
    end

    // ------------------------------------------------------------------
    // stage 5: carry-propagate add into the final 64-bit product
    // ------------------------------------------------------------------
    wire [63:0] sum = s4_s[63:0] + s4_c[63:0];
    always_ff @(posedge clk) begin
        if (reset) valid_out <= 1'b0;
        else begin
            valid_out <= s4_valid;
            p <= sum;
        end
    end
endmodule
