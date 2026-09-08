`timescale 1ns / 1ps

module mem_addr_gen #(
    parameter MEM_W = 320,
    parameter MEM_H = 240
) (
    input  logic        clk,
    input  logic [9:0]  i_x_pixel,
    input  logic [9:0]  i_y_pixel,
    input  logic [9:0]  i_marker_x,
    input  logic [9:0]  i_marker_y,
    input  logic [1:0]  i_edit_mode,
    input  logic        i_edit_active,

    output logic [16:0] o_mem_raddr
);

    localparam EDIT_MOSAIC = 2'b11;
    localparam [9:0] MOSAIC_REGION_RADIUS = 10'd2;
    localparam [9:0] MOSAIC_MAX_X = MEM_W - 1 - MOSAIC_REGION_RADIUS;
    localparam [9:0] MOSAIC_MAX_Y = MEM_H - 1 - MOSAIC_REGION_RADIUS;

    wire mosaic_mode_on = (i_edit_mode == EDIT_MOSAIC) && i_edit_active;

    wire [9:0] mosaic_center_x = (i_marker_x < MOSAIC_REGION_RADIUS) ? MOSAIC_REGION_RADIUS : (i_marker_x > MOSAIC_MAX_X) ? MOSAIC_MAX_X : i_marker_x;
    wire [9:0] mosaic_center_y = (i_marker_y < MOSAIC_REGION_RADIUS) ? MOSAIC_REGION_RADIUS : (i_marker_y > MOSAIC_MAX_Y) ? MOSAIC_MAX_Y : i_marker_y;

    wire [9:0] mdx = (i_x_pixel >= mosaic_center_x) ? (i_x_pixel - mosaic_center_x) : (mosaic_center_x - i_x_pixel);
    wire [9:0] mdy = (i_y_pixel >= mosaic_center_y) ? (i_y_pixel - mosaic_center_y) : (mosaic_center_y - i_y_pixel);
    wire in_region = (mdx <= MOSAIC_REGION_RADIUS) && (mdy <= MOSAIC_REGION_RADIUS);

    wire mosaic_on = mosaic_mode_on && in_region;

    wire [9:0] mem_x = mosaic_on ? mosaic_center_x : i_x_pixel;
    wire [9:0] mem_y = mosaic_on ? mosaic_center_y : i_y_pixel;

    logic [9:0] mem_x_r1, mem_y_r1;
    always_ff @(posedge clk) begin
        mem_x_r1 <= mem_x;
        mem_y_r1 <= mem_y;
    end

    wire [16:0] mem_raddr_comb = mem_y_r1 * MEM_W + mem_x_r1;
    logic [16:0] mem_raddr_r2;
    always_ff @(posedge clk) mem_raddr_r2 <= mem_raddr_comb;
    assign o_mem_raddr = mem_raddr_r2;

endmodule
