import riscv_pkg::*;

module memory #(
    parameter MEM_FILE = "",
    parameter W = 32,
    parameter CAPACITY = 512 // in words
)(
    input clk,

    // instruction port
    input [W-1:0] i_addr,
    output [W-1:0] i_data,

    // data port
    input logic d_write,
    input mem_width_t d_width,
    input [W-1:0] d_addr,
    input [W-1:0] d_wdata,
    output [W-1:0] d_rdata
);
    localparam NUM_BYTES = (W / 8) * CAPACITY;
    reg [7:0] mem [0:NUM_BYTES-1];
    initial $readmemh(MEM_FILE, mem);

    // async instruction read
    assign i_data = {mem[i_addr+3], mem[i_addr+2], mem[i_addr+1], mem[i_addr]};

    // async data read
    always_comb begin
        case (d_width)
            MW_BYTE:  d_rdata = {{24{mem[d_addr][7]}},  mem[d_addr]};
            MW_HALF:  d_rdata = {{16{mem[d_addr+1][7]}}, mem[d_addr+1], mem[d_addr]};
            MW_WORD:  d_rdata = {mem[d_addr+3], mem[d_addr+2], mem[d_addr+1], mem[d_addr]};
            MW_BYTEU: d_rdata = {24'b0, mem[d_addr]};
            MW_HALFU: d_rdata = {16'b0, mem[d_addr+1], mem[d_addr]};
            default:  d_rdata = '0;
        endcase
    end

    // sync data write
    always_ff @(posedge clk) begin
        if (d_write) begin
            case (d_width)
                MW_BYTE: mem[d_addr] <= d_wdata[7:0];
                MW_HALF: begin
                    mem[d_addr] <= d_wdata[7:0];
                    mem[d_addr+1] <= d_wdata[15:8];
                end
                MW_WORD: begin
                    mem[d_addr] <= d_wdata[7:0];
                    mem[d_addr+1] <= d_wdata[15:8];
                    mem[d_addr+2] <= d_wdata[23:16];
                    mem[d_addr+3] <= d_wdata[31:24];
                end
                default: ;
            endcase
        end
    end
endmodule
