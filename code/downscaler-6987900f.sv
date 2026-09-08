`timescale 1ns / 1ps

module downscaler (
    input  logic [9:0] i_x_pixel,
    input  logic [9:0] i_y_pixel,
    output logic [9:0] o_x_pixel,
    output logic [9:0] o_y_pixel
);

    assign o_x_pixel = i_x_pixel >> 1;
    assign o_y_pixel = i_y_pixel >> 1;

endmodule