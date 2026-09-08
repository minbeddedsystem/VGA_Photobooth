`timescale 1ns / 1ps

module async_fifo #(
    parameter DATA_WIDTH = 33,
    parameter ADDR_WIDTH = 4
) (

    input  logic                  wr_clk,
    input  logic                  wr_rst,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic                  wr_full,

    input  logic                  rd_clk,
    input  logic                  rd_rst,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  rd_empty
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem[0:DEPTH-1];

    logic [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_gray, wr_ptr_bin_next, wr_ptr_gray_next;
    logic [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_gray, rd_ptr_bin_next, rd_ptr_gray_next;
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    logic                 wr_full_val, rd_empty_val;

    assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en && !wr_full);
    assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    always_ff @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr_bin  <= '0;
            wr_ptr_gray <= '0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_en && !wr_full) mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    always_ff @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_ptr_gray_sync1 <= '0;
            rd_ptr_gray_sync2 <= '0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    assign wr_full_val = (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                                 rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});

    always_ff @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) wr_full <= 1'b0;
        else        wr_full <= wr_full_val;
    end

    assign rd_ptr_bin_next  = rd_ptr_bin + (rd_en && !rd_empty);
    assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr_bin  <= '0;
            rd_ptr_gray <= '0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            wr_ptr_gray_sync1 <= '0;
            wr_ptr_gray_sync2 <= '0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    assign rd_empty_val = (rd_ptr_gray_next == wr_ptr_gray_sync2);

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) rd_empty <= 1'b1;
        else        rd_empty <= rd_empty_val;
    end

endmodule
