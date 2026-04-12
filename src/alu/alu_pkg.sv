package alu_pkg;
    typedef enum logic [2:0] {
        ALU_ADD = 3'b000,
        ALU_SLL = 3'b001,
        ALU_SLT = 3'b010,
        ALU_SLTU = 3'b011,
        ALU_XOR = 3'b100,
        ALU_SRL = 3'b101,
        ALU_OR = 3'b110,
        ALU_AND = 3'b111
    } alu_op_t;
endpackage