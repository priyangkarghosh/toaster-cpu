import tbus_pkg::*;

module memory #(
    parameter MEM_FILE = "",
    parameter W = 32,
    parameter CAPACITY = 512  // words
)(
    input clk,

    // instruction port
    input [W-1:0] i_addr,
    output logic [W-1:0] i_data,

    // data port
    input req_t c_req,
    output rsp_t c_rsp
);
    reg [W-1:0] mem [0:CAPACITY-1];
    initial $readmemh(MEM_FILE, mem);

    // convert byte addresses to word
    wire [$clog2(CAPACITY)-1:0] i_widx = i_addr[W-1:2];
    wire [$clog2(CAPACITY)-1:0] d_widx = c_req.addr[W-1:2];

    // reads always return the full word
    assign i_data = mem[i_widx];
    assign c_rsp.rdata = mem[d_widx];
    assign c_rsp.ack = c_req.valid;

    // writes use per-byte enables from c_req.be
    always_ff @(posedge clk) begin
        if (c_req.valid & c_req.write) begin
            if (c_req.be[0]) mem[d_widx][7:0]   <= c_req.wdata[7:0];
            if (c_req.be[1]) mem[d_widx][15:8]  <= c_req.wdata[15:8];
            if (c_req.be[2]) mem[d_widx][23:16] <= c_req.wdata[23:16];
            if (c_req.be[3]) mem[d_widx][31:24] <= c_req.wdata[31:24];
        end
    end
endmodule
