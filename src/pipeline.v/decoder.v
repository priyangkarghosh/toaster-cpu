module decoder #(
    parameter WORD_LENGTH = 32
)(
    input [WORD_LENGTH-1:0] ir,

    // register addresses
    output [4:0] rs1, rs2, rd,

    // funct modifiers
    output [2:0] funct3,
    output [6:0] funct7
);
    wire [6:0] opcode = ir[6:0];

    // assign outputs
    assign rs1 = ir[19:15];
    assign rs2 = ir[24:20];
    assign rd  = ir[11:7];
    assign funct3 = ir[14:12];
    assign funct7 = ir[31:25];
endmodule