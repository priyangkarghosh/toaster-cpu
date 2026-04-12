package alu_pkg;
    typedef enum logic [2:0] {
        ADD = 3'b000,
        SLL = 3'b001,
        SLT = 3'b010,
        SLTU = 3'b011,
        XOR = 3'b100,
        SRL = 3'b101,
        OR = 3'b110,
        AND = 3'b111
    } alu_op_t;
endpackage