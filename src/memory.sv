import riscv_pkg::*;

module memory #(
    parameter MEM_FILE = "",
    parameter W = 32,
    parameter CAPACITY = 512  // in words
)(
    input clk,

    // instruction port
    input [W-1:0] i_addr,
    output logic [W-1:0] i_data,

    // data port
    input logic d_write,
    input mem_width_t d_width,
    input [W-1:0] d_addr,
    input [W-1:0] d_wdata,
    output logic [W-1:0] d_rdata
);
    reg [W-1:0] mem [0:CAPACITY-1];
    initial $readmemh(MEM_FILE, mem);

    // convert byte addresses to word
    wire [$clog2(CAPACITY)-1:0] i_widx = i_addr[W-1:2];
    wire [$clog2(CAPACITY)-1:0] d_widx = d_addr[W-1:2];
    wire [1:0] d_boff = d_addr[1:0];

    // reads
    assign i_data = mem[i_widx];
    always_comb begin
        case (d_width)
            MW_BYTE: begin
                case (d_boff)
                    2'd0: d_rdata = {{24{mem[d_widx][7]}},  mem[d_widx][7:0]};
                    2'd1: d_rdata = {{24{mem[d_widx][15]}}, mem[d_widx][15:8]};
                    2'd2: d_rdata = {{24{mem[d_widx][23]}}, mem[d_widx][23:16]};
                    2'd3: d_rdata = {{24{mem[d_widx][31]}}, mem[d_widx][31:24]};
                endcase
            end

            MW_HALF: begin
                case (d_boff)
                    2'd0: d_rdata = {{16{mem[d_widx][15]}}, mem[d_widx][15:0]};
                    2'd2: d_rdata = {{16{mem[d_widx][31]}}, mem[d_widx][31:16]};
                    default: d_rdata = '0; // misaligned
                endcase
            end

            MW_BYTEU: begin
                case (d_boff)
                    2'd0: d_rdata = {24'b0, mem[d_widx][7:0]};
                    2'd1: d_rdata = {24'b0, mem[d_widx][15:8]};
                    2'd2: d_rdata = {24'b0, mem[d_widx][23:16]};
                    2'd3: d_rdata = {24'b0, mem[d_widx][31:24]};
                endcase
            end

            MW_HALFU: begin
                case (d_boff)
                    2'd0: d_rdata = {16'b0, mem[d_widx][15:0]};
                    2'd2: d_rdata = {16'b0, mem[d_widx][31:16]};
                    default: d_rdata = '0; // misaligned
                endcase
            end

            MW_WORD: d_rdata = mem[d_widx];
            default: d_rdata = '0;
        endcase
    end

    // writes
    always_ff @(posedge clk) begin
        if (d_write) begin
            case (d_width)
                MW_BYTE: begin
                    case (d_boff)
                        2'd0: mem[d_widx][7:0]   <= d_wdata[7:0];
                        2'd1: mem[d_widx][15:8]  <= d_wdata[7:0];
                        2'd2: mem[d_widx][23:16] <= d_wdata[7:0];
                        2'd3: mem[d_widx][31:24] <= d_wdata[7:0];
                    endcase
                end

                MW_HALF: begin
                    case (d_boff)
                        2'd0: mem[d_widx][15:0]  <= d_wdata[15:0];
                        2'd2: mem[d_widx][31:16] <= d_wdata[15:0];
                        default: ; // misaligned
                    endcase
                end

                MW_WORD: mem[d_widx] <= d_wdata;
                default: ;
            endcase
        end
    end
endmodule
