import riscv_pkg::*;

module csr # (
    // sync
    input clk, reset,

    // read/write port
    input logic csr_en,
    input logic [11:0] csr_addr,
    input logic [31:0] csr_in,
    output logic [31:0] csr_out
);
    // csr addresses
    localparam logic [11:0] CSR_MSTATUS   = 12'h300;
    localparam logic [11:0] CSR_MISA      = 12'h301;
    localparam logic [11:0] CSR_MIE       = 12'h304;
    localparam logic [11:0] CSR_MTVEC     = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
    localparam logic [11:0] CSR_MEPC      = 12'h341;
    localparam logic [11:0] CSR_MCAUSE    = 12'h342;
    localparam logic [11:0] CSR_MTVAL     = 12'h343;
    localparam logic [11:0] CSR_MIP       = 12'h344;
    localparam logic [11:0] CSR_MVENDORID = 12'hF11;
    localparam logic [11:0] CSR_MARCHID   = 12'hF12;
    localparam logic [11:0] CSR_MIMPID    = 12'hF13;
    localparam logic [11:0] CSR_MHARTID   = 12'hF14;

    // csr registers
    logic [31:0] mstatus, mepc, mcause;

    // read logic
    always_comb begin
        unique case (csr_addr)
            CSR_MSTATUS: csr_rdata = mstatus;
            CSR_MTVEC:   csr_rdata = mtvec;
            CSR_MEPC:    csr_rdata = mepc;
            CSR_MCAUSE:  csr_rdata = mcause;
            default:     csr_rdata = '0;
        endcase
    end

    // write logic
    always_ff @(posedge clk) begin
        if (reset) begin
            mstatus <= '0;
            mtvec <= '0;
            mepc <= '0;
            mcause <= '0;
        end

        else if (csr_we) begin
            unique case (csr_addr)
                CSR_MSTATUS: mstatus <= csr_wdata;
                CSR_MTVEC:   mtvec   <= csr_wdata;
                CSR_MEPC:    mepc    <= csr_wdata;
                CSR_MCAUSE:  mcause  <= csr_wdata;
                default: ;
            endcase
        end
    end
endmodule
