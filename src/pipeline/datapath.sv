import riscv_pkg::*;

module datapath #(
    parameter W = 32,
    parameter RF_ADDR_BITS = 5
)(
    input clk, reset,

    // memory connections
    output logic [W-1:0] mem_pc,
    input logic [W-1:0] mem_inst_in,

    output logic [3:0] mem_write,
    output logic [W-1:0] mem_addr,
    input logic [W-1:0] mem_data_in,
    output logic [W-1:0] mem_data_out
);
    // control wiring
    logic stall, flush, bubble;
    assign stall = 0;
    assign flush = 0;
    assign bubble = 0;

    // pc wiring
    logic [W-1:0] pc;
    wire [W-1:0] pc_next = pc + 4;
    always_ff @(posedge clk) begin
        if (reset) pc <= '0;
        else if (!stall) pc <= pc_next;
    end

    // regfile wiring
    logic rf_write;
    logic [W-1:0] rf_in;
    logic [RF_ADDR_BITS-1:0] rf_rd;
    logic [RF_ADDR_BITS-1:0] rf_rs1, rf_rs2;
    logic [W-1:0] rf_rr1, rf_rr2;
    regfile #(.W(W), .RF_ADDR_BITS(RF_ADDR_BITS)) u_rf (
        .clk(clk),
        .reset(reset),
        .rf_rs1(rf_rs1),
        .rf_rs2(rf_rs2),
        .rf_write(rf_write),
        .rf_rd(rf_rd),
        .rf_in(rf_in),
        .rf_rr1(rf_rr1),
        .rf_rr2(rf_rr2)
    );

    // mem wiring
    assign mem_pc = pc;
    assign mem_write = 4'b0;
    assign mem_addr = '0;
    assign mem_data_out = '0;

    // if -> id wiring
    logic [W-1:0] id_ir, id_pc;

    // id -> ex wiring
    logic [W-1:0] ex_pc, ex_imm, ex_rr1, ex_rr2;
    logic [RF_ADDR_BITS-1:0] ex_rs1, ex_rs2, ex_rd;
    alu_op_t ex_alu_op;
    logic ex_use_imm, ex_rf_write;

    // ex -> mem wiring
    logic [RF_ADDR_BITS-1:0] mem_rd;
    logic [W-1:0] mem_alu;
    logic mem_rf_write;

    // mem -> wb wiring
    logic [RF_ADDR_BITS-1:0] wb_rd;
    logic [W-1:0] wb_alu;
    logic wb_rf_write;

    // forwarding unit
    wire [W-1:0] fwd_rr1, fwd_rr2;
    forward #(.W(W), .RF_ADDR_BITS(RF_ADDR_BITS)) u_fw (
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .ex_rr1(ex_rr1),
        .ex_rr2(ex_rr2),
        .mem_rd(mem_rd),
        .mem_alu(mem_alu),
        .mem_rf_write(mem_rf_write),
        .wb_rd(wb_rd),
        .wb_alu(wb_alu),
        .wb_rf_write(wb_rf_write),
        .fwd_rr1(fwd_rr1),
        .fwd_rr2(fwd_rr2)
    );

    // instantiate stages
    tx_fetch #(.W(W), .RF_ADDR_BITS(RF_ADDR_BITS)) u_fetch (
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .flush(flush),
        .pc_in(pc),
        .inst_in(mem_inst_in),
        .id_ir(id_ir),
        .id_pc(id_pc)
    );

    tx_decode #(.W(W), .RF_ADDR_BITS(RF_ADDR_BITS)) u_decode (
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .flush(flush),
        .id_ir(id_ir),
        .id_pc(id_pc),
        .rf_rr1(rf_rr1),
        .rf_rr2(rf_rr2),
        .rf_rs1(rf_rs1),
        .rf_rs2(rf_rs2),
        .ex_pc(ex_pc),
        .ex_imm(ex_imm),
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd),
        .ex_rr1(ex_rr1),
        .ex_rr2(ex_rr2),
        .ex_alu_op(ex_alu_op),
        .ex_use_imm(ex_use_imm),
        .ex_rf_write(ex_rf_write)
    );

    tx_exec #(.W(W), .RF_ADDR_BITS(RF_ADDR_BITS)) u_exec (
        .clk(clk),
        .reset(reset),
        .bubble(bubble),
        .ex_pc(ex_pc),
        .ex_imm(ex_imm),
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd),
        .fwd_rr1(fwd_rr1),
        .fwd_rr2(fwd_rr2),
        .ex_alu_op(ex_alu_op),
        .ex_use_imm(ex_use_imm),
        .ex_rf_write(ex_rf_write),
        .mem_rd(mem_rd),
        .mem_alu(mem_alu),
        .mem_rf_write(mem_rf_write)
    );

    tx_mem #(.W(W), .RF_ADDR_BITS(RF_ADDR_BITS)) u_mem (
        .clk(clk),
        .reset(reset),
        .mem_rd(mem_rd),
        .mem_alu(mem_alu),
        .mem_rf_write(mem_rf_write),
        .wb_rd(wb_rd),
        .wb_alu(wb_alu),
        .wb_rf_write(wb_rf_write)
    );

    tx_wback #(.W(W), .RF_ADDR_BITS(RF_ADDR_BITS)) u_wback (
        .clk(clk),
        .reset(reset),
        .wb_rd(wb_rd),
        .wb_alu(wb_alu),
        .wb_rf_write(wb_rf_write),
        .rf_rd(rf_rd),
        .rf_data(rf_in),
        .rf_write(rf_write)
    );
endmodule
