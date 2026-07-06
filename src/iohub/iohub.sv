import tbus_pkg::*;

module iohub (
    input logic clk, reset,

    // completer port
    input req_t c_req,
    output rsp_t c_rsp,

    // irq lines to the core
    output logic irq_msi,
    output logic irq_mti
);
    // device windows
    localparam logic [11:0] W_CLINT = 12'h000;

    // get requested address window
    wire [11:0] window = c_req.addr[27:16];
    wire sel_clint = c_req.valid & (window == W_CLINT);

    // clint instance
    req_t clint_req;
    always_comb begin
        clint_req = c_req;
        clint_req.valid = sel_clint;
    end

    rsp_t clint_rsp;
    clint u_clint (
        .clk(clk),
        .reset(reset),
        .c_req(clint_req),
        .c_rsp(clint_rsp),
        .irq_msi(irq_msi),
        .irq_mti(irq_mti)
    );

    // dummy completer
    logic dummy_ack;
    always_ff @(posedge clk) begin
        if (reset | dummy_ack) dummy_ack <= 0;
        else if (c_req.valid & ~sel_clint) dummy_ack <= 1;
    end

    // collapse device responses
    always_comb begin
        c_rsp = '0;
        c_rsp.ack = dummy_ack;
        c_rsp.err = dummy_ack;
        if (clint_rsp.ack) c_rsp = clint_rsp;
    end
endmodule
