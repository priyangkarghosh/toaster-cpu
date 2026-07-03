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
    input req_t s_req,
    output rsp_t s_rsp
);
    reg [W-1:0] mem [0:CAPACITY-1];
    initial $readmemh(MEM_FILE, mem);

    // convert byte addresses to word
    wire [$clog2(CAPACITY)-1:0] i_widx = i_addr[W-1:2];
    wire [$clog2(CAPACITY)-1:0] d_widx = s_req.addr[W-1:2];

    // reads always return the full word
    assign i_data = mem[i_widx];
    assign s_rsp.rdata = mem[d_widx];
    assign s_rsp.ack = s_req.valid;

    // writes use per-byte enables from s_req.be
    always_ff @(posedge clk) begin
        if (s_req.valid & s_req.write) begin
            if (s_req.be[0]) mem[d_widx][7:0]   <= s_req.wdata[7:0];
            if (s_req.be[1]) mem[d_widx][15:8]  <= s_req.wdata[15:8];
            if (s_req.be[2]) mem[d_widx][23:16] <= s_req.wdata[23:16];
            if (s_req.be[3]) mem[d_widx][31:24] <= s_req.wdata[31:24];
        end
    end
endmodule
