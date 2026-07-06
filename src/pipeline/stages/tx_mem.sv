import riscv_pkg::*;
import tbus_pkg::*;

module tx_mem (
    input clk, reset, en, bubble,

    // inputs from prev stage
    input ex_ma_t ex_ma,

    // data memory port
    output req_t o_req,
    input rsp_t o_rsp,

    // csr trap port + live status
    output trap_t trap,
    input csr_stat_t csr_stat,

    // redirect (qualified by trap.en)
    output logic [31:0] pc_target,

    // output signals
    output ma_busy,
    
    // outputs to next stage
    output ma_wb_t ma_wb
);
    // lane placement is a shift by 8*boff
    wire is_word = (ex_ma.mem_width == MW_WORD);
    wire is_half = (ex_ma.mem_width == MW_HALF) | (ex_ma.mem_width == MW_HALFU);

    // calculate byte enable. misaligned accesses trap in ex, so the request never issues here
    wire [1:0] boff = ex_ma.data[1:0];
    wire [3:0] be = (is_word ? 4'b1111 : is_half ? 4'b0011 : 4'b0001) << boff;
    wire [31:0] wdata = ex_ma.rr2 << {boff, 3'b000};

    // extract lane by shifting down, sign/zero-ext per mem_width
    logic [31:0] rdata;
    wire [31:0] shifted = o_rsp.rdata >> {boff, 3'b000};
    always_comb begin
        case (ex_ma.mem_width)
            MW_BYTE:  rdata = {{24{shifted[7]}}, shifted[7:0]};
            MW_BYTEU: rdata = {24'b0, shifted[7:0]};
            MW_HALF:  rdata = {{16{shifted[15]}}, shifted[15:0]};
            MW_HALFU: rdata = {16'b0, shifted[15:0]};
            MW_WORD:  rdata = o_rsp.rdata;
            default:  rdata = '0;
        endcase
    end

    // access fault
    wire bus_err = o_req.valid & o_rsp.ack & o_rsp.err;

    // update exception data
    exc_t ma_exc;
    assign ma_exc.valid = ex_ma.exc.valid | bus_err;
    assign ma_exc.cause = ex_ma.exc.valid ? ex_ma.exc.cause : (ex_ma.store_en ? EXC_SACCESS : EXC_LACCESS);
    assign ma_exc.tval = ex_ma.exc.valid ? ex_ma.exc.tval : ex_ma.data;

    // commit trap
    wire replay_safe = ~(ex_ma.load_en | ex_ma.store_en | ex_ma.csr_en | ex_ma.mret_en);
    wire irq_taken = csr_stat.irq_en & ex_ma.valid & replay_safe;

    // csr trap port
    assign trap.en = ma_exc.valid | irq_taken;
    assign trap.pc = ex_ma.pc;
    assign trap.cause = ma_exc.valid ? {28'd0, ma_exc.cause} : csr_stat.irq_cause;
    assign trap.tval = ma_exc.valid ? ma_exc.tval : 32'd0;

    // vectored mtvec offsets interrupts only; exceptions always go to base
    wire [31:0] mtvec_base = {csr_stat.mtvec[31:2], 2'b00};
    wire irq_vec = ~ma_exc.valid & csr_stat.mtvec[0];
    assign pc_target = irq_vec ? mtvec_base + {26'd0, csr_stat.irq_cause[3:0], 2'b00} : mtvec_base;

    // set response data. a faulting load/store must never touch the bus
    assign o_req.valid = (ex_ma.load_en | ex_ma.store_en) & ~ex_ma.exc.valid;
    assign o_req.write = ex_ma.store_en;
    assign o_req.addr = ex_ma.data;
    assign o_req.wdata = wdata;
    assign o_req.be = be;

    // set busy flag
    assign ma_busy = o_req.valid & !o_rsp.ack; // only busy during r/w
    always_ff @(posedge clk) begin
        if (reset | bubble) begin
            ma_wb <= '0;
        end

        else if (en) begin
            ma_wb.data <= ex_ma.load_en ? rdata : ex_ma.data;
            ma_wb.rd <= ex_ma.rd;
            ma_wb.rf_en <= ex_ma.rf_en;
        end
    end
endmodule
