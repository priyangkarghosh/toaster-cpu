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
    
    // funct3
    typedef enum logic [2:0] {
        MW_BYTE  = 3'b000,
        MW_HALF  = 3'b001,
        MW_WORD  = 3'b010,
        MW_BYTEU = 3'b100,
        MW_HALFU = 3'b101
    } mem_width_t;

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
        logic [31:0] pc, imm, rr1, rr2;
        logic [4:0] rs1, rs2, rd;
        alu_op_t alu_op;
        mem_width_t mem_width;

        logic use_imm;
        logic rf_en;
        logic load_en;
        logic store_en;
    } id_ex_t;
 
    // ex -> ma
    typedef struct packed {
        logic [31:0] alu, rr2;
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
