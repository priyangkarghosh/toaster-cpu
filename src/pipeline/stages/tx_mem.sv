import riscv_pkg::*;
import tbus_pkg::*;

module tx_mem (
    input clk, reset, en, bubble,

    // output signals
    output ma_busy,

    // inputs from prev stage
    input ex_ma_t ex_ma,

    // data memory port
    output req_t o_req,
    input rsp_t o_rsp,

    // outputs to next stage
    output ma_wb_t ma_wb
);
    wire [1:0] boff = ex_ma.data[1:0];

    // encode be + lane-shifted wdata from mem_width + addr[1:0]
    logic [3:0] be;
    logic [31:0] wdata;
    always_comb begin
        be = '0;
        wdata = '0;
        case (ex_ma.mem_width)
            MW_WORD: begin
                be = 4'b1111;
                wdata = ex_ma.rr2;
            end
            MW_HALF, MW_HALFU: case (boff)
                2'd0: begin be = 4'b0011; wdata = {16'b0, ex_ma.rr2[15:0]}; end
                2'd2: begin be = 4'b1100; wdata = {ex_ma.rr2[15:0], 16'b0}; end
                default: ; // misaligned
            endcase
            MW_BYTE, MW_BYTEU: case (boff)
                2'd0: begin be = 4'b0001; wdata = {24'b0, ex_ma.rr2[7:0]}; end
                2'd1: begin be = 4'b0010; wdata = {16'b0, ex_ma.rr2[7:0], 8'b0}; end
                2'd2: begin be = 4'b0100; wdata = {8'b0, ex_ma.rr2[7:0], 16'b0}; end
                2'd3: begin be = 4'b1000; wdata = {ex_ma.rr2[7:0], 24'b0}; end
            endcase
            default: ;
        endcase
    end

    // extract byte/half lane from returned word, sign/zero-ext per mem_width
    logic [31:0] rdata;
    always_comb begin
        case (ex_ma.mem_width)
            MW_BYTE: case (boff)
                2'd0: rdata = {{24{o_rsp.rdata[7]}},  o_rsp.rdata[7:0]};
                2'd1: rdata = {{24{o_rsp.rdata[15]}}, o_rsp.rdata[15:8]};
                2'd2: rdata = {{24{o_rsp.rdata[23]}}, o_rsp.rdata[23:16]};
                2'd3: rdata = {{24{o_rsp.rdata[31]}}, o_rsp.rdata[31:24]};
            endcase
            MW_BYTEU: case (boff)
                2'd0: rdata = {24'b0, o_rsp.rdata[7:0]};
                2'd1: rdata = {24'b0, o_rsp.rdata[15:8]};
                2'd2: rdata = {24'b0, o_rsp.rdata[23:16]};
                2'd3: rdata = {24'b0, o_rsp.rdata[31:24]};
            endcase
            MW_HALF: case (boff)
                2'd0: rdata = {{16{o_rsp.rdata[15]}}, o_rsp.rdata[15:0]};
                2'd2: rdata = {{16{o_rsp.rdata[31]}}, o_rsp.rdata[31:16]};
                default: rdata = '0; // misaligned
            endcase
            MW_HALFU: case (boff)
                2'd0: rdata = {16'b0, o_rsp.rdata[15:0]};
                2'd2: rdata = {16'b0, o_rsp.rdata[31:16]};
                default: rdata = '0;
            endcase
            MW_WORD: rdata = o_rsp.rdata;
            default: rdata = '0;
        endcase
    end

    // set response data
    assign o_req.valid = ex_ma.load_en | ex_ma.store_en;
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
