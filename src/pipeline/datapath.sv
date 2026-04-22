import riscv_pkg::*;

module datapath (
    input clk, reset,

    // memory connections
    output logic [31:0] mem_pc,
    input  logic [31:0] mem_inst_in,

    output logic [3:0]  mem_write,
    output logic [31:0] mem_addr,
    input  logic [31:0] mem_data_in,
    output logic [31:0] mem_data_out
);
    // control wiring
    logic stall, flush, bubble;
    assign stall = 0;
    assign flush = 0;
    assign bubble = 0;

    // pc
    logic [31:0] pc;
    always_ff @(posedge clk) begin
        if (reset) pc <= '0;
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

    // memory
    assign mem_pc = pc;
    assign mem_write = 4'b0;
    assign mem_addr = '0;
    assign mem_data_out = '0;

    // pipeline structs
    if_id_t if_id;
    id_ex_t id_ex;
    ex_ma_t ex_ma;
    ma_wb_t ma_wb;

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
        .inst_in(mem_inst_in),
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
        .ex_ma(ex_ma)
    );

    tx_mem u_mem (
        .clk(clk), 
        .reset(reset),
        .ex_ma(ex_ma),
        .ma_wb(ma_wb)
    );

    tx_wback u_wback (
        .ma_wb(ma_wb),
        .rf_rd(rf_rd), 
        .rf_data(rf_in), 
        .rf_en(rf_en)
    );
endmodule
