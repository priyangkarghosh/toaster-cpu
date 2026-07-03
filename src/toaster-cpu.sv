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

    // tbus originator
    req_t [0:0] o_req;
    rsp_t [0:0] o_rsp;
    req_t [0:0] c_req;
    rsp_t [0:0] c_rsp;

    tbus #(
        .N_ORIGINATORS(1),
        .N_COMPLETERS(1),
        .MAP('{MEM})
    ) u_tbus (
        .clk(clk),
        .reset(reset),
        .o_req(o_req),
        .o_rsp(o_rsp),
        .c_req(c_req),
        .c_rsp(c_rsp)
    );

    memory #(
        .MEM_FILE(MEM_FILE),
        .CAPACITY(CAPACITY)
    ) u_mem (
        .clk(clk),
        .reset(reset),
        .i_addr(i_addr),
        .i_data(i_data),
        .c_req(c_req[0]),
        .c_rsp(c_rsp[0])
    );

    // irqs tied off until clint + iohub are wired in
    datapath u_core (
        .clk(clk),
        .reset(reset),
        .i_addr(i_addr),
        .i_data(i_data),
        .o_req(o_req[0]),
        .o_rsp(o_rsp[0]),
        .irq_msi(1'b0),
        .irq_mti(1'b0),
        .irq_mei(1'b0)
    );
endmodule
