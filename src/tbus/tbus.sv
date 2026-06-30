import tbus_pkg::*;
import tbus_map_pkg::*;

module tbus #(
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
    input req_t [N_MASTERS-1:0] m_req,
    output rsp_t [N_MASTERS-1:0] m_rsp,

    // slave ports
    output req_t [N_SLAVES-1:0] s_req,
    input rsp_t [N_SLAVES-1:0] s_rsp
);
    // arbitration
    // -> for now fixed priority, lowest-index wins
    logic [N_MASTERS-1:0] grant;
    always_comb begin
        grant = '0;
        for (int i = 0; i < N_MASTERS; i++) begin
            if (m_req[i].valid && (grant == '0)) grant[i] = 1'b1;
        end
    end

    // mux the granted master onto the shared "current transaction" bundle
    req_t cur;
    always_comb begin
        cur = '0;
        for (int i = 0; i < N_MASTERS; i++) begin
            if (grant[i]) cur = m_req[i];
        end
    end

    // slave-side routing
    // -> each slave gets the full request, but only the addressed slave sees valid=1
    genvar gi;
    generate
        for (gi = 0; gi < N_SLAVES; gi++) begin : gen_route
            logic sel;
            assign sel = (cur.addr & MAP[gi].mask) == MAP[gi].base;
            always_comb begin
                s_req[gi] = cur;
                s_req[gi].valid = cur.valid & sel;
            end
        end
    endgenerate

    // collapse slave responses
    rsp_t cur_rsp;
    always_comb begin
        cur_rsp = '0;
        for (int i = 0; i < N_SLAVES; i++) begin
            if (s_rsp[i].ack) cur_rsp = s_rsp[i];
        end
    end

    // return response only to the granted master.
    // ungranted masters see ack=0, hold their req until they win arbitration
    generate
        for (gi = 0; gi < N_MASTERS; gi++) begin : gen_resp
            always_comb begin
                m_rsp[gi] = cur_rsp;
                m_rsp[gi].ack = grant[gi] & cur_rsp.ack;
            end
        end
    endgenerate
endmodule
