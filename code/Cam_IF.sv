`timescale 1ns / 1ps

module Cam_IF #(
    parameter IMG_W = 320,
    parameter IMG_H = 240,
    parameter DW    = 16,
    parameter AW    = $clog2(IMG_W * IMG_H)
)(

    input  logic clk,
    input  logic reset,
    input  logic reset_pclk,

    input logic i_cam_stream_en,
    output logic o_cam_ready,

    input  logic       pclk,
    output logic       xclk,
    input  logic       cam_href,
    input  logic       cam_vsync,
    input  logic [7:0] cam_data,

    output logic scl,
    inout  wire  sda,

    output logic          w_en,

    output logic [DW-1:0] w_data,
    output logic [8:0]    pixel_x,
    output logic [7:0]    pixel_y
);

    logic [9:0] pixel_x_full;
    logic [8:0] pixel_y_full;
    assign pixel_x = pixel_x_full[8:0];
    assign pixel_y = pixel_y_full[7:0];

    top_setup u_top_setup (
        .clk        (clk),
        .reset        (reset),
        .scl        (scl),
        .sda        (sda),
        .setup_done (o_cam_ready)
    );

    cam_xclk_gen u_cam_xclk_gen (
        .clk   (clk),
        .reset (reset),
        .xclk  (xclk)
    );

    ov7670_mem_controller #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .DW    (DW),
        .AW    (AW)
    ) u_ov7670_mem_controller (
        .pclk      (pclk),
        .reset     (reset_pclk),
        .i_cam_stream_en (i_cam_stream_en),

        .cam_href  (cam_href),
        .cam_vsync (cam_vsync),
        .cam_data  (cam_data),

        .we         (w_en),
        .wAddr      (),
        .wData      (w_data),

        .x          (pixel_x_full),
        .y          (pixel_y_full)
    );

endmodule

module cam_xclk_gen (
    input  logic clk,
    input  logic reset,
    output logic xclk
);

    logic [1:0] div_cnt;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            div_cnt <= 2'b00;
        end
        else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    assign xclk = div_cnt[1];

endmodule
