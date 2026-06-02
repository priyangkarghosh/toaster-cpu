package riscv_pkg;
    // alt + funct3
    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b1000,
        ALU_SLL  = 4'b0001,
        ALU_SLT  = 4'b0010,
        ALU_SLTU = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SRL  = 4'b0101,
        ALU_SRA  = 4'b1101,
        ALU_OR   = 4'b0110,
        ALU_AND  = 4'b0111
    } alu_op_t;

    // mul-ext operations
    typedef enum logic [2:0] {
        MDU_MUL    = 3'b000,
        MDU_MULH   = 3'b001,
        MDU_MULHSU = 3'b010,
        MDU_MULHU  = 3'b011,
        MDU_DIV    = 3'b100,
        MDU_DIVU   = 3'b101,
        MDU_REM    = 3'b110,
        MDU_REMU   = 3'b111
    } mdu_op_t;
    
    // funct3
    typedef enum logic [2:0] {
        MW_BYTE  = 3'b000,
        MW_HALF  = 3'b001,
        MW_WORD  = 3'b010,
        MW_BYTEU = 3'b100,
        MW_HALFU = 3'b101
    } mem_width_t;

    // funct3
    typedef enum logic [2:0] {
        BR_BEQ  = 3'h0,
        BR_BNE  = 3'h1,
        BR_BLT  = 3'h4,
        BR_BGE  = 3'h5,
        BR_BLTU = 3'h6,
        BR_BGEU = 3'h7
    } branch_t;

    typedef enum logic [6:0] {
        OP_REG    = 7'b0110011,
        OP_IMM    = 7'b0010011,
        OP_LOAD   = 7'b0000011,
        OP_STORE  = 7'b0100011,
        OP_BRANCH = 7'b1100011,
        OP_JAL    = 7'b1101111,
        OP_JALR   = 7'b1100111,
        OP_LUI    = 7'b0110111,
        OP_AUIPC  = 7'b0010111
    } opcode_t;

    // if -> id
    typedef struct packed {
        logic [31:0] pc, ir;
    } if_id_t;
 
    // id -> ex
    typedef struct packed {
        logic [31:0] pc, pc_next, imm, rr1, rr2;
        logic [4:0] rs1, rs2, rd;
        alu_op_t alu_op;
        mem_width_t mem_width;
        branch_t br_type;

        logic use_imm;
        logic use_pc;
        logic rf_en;
        logic load_en;
        logic store_en;
        logic branch_en;
        logic jal_en;

        // extensions
        logic mul_en;
        logic div_en;
    } id_ex_t;
 
    // ex -> ma
    typedef struct packed {
        logic [31:0] data, rr2;
        logic [4:0] rd;
        mem_width_t mem_width;
        
        logic rf_en;
        logic load_en;
        logic store_en;
    } ex_ma_t;
 
    // ma -> wb
    typedef struct packed {
        logic [31:0] data;
        logic [4:0] rd;
        logic rf_en;
    } ma_wb_t;
endpackage
