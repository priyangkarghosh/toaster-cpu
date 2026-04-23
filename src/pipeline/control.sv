import riscv_pkg::*;

module control (
    input logic [31:0] ir,

    // register addresses
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,
    output logic [31:0] imm,

    // alu control
    output alu_op_t alu_op,
    output mem_width_t mem_width,
    output branch_t br_type,

    // output signals
    output logic use_imm,
    output logic rf_en,
    output logic load_en,
    output logic store_en,
    output logic branch_en,
    output logic jal_en,
    output logic jalr_en
);
    opcode_t opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = opcode_t'(ir[6:0]);
    assign funct3 = ir[14:12];
    assign funct7 = ir[31:25];
    assign mem_width = mem_width_t'(funct3);
    assign br_type = branch_t'(funct3);

    assign rs1 = ir[19:15];
    assign rs2 = ir[24:20];
    assign rd = ir[11:7];

    // immediate formats
    wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
    wire [31:0] imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
    wire [31:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
    wire [31:0] imm_u = {ir[31:12], 12'b0};
    wire [31:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

    always_comb begin
        imm = '0;
        alu_op = ALU_ADD;
        use_imm = 0;
        rf_en = 0;
        load_en = 0;
        store_en = 0;
        branch_en = 0;
        jal_en = 0;
        jalr_en = 0;

        case (opcode)
            OP_REG: begin
                alu_op = alu_op_t'({funct7[5], funct3});
                rf_en = 1;
            end

            OP_IMM: begin
                alu_op = alu_op_t'({funct7[5] & (funct3 == ALU_SRL[2:0]), funct3});
                imm = imm_i;
                use_imm = 1;
                rf_en = 1;
            end

            OP_LOAD: begin
                imm = imm_i;
                use_imm = 1;
                rf_en = 1;
                load_en = 1;
            end

            OP_STORE: begin
                imm = imm_s;
                use_imm = 1;
                store_en = 1;
            end

            OP_BRANCH: begin
                imm = imm_b;
                use_imm = 1;
                branch_en = 1;
            end

            OP_JAL: begin
                imm = imm_j;
                use_imm = 1;
                rf_en = 1;
                jal_en = 1;
            end

            OP_JALR: begin
                imm = imm_i;
                use_imm = 1;
                rf_en = 1;
                jalr_en = 1;
            end

            default: ;
        endcase
    end
endmodule