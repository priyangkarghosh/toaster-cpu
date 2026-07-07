import riscv_pkg::*;
import ooo_pkg::*;

module rob # (
    parameter INDEX_BITS = 4
) (
    // sync
    input logic clk, reset,

    // input signals
    input logic flush,
    input logic retire_en,

    // entry being allocated
    input logic alloc_en,
    input rob_entry_t alloc_entry,

    // completion inputs (from MA)
    input logic comp_en,
    input logic [INDEX_BITS-1:0] comp_idx,
    input comp_req_t comp_req,

    // entry being retired
    output logic head_ready,
    output rob_entry_t head_entry,

    // output signals
    output logic [INDEX_BITS-1:0] alloc_idx,
    output logic full
);
    localparam BUF_DEPTH = 1 << INDEX_BITS;
    rob_entry_t buffer [0:BUF_DEPTH-1];

    // fifo state
    logic empty;
    logic [INDEX_BITS-1:0] head, tail;
    always_ff @(posedge clk) begin
        if (reset | flush) begin
            head <= '0;
            tail <= '0;
            full <= '0;
        end

        else begin
            if (alloc_en) begin
                buffer[tail] <= alloc_entry;
                buffer[tail].done <= 1'b0;
                full <= (~retire_en & (head == tail)) | (retire_en & full);
                tail <= tail + 1'b1;
            end

            if (comp_en) begin
                buffer[comp_idx].exc <= comp_req.exc;
                buffer[comp_idx].data <= comp_req.data;
                buffer[comp_idx].done <= 1'b1;
            end

            if (retire_en) begin
                head <= head + 1'b1;
                full <= '0;
            end
        end
    end

    assign alloc_idx = tail;
    assign head_entry = buffer[head];
    assign head_ready = head_entry.done & (full | (head != tail));

    // DEBUG
    // synthesis translate_off
    wire [INDEX_BITS-1:0] count = tail - head;
    always @(posedge clk) if (~reset & comp_en)
        assert (full | ((comp_idx - head) < count));
    // synthesis translate_on
endmodule
