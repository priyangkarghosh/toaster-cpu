package unit_pkg;
    typedef enum logic [2:0] {
        BOOTH_ZERO  = 3'b000,
        BOOTH_POS1  = 3'b001,
        BOOTH_NEG1  = 3'b010,
        BOOTH_POS2  = 3'b011,
        BOOTH_NEG2  = 3'b100
    } booth_recode_t;
endpackage
