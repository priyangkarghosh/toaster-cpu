import tbus_map_pkg::*;

module tbus #(
    parameter int ADDR_W    = 32,
    parameter int DATA_W    = 32,
    parameter int N_MASTERS = 1,
    parameter int N_SLAVES  = 2,

    // system memory map: a transaction at addr routes to slave i when
    // (addr & MAP[i].mask) == MAP[i].base
    // i.e with named regions from tbus_map_pkg:
    //   .MAP('{MEM, IOHUB})
    parameter region_t MAP[N_SLAVES] = '{default: '0}
) (
    // unused until arbiter goes stateful (round-robin etc)
    input logic clk,
    input logic reset,

    // master ports
    input  logic [N_MASTERS-1:0]               m_req,
    input  logic [N_MASTERS-1:0]               m_write,
    input  logic [N_MASTERS-1:0][ADDR_W-1:0]   m_addr,
    input  logic [N_MASTERS-1:0][DATA_W-1:0]   m_wdata,
    input  logic [N_MASTERS-1:0][DATA_W/8-1:0] m_be,
    output logic [N_MASTERS-1:0][DATA_W-1:0]   m_rdata,
    output logic [N_MASTERS-1:0]               m_ack,

    // slave ports
    output logic [N_SLAVES-1:0]                s_req,
    output logic [N_SLAVES-1:0]                s_write,
    output logic [N_SLAVES-1:0][ADDR_W-1:0]    s_addr,
    output logic [N_SLAVES-1:0][DATA_W-1:0]    s_wdata,
    output logic [N_SLAVES-1:0][DATA_W/8-1:0]  s_be,
    input  logic [N_SLAVES-1:0][DATA_W-1:0]    s_rdata,
    input  logic [N_SLAVES-1:0]                s_ack
);
    // arbitration
    // -> for now fixed priority, lowest-index master wins
    logic [N_MASTERS-1:0] grant;
    always_comb begin
        grant = '0;
        for (int i = 0; i < N_MASTERS; i++) begin
            if (m_req[i] && (grant == '0)) grant[i] = 1'b1;
        end
    end

    // mux the granted master onto the shared "current transaction" wires
    logic cur_req, cur_write;
    logic [ADDR_W-1:0] cur_addr;
    logic [DATA_W-1:0] cur_wdata;
    logic [DATA_W/8-1:0] cur_be;
    always_comb begin
        cur_req   = 1'b0;
        cur_write = 1'b0;
        cur_addr  = '0;
        cur_wdata = '0;
        cur_be    = '0;
        for (int i = 0; i < N_MASTERS; i++) begin
            if (grant[i]) begin
                cur_req   = m_req[i];
                cur_write = m_write[i];
                cur_addr  = m_addr[i];
                cur_wdata = m_wdata[i];
                cur_be    = m_be[i];
            end
        end
    end

    // slave-side routing
    logic [N_SLAVES-1:0] sel;
    genvar gi;
    generate
        for (gi = 0; gi < N_SLAVES; gi++) begin : gen_route
            assign sel[gi]     = (cur_addr & MAP[gi].mask) == MAP[gi].base;
            assign s_req[gi]   = cur_req & sel[gi];
            assign s_write[gi] = cur_write;
            assign s_addr[gi]  = cur_addr;
            assign s_wdata[gi] = cur_wdata;
            assign s_be[gi]    = cur_be;
        end
    endgenerate

    // collapse slave responses
    logic cur_ack;
    logic [DATA_W-1:0] cur_rdata;
    assign cur_ack = |s_ack;
    always_comb begin
        cur_rdata = '0;
        for (int i = 0; i < N_SLAVES; i++) begin
            if (s_ack[i]) cur_rdata = s_rdata[i];
        end
    end

    // return response only to the granted master.
    // ungranted masters see ack=0, hold their req until they win arbitration
    generate
        for (gi = 0; gi < N_MASTERS; gi++) begin : gen_resp
            assign m_ack[gi] = grant[gi] & cur_ack;
            assign m_rdata[gi] = cur_rdata;
        end
    endgenerate
endmodule
