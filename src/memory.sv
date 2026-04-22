import riscv_pkg::*;

module memory # (
    parameter MEM_FILE = "",
    parameter W = 32,
    parameter CAPACITY = 512 // in words
)(
    input clk,

    // read-only instruction port
    input [W-1:0] pc,
    output [W-1:0] inst_out,

    // read-write data port
    input logic write, // one-hot per byte in the word
    input mem_width_t width,
    input [W-1:0] addr,
    input [W-1:0] data_in,
    output [W-1:0] data_out
);
    // init the memory buffer
    localparam BUF_SIZE = W * CAPACITY;
    reg [7:0] buffer [0:BUF_SIZE-1];
    initial $readmemh(MEM_FILE, buffer);

    // async reads
    assign inst_out = {buffer[pc+3], buffer[pc+2], buffer[pc+1], buffer[pc]};
    always_comb begin
        case (width)
            MW_BYTE:   data_out = {{24{buffer[addr][7]}},  buffer[addr]};
            MW_HALF:   data_out = {{16{buffer[addr+1][7]}}, buffer[addr+1], buffer[addr]};
            MW_WORD:   data_out = {buffer[addr+3], buffer[addr+2], buffer[addr+1], buffer[addr]};
            MW_BYTEU:  data_out = {24'b0, buffer[addr]};
            MW_HALFU:  data_out = {16'b0, buffer[addr+1], buffer[addr]};
            default:   data_out = '0;
        endcase
    end

    // sync write
    always_ff @(posedge clk) begin
        if (write) begin
            case (width)
                MW_BYTE: buffer[addr] <= data_in[7:0];
                MW_HALF: begin
                    buffer[addr] <= data_in[7:0];
                    buffer[addr+1] <= data_in[15:8];
                end
                MW_WORD: begin
                    buffer[addr] <= data_in[7:0];
                    buffer[addr+1] <= data_in[15:8];
                    buffer[addr+2] <= data_in[23:16];
                    buffer[addr+3] <= data_in[31:24];
                end
                default: ;
            endcase
        end
    end
endmodule
