import riscv_pkg::*;

module csr (
    // sync
    input logic clk,
    input logic reset,

    // access port
    input  logic        csr_en,
    input  csr_op_t     csr_op,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    input  logic        csr_wmask,
    output logic [31:0] csr_rdata,
    output logic        csr_illegal,

    // trap entry
    input logic trap_en,
    input logic [31:0] trap_pc,
    input logic [31:0] trap_cause,
    input logic [31:0] trap_tval,

    // mret
    input logic mret_en,

    // interrupt-pending wires
    input logic irq_msi,
    input logic irq_mti,
    input logic irq_mei,

    // exposed for later wiring
    output logic [31:0] mstatus_o,
    output logic [31:0] mtvec_o,
    output logic [31:0] mepc_o,
    output logic [31:0] mie_o,
    output logic [31:0] mip_o,

    // interrupt-taken (priority-encoded mei > msi > mti)
    output logic irq_en,
    output logic [31:0] irq_cause
);
    // addresses
    localparam logic [11:0] CSR_MVENDORID = 12'hF11;
    localparam logic [11:0] CSR_MARCHID   = 12'hF12;
    localparam logic [11:0] CSR_MIMPID    = 12'hF13;
    localparam logic [11:0] CSR_MHARTID   = 12'hF14;
    localparam logic [11:0] CSR_MISA      = 12'h301;
    localparam logic [11:0] CSR_MSTATUS   = 12'h300;
    localparam logic [11:0] CSR_MIE       = 12'h304;
    localparam logic [11:0] CSR_MTVEC     = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
    localparam logic [11:0] CSR_MEPC      = 12'h341;
    localparam logic [11:0] CSR_MCAUSE    = 12'h342;
    localparam logic [11:0] CSR_MTVAL     = 12'h343;
    localparam logic [11:0] CSR_MIP       = 12'h344;

    // constants
    localparam logic [31:0] MISA_VAL    = (32'd1 << 30) | (32'd1 << 12) | (32'd1 << 8); // rv32im: mxl=01, m, i
    localparam logic [31:0] MSTATUS_RST = 32'd3 << 11; // m-mode is the only mode so mpp=11

    // write masks
    localparam logic [31:0] MSTATUS_WMASK = (32'd1 << 3) | (32'd1 << 7); // only mie (bit 3) and mpie (bit 7) writeable
    localparam logic [31:0] MIE_WMASK     = (32'd1 << 3) | (32'd1 << 7) | (32'd1 << 11); // msie/mtie/meie writable at 3/7/11
    localparam logic [31:0] MTVEC_WMASK   = 32'hFFFF_FFFD; // bit 1 is reserved at 0
    localparam logic [31:0] MEPC_WMASK    = 32'hFFFF_FFFC; // 4-byte aligned

    // registers
    logic [31:0] mstatus_q;
    logic [31:0] mtvec_q;
    logic [31:0] mie_q;
    logic [31:0] mscratch_q;
    logic [31:0] mepc_q;
    logic [31:0] mcause_q;
    logic [31:0] mtval_q;

    // mip is fully combinational from external irq wires, writes no-op
    wire [31:0] mip_w = {20'd0, irq_mei, 3'd0, irq_mti, 3'd0, irq_msi, 3'd0};

    // interrupt-taken
    wire mei_pend = mip_w[11] & mie_q[11];
    wire msi_pend = mip_w[3]  & mie_q[3];
    wire mti_pend = mip_w[7]  & mie_q[7];
    assign irq_en    = (mei_pend | msi_pend | mti_pend) & mstatus_q[3];
    assign irq_cause = mei_pend ? 32'h8000_000B :
                       msi_pend ? 32'h8000_0003 :
                                  32'h8000_0007;

    // reads
    logic addr_valid;
    logic addr_ro;
    always_comb begin
        csr_rdata = 32'd0;
        addr_valid = 1'b1;
        addr_ro = 1'b0;
        unique case (csr_addr)
            CSR_MVENDORID: begin csr_rdata = 32'd0; addr_ro = 1'b1; end
            CSR_MARCHID:   begin csr_rdata = 32'd0; addr_ro = 1'b1; end
            CSR_MIMPID:    begin csr_rdata = 32'd0; addr_ro = 1'b1; end
            CSR_MHARTID:   begin csr_rdata = 32'd0; addr_ro = 1'b1; end
            CSR_MISA:      csr_rdata = MISA_VAL; // can be a const since it cant be written
            CSR_MSTATUS:   csr_rdata = mstatus_q;
            CSR_MIE:       csr_rdata = mie_q;
            CSR_MTVEC:     csr_rdata = mtvec_q;
            CSR_MSCRATCH:  csr_rdata = mscratch_q;
            CSR_MEPC:      csr_rdata = mepc_q;
            CSR_MCAUSE:    csr_rdata = mcause_q;
            CSR_MTVAL:     csr_rdata = mtval_q;
            CSR_MIP:       csr_rdata = mip_w;
            default:       addr_valid = 1'b0;
        endcase
    end

    // atomic read-modify-write value
    logic [31:0] csr_new;
    always_comb begin
        unique case (csr_op)
            CSR_RW:  csr_new = csr_wdata;
            CSR_RS:  csr_new = csr_rdata |  csr_wdata;
            CSR_RC:  csr_new = csr_rdata & ~csr_wdata;
            default: csr_new = csr_rdata;
        endcase
    end

    // commit + illegal detect. rs/rc with zero source aren't real writes and don't trip illegal
    wire write_ok = csr_en & csr_wmask & addr_valid & ~addr_ro;
    assign csr_illegal = csr_en & (~addr_valid | (csr_wmask & addr_ro));

    // writeback
    always_ff @(posedge clk) begin
        if (reset) begin
            mstatus_q  <= MSTATUS_RST;
            mtvec_q    <= '0;
            mie_q      <= '0;
            mscratch_q <= '0;
            mepc_q     <= '0;
            mcause_q   <= '0;
            mtval_q    <= '0;
        end

        else if (trap_en) begin
            mepc_q    <= trap_pc & MEPC_WMASK;
            mcause_q  <= trap_cause;
            mtval_q   <= trap_tval;
            mstatus_q <= {mstatus_q[31:8], mstatus_q[3], 7'd0};
        end

        else if (mret_en) begin
            mstatus_q <= {mstatus_q[31:8], 1'b1, 3'd0, mstatus_q[7], 3'd0};
        end

        else if (write_ok) begin
            unique case (csr_addr)
                CSR_MSTATUS:  mstatus_q  <= (mstatus_q & ~MSTATUS_WMASK) | (csr_new & MSTATUS_WMASK);
                CSR_MIE:      mie_q      <= (mie_q & ~MIE_WMASK) | (csr_new & MIE_WMASK);
                CSR_MTVEC:    mtvec_q    <= csr_new & MTVEC_WMASK;
                CSR_MSCRATCH: mscratch_q <= csr_new;
                CSR_MEPC:     mepc_q     <= csr_new & MEPC_WMASK;
                CSR_MCAUSE:   mcause_q   <= csr_new;
                CSR_MTVAL:    mtval_q    <= csr_new;
                default: ;
            endcase
        end
    end

    // exposed outputs
    assign mstatus_o = mstatus_q;
    assign mtvec_o = mtvec_q;
    assign mepc_o = mepc_q;
    assign mie_o = mie_q;
    assign mip_o = mip_w;
endmodule
