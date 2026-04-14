module memory # (
    parameter MEM_FILE = "",
    parameter W = 32,
    parameter CAPACITY = 512
)(
    input clk,

    // read-only instruction port
    input [W-1:0] pc,
    output [W-1:0] inst_out,

    // read-write data port
    input [3:0] write, // one-hot per byte in the word
    input [W-1:0] addr,
    input [W-1:0] data_in,
    output [W-1:0] data_out
);
    // init the memory buffer
    reg [W-1:0] buffer [0:CAPACITY-1];
    initial $readmemh(MEM_FILE, buffer);

    // convert the byte addresses to word addresses
    wire [$clog2(CAPACITY)-1:0] instIndex = pc[W-1:2];
    wire [$clog2(CAPACITY)-1:0] dataIndex = addr[W-1:2];

    // async reads
    assign inst_out = buffer[instIndex];
    assign data_out = buffer[dataIndex];

    // sync write
    always_ff @(posedge clk) begin
        if (write[0]) buffer[dataIndex][7:0] <= data_in[7:0];
        if (write[1]) buffer[dataIndex][15:8] <= data_in[15:8];
        if (write[2]) buffer[dataIndex][23:16] <= data_in[23:16];
        if (write[3]) buffer[dataIndex][31:24] <= data_in[31:24];
    end
endmodule
