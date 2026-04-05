module memory #(
    parameter MEM_FILE = "",
    parameter WORD_LENGTH = 32,
    parameter CAPACITY = 512
)(
    input clk,

    // read-only instruction port
    input  [WORD_LENGTH-1:0] instAddr,
    output [WORD_LENGTH-1:0] instOut,

    // read-write data port
    input [3:0] dataWrite, // one-hot per byte in the word
    input [WORD_LENGTH-1:0] dataAddr,
    input [WORD_LENGTH-1:0] dataIn,
    output [WORD_LENGTH-1:0] dataOut
);
    // init the memory buffer
    reg [WORD_LENGTH-1:0] buffer [0:CAPACITY-1];
    initial $readmemh(MEM_FILE, buffer);

    // convert the byte addresses to word addresses
    wire [$clog2(CAPACITY)-1:0] instIndex = instAddr[WORD_LENGTH-1:2];
    wire [$clog2(CAPACITY)-1:0] dataIndex = dataAddr[WORD_LENGTH-1:2];

    // async reads
    assign instOut = buffer[instIndex];
    assign dataOut = buffer[dataIndex];

    // sync write
    always @(posedge clk) begin
        if (dataWrite[0]) buffer[dataIndex][7:0] <= dataIn[7:0];
        if (dataWrite[1]) buffer[dataIndex][15:8] <= dataIn[15:8];
        if (dataWrite[2]) buffer[dataIndex][23:16] <= dataIn[23:16];
        if (dataWrite[3]) buffer[dataIndex][31:24] <= dataIn[31:24];
    end
endmodule
