`timescale 1ns / 1ps

module mem_writer (
    input  logic        clk,
    input  logic        reset,
    input  logic [ 1:0] i_edit_mode,
    input  logic        i_edit_active,
    input  logic [ 1:0] i_stk_id,
    input  logic [ 1:0] i_stk_size,
    input  logic        i_stk_place_p,
    input  logic [ 2:0] i_draw_color,
    input  logic [ 8:0] marker_x,
    input  logic [ 7:0] marker_y,
    input  logic        marker_valid,
    output logic        mem_en,
    output logic [16:0] mem_waddr,
    output logic [11:0] mem_wdata,
    output logic [16:0] mem_raddr,
    input  logic [11:0] mem_rdata,

    output logic [1:0]  stk_rom_idx,
    output logic [1:0]  stk_rom_size,
    output logic [4:0]  stk_rom_x,
    output logic [4:0]  stk_rom_y,
    input  logic [11:0] stk_rom_rgb,
    input  logic         stk_rom_transparent
);

    parameter MEM_W = 320;
    parameter MEM_H = 240;

    parameter IDLE = 0, STICKER = 1, DRAWING = 2, WAIT_MOSAIC = 3, MOSAIC = 4,
              STK_PREP = 5, MO_PREP = 6;

    localparam [8:0] MOSAIC_HALF = 9'd2;
    localparam [8:0] MOSAIC_SIZE = 9'd5;

    logic [2:0] c_state, n_state;
    logic mem_en_r, n_mem_en_r;
    logic [16:0] mem_waddr_r, n_mem_waddr_r;
    logic [11:0] mem_wdata_r, n_mem_wdata_r;
    logic [16:0] mem_raddr_r, n_mem_raddr_r;

    logic [3:0] write_cnt, n_write_cnt;
    logic [8:0] marker_x_r, n_marker_x_r;
    logic [7:0] marker_y_r, n_marker_y_r;
    logic [8:0] n_marker_y_r_c9;

    parameter BLACK = 12'h000;
    parameter RED = 12'hF00;
    parameter ORANGE = 12'hF80;
    parameter YELLOW = 12'hFF0;
    parameter GREEN = 12'h0F0;
    parameter BLUE = 12'h00F;
    parameter NAVY = 12'h309;
    parameter PURPLE = 12'hF0F;

    assign mem_en    = mem_en_r;
    assign mem_waddr = mem_waddr_r;
    assign mem_wdata = mem_wdata_r;
    assign mem_raddr = mem_raddr_r;

    logic [11:0] draw_rgb;
    always_comb begin
        case (i_draw_color)
            3'd0: draw_rgb = BLACK;
            3'd1: draw_rgb = RED;
            3'd2: draw_rgb = ORANGE;
            3'd3: draw_rgb = YELLOW;
            3'd4: draw_rgb = GREEN;
            3'd5: draw_rgb = BLUE;
            3'd6: draw_rgb = NAVY;
            3'd7: draw_rgb = PURPLE;
        endcase
    end

    function automatic [8:0] clamp_center_w(input [8:0] c, input [8:0] half, input [8:0] dim);
        if (c < half)
            clamp_center_w = half;
        else if (c + half > dim - 9'd1)
            clamp_center_w = dim - 9'd1 - half;
        else
            clamp_center_w = c;
    endfunction

    function automatic [8:0] clamp_topleft_w(input [8:0] center, input [8:0] len, input [8:0] mem_len);
        if (center < (len >> 1))
            clamp_topleft_w = 9'd0;
        else if ((center - (len >> 1) + len) > mem_len)
            clamp_topleft_w = mem_len - len;
        else
            clamp_topleft_w = center - (len >> 1);
    endfunction

    logic [16:0] addr;
    always_comb begin
        case (write_cnt)
            4'd0: addr = (marker_y_r - 8'd1) * MEM_W + (marker_x_r - 9'd1);
            4'd1: addr = (marker_y_r - 8'd1) * MEM_W + (marker_x_r);
            4'd2: addr = (marker_y_r - 8'd1) * MEM_W + (marker_x_r + 9'd1);
            4'd3: addr = (marker_y_r) * MEM_W + (marker_x_r - 9'd1);
            4'd4: addr = (marker_y_r) * MEM_W + (marker_x_r);
            4'd5: addr = (marker_y_r) * MEM_W + (marker_x_r + 9'd1);
            4'd6: addr = (marker_y_r + 8'd1) * MEM_W + (marker_x_r - 9'd1);
            4'd7: addr = (marker_y_r + 8'd1) * MEM_W + (marker_x_r);
            default: addr = (marker_y_r + 8'd1) * MEM_W + (marker_x_r + 9'd1);
        endcase
    end

    logic [8:0] disp_size_r, n_disp_size_r;

    logic [1:0] size_r, n_size_r;
    logic [1:0] stk_id_r, n_stk_id_r;

    logic [5:0] dx_r, n_dx_r, dy_r, n_dy_r;

    logic [16:0] stk_waddr_r, n_stk_waddr_r;
    logic        stk_wait_r, n_stk_wait_r;

    logic [8:0] stk_top_x_r, n_stk_top_x_r, stk_top_y_r, n_stk_top_y_r;

    logic [11:0] stk_rgb;
    logic        stk_transparent;

    assign stk_rom_idx  = stk_id_r;
    assign stk_rom_size = size_r;
    assign stk_rom_x    = dx_r[4:0];
    assign stk_rom_y    = dy_r[4:0];
    assign stk_rgb         = stk_rom_rgb;
    assign stk_transparent = stk_rom_transparent;

    logic [3:0]  mo_dx_r, n_mo_dx_r, mo_dy_r, n_mo_dy_r;
    logic [16:0] mo_waddr_r, n_mo_waddr_r;

    logic [11:0] mo_color_r, n_mo_color_r;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state <= IDLE;
            mem_en_r <= 1'b0;
            mem_waddr_r <= 0;
            mem_wdata_r <= 0;
            mem_raddr_r <= 0;
            write_cnt <= 1'b0;
            marker_x_r <= 0;
            marker_y_r <= 0;
            disp_size_r <= 0;
            size_r      <= 0;
            stk_id_r    <= 0;
            dx_r <= 0; dy_r <= 0;
            stk_waddr_r <= 0;
            stk_wait_r  <= 0;
            stk_top_x_r <= 0; stk_top_y_r <= 0;
            mo_dx_r <= 0; mo_dy_r <= 0;
            mo_waddr_r  <= 0;
            mo_color_r  <= 0;
        end else begin
            c_state     <= n_state;
            mem_en_r    <= n_mem_en_r;
            mem_waddr_r <= n_mem_waddr_r;
            mem_wdata_r <= n_mem_wdata_r;
            mem_raddr_r <= n_mem_raddr_r;
            write_cnt   <= n_write_cnt;
            marker_x_r <= n_marker_x_r;
            marker_y_r <= n_marker_y_r;
            disp_size_r <= n_disp_size_r;
            size_r      <= n_size_r;
            stk_id_r    <= n_stk_id_r;
            dx_r <= n_dx_r; dy_r <= n_dy_r;
            stk_waddr_r <= n_stk_waddr_r;
            stk_wait_r  <= n_stk_wait_r;
            stk_top_x_r <= n_stk_top_x_r; stk_top_y_r <= n_stk_top_y_r;
            mo_dx_r <= n_mo_dx_r; mo_dy_r <= n_mo_dy_r;
            mo_waddr_r  <= n_mo_waddr_r;
            mo_color_r  <= n_mo_color_r;
        end
    end

    always_comb begin
        n_marker_y_r_c9 = 9'd0;
        n_state       = c_state;
        n_mem_en_r    = mem_en_r;
        n_mem_waddr_r = mem_waddr_r;
        n_mem_wdata_r = mem_wdata_r;
        n_mem_raddr_r = mem_raddr_r;
        n_write_cnt   = write_cnt;
        n_marker_x_r  = marker_x_r;
        n_marker_y_r  = marker_y_r;
        n_disp_size_r = disp_size_r;
        n_size_r      = size_r;
        n_stk_id_r    = stk_id_r;
        n_dx_r = dx_r; n_dy_r = dy_r;
        n_stk_waddr_r = stk_waddr_r;
        n_stk_wait_r  = stk_wait_r;
        n_stk_top_x_r = stk_top_x_r; n_stk_top_y_r = stk_top_y_r;
        n_mo_dx_r = mo_dx_r; n_mo_dy_r = mo_dy_r;
        n_mo_waddr_r = mo_waddr_r;
        n_mo_color_r = mo_color_r;

        case (c_state)
            IDLE: begin
                n_mem_en_r = 1'b0;

                if ((i_edit_mode == 2'b01) && (i_stk_place_p) && marker_valid) begin
                    n_state      = STK_PREP;
                    n_marker_x_r = marker_x;
                    n_marker_y_r = marker_y;

                    n_disp_size_r = 9'd4 << i_stk_size;
                    n_size_r      = i_stk_size;
                    n_stk_id_r    = i_stk_id;

                    n_dx_r = 0; n_dy_r = 0;
                    n_stk_wait_r = 1'b0;

                    n_stk_top_x_r = clamp_topleft_w(marker_x, n_disp_size_r, MEM_W[8:0]);
                    n_stk_top_y_r = clamp_topleft_w({1'b0, marker_y}, n_disp_size_r, MEM_H[8:0]);
                end else if ((i_edit_mode == 2'b10) && (i_edit_active) && marker_valid) begin
                    n_state    = DRAWING;

                    n_marker_x_r = clamp_center_w(marker_x, 9'd1, MEM_W[8:0]);
                    n_marker_y_r_c9 = clamp_center_w({1'b0, marker_y}, 9'd1, MEM_H[8:0]);
                    n_marker_y_r = n_marker_y_r_c9[7:0];
                end else if ((i_edit_mode == 2'b11) && (i_edit_active) && marker_valid) begin
                    n_state       = MO_PREP;

                    n_marker_x_r  = clamp_center_w(marker_x, MOSAIC_HALF, MEM_W[8:0]);
                    n_marker_y_r_c9 = clamp_center_w({1'b0, marker_y}, MOSAIC_HALF, MEM_H[8:0]);
                    n_marker_y_r  = n_marker_y_r_c9[7:0];

                    n_mo_dx_r = 0;
                    n_mo_dy_r = 0;

                end
            end

            STK_PREP: begin

                n_stk_waddr_r = stk_top_y_r * MEM_W + stk_top_x_r;
                n_state       = STICKER;
            end

            MO_PREP: begin

                n_mem_raddr_r = {1'b0, marker_y_r} * MEM_W + marker_x_r;

                n_mo_waddr_r = (17'(marker_y_r) - 17'(MOSAIC_HALF)) * MEM_W
                             + (17'(marker_x_r) - 17'(MOSAIC_HALF));
                n_state = WAIT_MOSAIC;
            end

            STICKER: begin
                if (!stk_wait_r) begin

                    n_mem_en_r   = 1'b0;
                    n_stk_wait_r = 1'b1;
                end else begin

                    if (!stk_transparent) begin
                        n_mem_en_r    = 1'b1;
                        n_mem_waddr_r = stk_waddr_r;
                        n_mem_wdata_r = stk_rgb;
                    end else begin
                        n_mem_en_r = 1'b0;
                    end

                    if (dx_r == disp_size_r - 6'd1) begin

                        n_dx_r    = 0;
                        if (dy_r == disp_size_r - 6'd1) begin

                            n_state      = IDLE;
                            n_stk_wait_r = 1'b0;
                        end else begin
                            n_dy_r        = dy_r + 6'd1;
                            n_stk_waddr_r = stk_waddr_r + (MEM_W - disp_size_r + 17'd1);
                            n_stk_wait_r  = 1'b0;
                        end
                    end else begin
                        n_dx_r        = dx_r + 6'd1;
                        n_stk_waddr_r = stk_waddr_r + 17'd1;
                        n_stk_wait_r  = 1'b0;
                    end
                end
            end

            DRAWING: begin
                n_mem_en_r = 1'b1;
                n_mem_waddr_r = addr;
                n_mem_wdata_r = draw_rgb;
                if (write_cnt == 4'd8) begin
                    n_write_cnt = 3'd0;
                    n_state = IDLE;
                end else begin
                    n_write_cnt = write_cnt + 1;
                end
            end
            WAIT_MOSAIC: begin
                n_state = MOSAIC;

            end
            MOSAIC: begin

                if (mo_dx_r == 4'd0 && mo_dy_r == 4'd0)
                    n_mo_color_r = mem_rdata;

                n_mem_en_r    = 1'b1;
                n_mem_waddr_r = mo_waddr_r;
                n_mem_wdata_r = (mo_dx_r == 4'd0 && mo_dy_r == 4'd0) ? mem_rdata : mo_color_r;

                if (mo_dx_r == MOSAIC_SIZE[3:0] - 4'd1) begin
                    n_mo_dx_r = 0;
                    if (mo_dy_r == MOSAIC_SIZE[3:0] - 4'd1) begin
                        n_state = IDLE;
                    end else begin
                        n_mo_dy_r    = mo_dy_r + 4'd1;
                        n_mo_waddr_r = mo_waddr_r + (MEM_W - MOSAIC_SIZE + 17'd1);
                    end
                end else begin
                    n_mo_dx_r    = mo_dx_r + 4'd1;
                    n_mo_waddr_r = mo_waddr_r + 17'd1;
                end
            end
        endcase
    end

endmodule
