import riscv_pkg::*;
import tbus_pkg::*;

module datapath (
    input clk, reset,

    // instruction port
    output logic [31:0] i_addr,
    input logic [31:0] i_data,

    // data port (tbus originator)
    output req_t o_req,
    input rsp_t o_rsp,

    // m-mode interrupt-pending wires
    input logic irq_msi,
    input logic irq_mti,
    input logic irq_mei
);
    // pipeline structs
    if_id_t if_id;
    id_ex_t id_ex;
    ex_ma_t ex_ma;
    ma_wb_t ma_wb;

    // stage status + redirect wiring (driven by the stage instances below)
    logic ex_busy, ma_busy;
    logic pc_en, trap_en;
    logic [31:0] pc_target;

    // hazard wiring
    wire load_use = ex_ma.load_en & (id_ex.rs1 == ex_ma.rd || id_ex.rs2 == ex_ma.rd);
    wire flush = pc_en; // redirect kills wrong-path IF/ID (pc_en is pre-gated in exec)

    // stalls
    wire ma_stall = ma_busy; // bus transaction in flight
    wire ex_stall = load_use | ex_busy | ma_stall; // operands or unit not ready

    // per-stage controls
    wire if_id_en = ~ex_stall;
    wire if_id_bubble = flush;
    wire id_ex_en = ~ex_stall;
    wire id_ex_bubble = flush;
    wire ex_ma_en = ~ma_stall;
    wire ex_ma_bubble = (ex_stall & ~ma_stall) | trap_en;
    wire ma_wb_en = ~ma_stall;
    wire ma_wb_bubble = '0;

    // pc
    logic [31:0] pc;
    always_ff @(posedge clk) begin
        if (reset) pc <= '0;
        else if (pc_en) pc <= pc_target;
        else if (if_id_en) pc <= pc + 4;
    end
    assign i_addr = pc;

    // regfile wiring
    logic rf_en;
    logic [31:0] rf_in;
    logic [4:0] rf_rd;
    logic [4:0] rf_rs1;
    logic [4:0] rf_rs2;
    logic [31:0] rf_rr1;
    logic [31:0] rf_rr2;
    regfile u_rf (
        .clk(clk),
        .reset(reset),
        .rf_rs1(rf_rs1),
        .rf_rs2(rf_rs2),
        .rf_en(rf_en),
        .rf_rd(rf_rd),
        .rf_in(rf_in),
        .rf_rr1(rf_rr1),
        .rf_rr2(rf_rr2)
    );

    // forwarding
    logic [31:0] fwd_rr1, fwd_rr2;
    forward u_fw (
        .ex_rs1(id_ex.rs1),
        .ex_rs2(id_ex.rs2),
        .ex_rr1(id_ex.rr1),
        .ex_rr2(id_ex.rr2),
        .ex_ma(ex_ma),
        .ma_wb(ma_wb),
        .fwd_rr1(fwd_rr1),
        .fwd_rr2(fwd_rr2)
    );

    // pipeline stages
    tx_fetch u_fetch (
        .clk(clk),
        .reset(reset),
        .en(if_id_en),
        .bubble(if_id_bubble),
        .pc_in(pc),
        .inst_in(i_data),
        .if_id(if_id)
    );

    tx_decode u_decode (
        .clk(clk),
        .reset(reset),
        .en(id_ex_en),
        .bubble(id_ex_bubble),
        .if_id(if_id),
        .rf_rr1(rf_rr1),
        .rf_rr2(rf_rr2),
        .rf_rs1(rf_rs1),
        .rf_rs2(rf_rs2),
        .id_ex(id_ex)
    );

    tx_exec u_exec (
        .clk(clk),
        .reset(reset),
        .en(ex_ma_en),
        .bubble(ex_ma_bubble),
        .load_use(load_use),
        .ex_busy(ex_busy),
        .id_ex(id_ex),
        .fwd_rr1(fwd_rr1),
        .fwd_rr2(fwd_rr2),
        .irq_msi(irq_msi),
        .irq_mti(irq_mti),
        .irq_mei(irq_mei),
        .pc_target(pc_target),
        .pc_en(pc_en),
        .trap_en(trap_en),
        .ex_ma(ex_ma)
    );

    tx_mem u_ma (
        .clk(clk),
        .reset(reset),
        .en(ma_wb_en),
        .bubble(ma_wb_bubble),
        .ma_busy(ma_busy),
        .ex_ma(ex_ma),
        .o_req(o_req),
        .o_rsp(o_rsp),
        .ma_wb(ma_wb)
    );

    tx_wback u_wback (
        .ma_wb(ma_wb),
        .rf_rd(rf_rd),
        .rf_data(rf_in),
        .rf_en(rf_en)
    );
endmodule
