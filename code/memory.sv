`timescale 1ns / 1ps

module memory #(
    parameter MEM_W = 320,
    parameter MEM_H = 240
) (
    input logic clk,
    input logic rst,

    input  logic        i_we,
    input  logic [16:0] i_addr,
    input  logic [11:0] i_wdata,
    output logic [11:0] o_rdata_a,

    input  logic [16:0] i_raddr,
    output logic [11:0] o_rdata_b
);

    localparam DEPTH = MEM_W * MEM_H;

    (* ram_style = "block" *) logic [11:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (i_we) begin
            mem[i_addr] <= i_wdata;
        end
        o_rdata_a <= mem[i_addr];
    end

    always_ff @(posedge clk) begin
        o_rdata_b <= mem[i_raddr];
    end

endmodule
