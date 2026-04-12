module decoder #(
    parameter W=32,
    parameter RF_ADDR_BITS=5
)(
    input [W-1:0] ir,

    // register addresses
    output logic [RF_ADDR_BITS-1:0] rs1, rs2, rd,
    output logic [W-1:0] imm,

    // output signals
);
    // instruction fields
    wire [6:0] opcode = ir[6:0];
    wire [2:0] funct3 = ir[14:12];
    wire [6:0] funct7 = ir[31:25];

    // register addresses
    assign rs1 = ir[19:15];
    assign rs2 = ir[24:20];
    assign rd = ir[11:7];

    // immediate formats
    wire [W-1:0] imm_i = {{20{ir[31]}}, ir[31:20]};
    wire [W-1:0] imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
    wire [W-1:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
    wire [W-1:0] imm_u = {ir[31:12], 12'b0};
    wire [W-1:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

    always_comb begin

        case (opcode)
            default: ;
        endcase
    end
endmodule
