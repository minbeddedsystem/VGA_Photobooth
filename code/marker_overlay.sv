`timescale 1ns / 1ps

module marker_overlay #(
    parameter MEM_W = 320,
    parameter MEM_H = 240,
    parameter FRAME_THICKNESS = 4,
    parameter CURSOR_ARM = 3
) (
    input logic clk,
    input logic rst,

    input logic [9:0] i_x_pixel,
    input logic [9:0] i_y_pixel,
    input logic [9:0] i_marker_x,
    input logic [9:0] i_marker_y,
    input logic       i_marker_valid,

    input logic [1:0] i_edit_mode,
    input logic i_edit_active,
    input logic [1:0] i_stk_id,
    input logic [1:0] i_stk_size,
    input  logic        i_stk_place_p,
    input logic [2:0] i_draw_color,

    input  logic        i_frame_sel,

    input  logic [11:0] i_mem_rdata,

    output logic [11:0] o_pixel_data
);

    localparam EDIT_STICKER = 2'b01;
    localparam EDIT_DRAW = 2'b10;

    function automatic [9:0] clamp_pos(input [9:0] center, input [9:0] len,
                                       input [9:0] mem_len);
        if (center < (len >> 1)) clamp_pos = 10'd0;
        else if (center - (len >> 1) + len > mem_len) clamp_pos = mem_len - len;
        else clamp_pos = center - (len >> 1);
    endfunction

    function automatic [9:0] stk_len_of(input [1:0] size);
        case (size)
            2'd3:    stk_len_of = 10'd32;
            2'd2:    stk_len_of = 10'd16;
            2'd1:    stk_len_of = 10'd8;
            default: stk_len_of = 10'd4;
        endcase
    endfunction

    wire [9:0] stk_len = stk_len_of(i_stk_size);

    logic [9:0] stk_x, stk_y;
    always_ff @(posedge clk) begin
        if (rst) begin
            stk_x <= 10'd0;
            stk_y <= 10'd0;
        end else if (!i_stk_place_p && i_marker_valid) begin
            stk_x <= clamp_pos(i_marker_x, stk_len, MEM_W[9:0]);
            stk_y <= clamp_pos(i_marker_y, stk_len, MEM_H[9:0]);
        end
    end

    wire stk_hit = i_marker_valid && (i_edit_mode == EDIT_STICKER) &&
                   (i_x_pixel >= stk_x) && (i_x_pixel < stk_x + stk_len) &&
                   (i_y_pixel >= stk_y) && (i_y_pixel < stk_y + stk_len);

    logic stk_hit_q;
    always_ff @(posedge clk) stk_hit_q <= stk_hit;

    wire [9:0] stk_rom_x = i_x_pixel - stk_x;
    wire [9:0] stk_rom_y = i_y_pixel - stk_y;

    logic [11:0] stk_rgb;
    logic stk_transparent;

    sticker_rom U_STICKER_ROM (
        .clk        (clk),
        .idx        (i_stk_id),
        .size       (i_stk_size),
        .x          (stk_rom_x[4:0]),
        .y          (stk_rom_y[4:0]),
        .rgb        (stk_rgb),
        .transparent(stk_transparent)
    );

    wire draw_hit = (i_edit_mode == EDIT_DRAW) && i_edit_active &&
                     (i_x_pixel == i_marker_x) && (i_y_pixel == i_marker_y);

    logic [11:0] draw_rgb;
    always_comb begin
        case (i_draw_color)
            3'd0: draw_rgb = 12'h000;
            3'd1: draw_rgb = 12'hF00;
            3'd2: draw_rgb = 12'hF80;
            3'd3: draw_rgb = 12'hFF0;
            3'd4: draw_rgb = 12'h0F0;
            3'd5: draw_rgb = 12'h00F;
            3'd6: draw_rgb = 12'h309;
            3'd7: draw_rgb = 12'hF0F;
            default: draw_rgb = 12'h000;
        endcase
    end

    localparam [9:0] FRAME_HALF_W = MEM_W[9:0] >> 1;
    localparam [9:0] FRAME_HALF_H = MEM_H[9:0] >> 1;
    localparam [9:0] FRAME_T = FRAME_THICKNESS[9:0];

    wire frame_border = (i_x_pixel < FRAME_T) || (i_x_pixel >= MEM_W[9:0] - FRAME_T) ||
                         (i_y_pixel < FRAME_T) || (i_y_pixel >= MEM_H[9:0] - FRAME_T);

    wire frame_cross = (i_x_pixel >= FRAME_HALF_W - (FRAME_T >> 1) && i_x_pixel < FRAME_HALF_W + (FRAME_T >> 1)) ||
                        (i_y_pixel >= FRAME_HALF_H - (FRAME_T >> 1) && i_y_pixel < FRAME_HALF_H + (FRAME_T >> 1));

    wire frame_hit = frame_border || frame_cross;
    wire [11:0] frame_rgb = i_frame_sel ? 12'h000 : 12'hFFF;

    wire [9:0] cx_dist = (i_x_pixel >= i_marker_x) ? (i_x_pixel - i_marker_x) : (i_marker_x - i_x_pixel);
    wire [9:0] cy_dist = (i_y_pixel >= i_marker_y) ? (i_y_pixel - i_marker_y) : (i_marker_y - i_y_pixel);

    wire cursor_hit = i_marker_valid && (i_edit_mode != EDIT_STICKER) &&
                       ((i_y_pixel == i_marker_y && i_x_pixel != i_marker_x && cx_dist <= CURSOR_ARM[9:0]) ||
                        (i_x_pixel == i_marker_x && i_y_pixel != i_marker_y && cy_dist <= CURSOR_ARM[9:0]));

    wire [11:0] cursor_rgb = (i_edit_mode == EDIT_DRAW) ? draw_rgb : 12'h0FF;

    logic stk_hit_d1, draw_hit_d1, cursor_hit_d1, frame_hit_d1;
    logic [11:0] stk_rgb_d1, draw_rgb_d1, cursor_rgb_d1, frame_rgb_d1;
    logic stk_hit_d2, draw_hit_d2, cursor_hit_d2, frame_hit_d2;
    logic [11:0] stk_rgb_d2, draw_rgb_d2, cursor_rgb_d2, frame_rgb_d2;
    logic stk_hit_d3, draw_hit_d3, cursor_hit_d3, frame_hit_d3;
    logic [11:0] stk_rgb_d3, draw_rgb_d3, cursor_rgb_d3, frame_rgb_d3;
    always_ff @(posedge clk) begin
        stk_hit_d1    <= stk_hit_q && !stk_transparent;
        draw_hit_d1   <= draw_hit;
        cursor_hit_d1 <= cursor_hit;
        frame_hit_d1  <= frame_hit;
        stk_rgb_d1    <= stk_rgb;
        draw_rgb_d1   <= draw_rgb;
        cursor_rgb_d1 <= cursor_rgb;
        frame_rgb_d1  <= frame_rgb;

        stk_hit_d2    <= stk_hit_d1;
        draw_hit_d2   <= draw_hit_d1;
        cursor_hit_d2 <= cursor_hit_d1;
        frame_hit_d2  <= frame_hit_d1;
        stk_rgb_d2    <= stk_rgb_d1;
        draw_rgb_d2   <= draw_rgb_d1;
        cursor_rgb_d2 <= cursor_rgb_d1;
        frame_rgb_d2  <= frame_rgb_d1;

        stk_hit_d3    <= stk_hit_d2;
        draw_hit_d3   <= draw_hit_d2;
        cursor_hit_d3 <= cursor_hit_d2;
        frame_hit_d3  <= frame_hit_d2;
        stk_rgb_d3    <= stk_rgb_d2;
        draw_rgb_d3   <= draw_rgb_d2;
        cursor_rgb_d3 <= cursor_rgb_d2;
        frame_rgb_d3  <= frame_rgb_d2;
    end

    always_comb begin
        if (stk_hit_d2) o_pixel_data = stk_rgb_d2;
        else if (draw_hit_d3) o_pixel_data = draw_rgb_d3;
        else if (cursor_hit_d3) o_pixel_data = cursor_rgb_d3;
        else if (frame_hit_d3) o_pixel_data = frame_rgb_d3;
        else o_pixel_data = i_mem_rdata;
    end

endmodule
