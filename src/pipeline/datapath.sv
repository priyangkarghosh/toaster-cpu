import riscv_pkg::*;

module datapath (
    input clk, reset,
    
    // instruction port
    output logic [31:0] i_addr,
    input logic [31:0] i_data,

    // data port
    output logic d_write,
    output logic [31:0] d_addr,
    input  logic [31:0] d_rdata,
    output logic [31:0] d_wdata,
    output mem_width_t d_width
);
    // control wiring
    logic stall, flush, bubble;

    // pc
    logic pc_en;
    logic [31:0] pc;
    logic [31:0] pc_target;
    always_ff @(posedge clk) begin
        if (reset) pc <= '0;
        else if (pc_en) pc <= pc_target;
        else if (!stall) pc <= pc + 4;
    end

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

    // instruction memory connections
    assign i_addr = pc;

    // pipeline structs
    if_id_t if_id;
    id_ex_t id_ex;
    ex_ma_t ex_ma;
    ma_wb_t ma_wb;

    // hazard wiring
    wire load_use = ex_ma.load_en & (id_ex.rs1 == ex_ma.rd || id_ex.rs2 == ex_ma.rd);
    assign stall = load_use;
    assign flush = pc_en & !load_use; // CHECK BEHAVIOUR OF BRANCH AFTER LOAD
    assign bubble = load_use;

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
        .stall(stall), 
        .flush(flush),
        .pc_in(pc), 
        .inst_in(i_data),
        .if_id(if_id)
    );

    tx_decode u_decode (
        .clk(clk), 
        .reset(reset), 
        .stall(stall), 
        .flush(flush),
        .if_id(if_id),
        .rf_rr1(rf_rr1), 
        .rf_rr2(rf_rr2),
        .pc_next(pc),
        .rf_rs1(rf_rs1), 
        .rf_rs2(rf_rs2),
        .id_ex(id_ex)
    );

    tx_exec u_exec (
        .clk(clk), 
        .reset(reset), 
        .bubble(bubble),
        .id_ex(id_ex),
        .fwd_rr1(fwd_rr1), 
        .fwd_rr2(fwd_rr2),
        .pc_target(pc_target),
        .pc_en(pc_en),
        .ex_ma(ex_ma)
    );

    tx_mem u_mem (
        .clk(clk), 
        .reset(reset),
        .ex_ma(ex_ma),
        .d_addr(d_addr),
        .d_rdata(d_rdata),
        .d_wdata(d_wdata),
        .d_width(d_width),
        .d_write(d_write),
        .ma_wb(ma_wb)
    );

    tx_wback u_wback (
        .ma_wb(ma_wb),
        .rf_rd(rf_rd), 
        .rf_data(rf_in), 
        .rf_en(rf_en)
    );
endmodule
