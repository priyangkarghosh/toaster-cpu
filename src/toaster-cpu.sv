import tbus_pkg::*;
import tbus_map_pkg::*;

module toaster_cpu #(
    parameter MEM_FILE = "",
    parameter CAPACITY = 512  // words
)(
    input logic clk, reset
);
    // instruction port
    logic [31:0] i_addr;
    logic [31:0] i_data;

    // tbus master
    req_t [0:0] m_req;
    rsp_t [0:0] m_rsp;
    req_t [0:0] s_req;
    rsp_t [0:0] s_rsp;

    tbus #(
        .N_MASTERS(1),
        .N_SLAVES(1),
        .MAP('{MEM})
    ) u_tbus (
        .clk(clk),
        .reset(reset),
        .m_req(m_req),
        .m_rsp(m_rsp),
        .s_req(s_req),
        .s_rsp(s_rsp)
    );

    memory #(
        .MEM_FILE(MEM_FILE),
        .CAPACITY(CAPACITY)
    ) u_mem (
        .clk(clk),
        .i_addr(i_addr),
        .i_data(i_data),
        .s_req(s_req[0]),
        .s_rsp(s_rsp[0])
    );

    // irqs tied off until clint + iohub are wired in
    datapath u_core (
        .clk(clk),
        .reset(reset),
        .i_addr(i_addr),
        .i_data(i_data),
        .m_req(m_req[0]),
        .m_rsp(m_rsp[0]),
        .irq_msi(1'b0),
        .irq_mti(1'b0),
        .irq_mei(1'b0)
    );
endmodule
