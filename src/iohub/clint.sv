import tbus_pkg::*;

// core-local interruptor
module clint (
    input logic clk, reset,

    // tbus completer port
    input req_t c_req,
    output rsp_t c_rsp,

    // irq lines to the core
    output logic irq_msi,
    output logic irq_mti
);
    typedef enum logic [15:0] {
        A_MSIP      = 16'h0000,
        A_MTIMECMP  = 16'h4000,
        A_MTIMECMPH = 16'h4004,
        A_MTIME     = 16'hBFF8,
        A_MTIMEH    = 16'hBFFC
    } clint_addr_t;

    logic msip_q; // interrupt pending reg
    logic [63:0] mtime_q, mtimecmp_q;

    // both irqs are level. mti clears by moving mtimecmp forward
    assign irq_msi = msip_q;
    assign irq_mti = (mtime_q >= mtimecmp_q);

    // read decode
    logic err;
    logic [31:0] rdata;
    always_comb begin
        err = 0;
        case (c_req.addr[15:0])
            A_MSIP:      rdata = {31'd0, msip_q};
            A_MTIMECMP:  rdata = mtimecmp_q[31:0];
            A_MTIMECMPH: rdata = mtimecmp_q[63:32];
            A_MTIME:     rdata = mtime_q[31:0];
            A_MTIMEH:    rdata = mtime_q[63:32];
            default:     begin rdata = '0; err = 1; end
        endcase
    end

    // a request is consumed on the cycle before ack
    wire wr_en = c_req.valid & c_req.write & ~c_rsp.ack;

    // register logic
    always_ff @(posedge clk) begin
        if (reset) begin
            msip_q <= 0;
            mtime_q <= '0;
            mtimecmp_q <= '1; // far future so mti isn't pending out of reset
        end

        else begin
            mtime_q <= mtime_q + 64'd1;
            if (wr_en) begin
                case (c_req.addr[15:0])
                    A_MSIP:      msip_q <= c_req.wdata[0];
                    A_MTIMECMP:  mtimecmp_q[31:0] <= c_req.wdata;
                    A_MTIMECMPH: mtimecmp_q[63:32] <= c_req.wdata;
                    A_MTIME:     mtime_q[31:0] <= c_req.wdata;
                    A_MTIMEH:    mtime_q[63:32] <= c_req.wdata;
                    default: ;
                endcase
            end
        end
    end

    // response
    always_ff @(posedge clk) begin
        if (reset) c_rsp <= '0;
        else if (c_rsp.ack) c_rsp.ack <= 0;
        else if (c_req.valid) begin
            c_rsp.ack <= 1;
            c_rsp.err <= err;
            c_rsp.rdata <= rdata;
        end
    end
endmodule
