import tbus_pkg::*;
import tbus_map_pkg::*;

module tbus #(
    parameter int N_ORIGINATORS = 1,
    parameter int N_COMPLETERS  = 2,

    // system memory map: a transaction at addr routes to completer i when
    // (addr & MAP[i].mask) == MAP[i].base
    // i.e with named regions from tbus_map_pkg:
    //   .MAP('{MEM, IOHUB})
    parameter region_t MAP[N_COMPLETERS] = '{default: '0}
) (
    // unused until arbiter goes stateful (round-robin etc)
    input logic clk,
    input logic reset,

    // originator ports
    input req_t [N_ORIGINATORS-1:0] o_req,
    output rsp_t [N_ORIGINATORS-1:0] o_rsp,

    // completer ports
    output req_t [N_COMPLETERS-1:0] c_req,
    input rsp_t [N_COMPLETERS-1:0] c_rsp
);
    // arbitration
    // -> for now fixed priority, lowest-index wins
    logic [N_ORIGINATORS-1:0] grant;
    always_comb begin
        grant = '0;
        for (int i = 0; i < N_ORIGINATORS; i++) begin
            if (o_req[i].valid && (grant == '0)) grant[i] = 1'b1;
        end
    end

    // mux the granted originator onto the shared "current transaction" bundle
    req_t cur;
    always_comb begin
        cur = '0;
        for (int i = 0; i < N_ORIGINATORS; i++) begin
            if (grant[i]) cur = o_req[i];
        end
    end

    // completer-side routing
    // -> each completer gets the full request, but only the addressed completer sees valid=1
    genvar gi;
    generate
        for (gi = 0; gi < N_COMPLETERS; gi++) begin : gen_route
            logic sel;
            assign sel = (cur.addr & MAP[gi].mask) == MAP[gi].base;
            always_comb begin
                c_req[gi] = cur;
                c_req[gi].valid = cur.valid & sel;
            end
        end
    endgenerate

    // collapse completer responses
    rsp_t cur_rsp;
    always_comb begin
        cur_rsp = '0;
        for (int i = 0; i < N_COMPLETERS; i++) begin
            if (c_rsp[i].ack) cur_rsp = c_rsp[i];
        end
    end

    // return response only to the granted originator.
    // ungranted originators see ack=0, hold their req until they win arbitration
    generate
        for (gi = 0; gi < N_ORIGINATORS; gi++) begin : gen_resp
            always_comb begin
                o_rsp[gi] = cur_rsp;
                o_rsp[gi].ack = grant[gi] & cur_rsp.ack;
            end
        end
    endgenerate
endmodule
