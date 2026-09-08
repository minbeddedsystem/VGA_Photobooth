`timescale 1ns / 1ps

module edit_engine #(
    parameter MEM_W = 320,
    parameter MEM_H = 240
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        i_img_req_valid,
    output logic        o_img_req_ready,
    output logic        o_img_export_done,
    output logic        o_img_export_active,
    output logic        o_img_export_error,

    input  logic [9:0]  i_x_pixel,
    input  logic [9:0]  i_y_pixel,
    input  logic        i_data_en,

    input  logic [8:0]  i_marker_x,
    input  logic [7:0]  i_marker_y,
    input  logic        i_marker_valid,

    input  logic [16:0] i_addr,
    input  logic [11:0] i_rgb,
    input  logic        i_pixel_valid,

    output logic [11:0] o_pixel_data,
    output logic        o_pixel_valid,
    input  logic        i_pixel_ready,

    input  logic [1:0]  i_edit_mode,
    input  logic        i_edit_active,
    input  logic [1:0]  i_stk_id,
    input  logic [1:0]  i_stk_size,
    input  logic        i_stk_place_p,
    input  logic [2:0]  i_draw_color,

    input  logic         i_frame_sel
);

    wire [9:0] uart_x_pixel;
    wire [8:0] uart_y_pixel;
    wire       uart_valid;

    logic sending_r;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) sending_r <= 1'b0;
        else if (i_img_req_valid && !sending_r) sending_r <= 1'b1;
        else if (o_img_export_done) sending_r <= 1'b0;
    end
    wire sending = sending_r;
    assign o_img_export_active = sending_r;

    logic frame_sel_latched;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) frame_sel_latched <= 1'b0;
        else if (i_img_req_valid && !sending_r) frame_sel_latched <= i_frame_sel;
    end
    wire frame_sel_eff = sending_r ? frame_sel_latched : i_frame_sel;

    assign o_img_export_error = 1'b0;

    final_frame_sender U_IMAGE_EXPORT (
        .clk              (clk),
        .reset            (rst),
        .i_img_req_valid  (i_img_req_valid),
        .o_img_req_ready  (o_img_req_ready),
        .o_img_export_done(o_img_export_done),
        .o_x_pixel        (uart_x_pixel),
        .o_y_pixel        (uart_y_pixel),
        .i_pixel_ready    (i_pixel_ready),
        .o_pixel_valid    (uart_valid)
    );

    wire [9:0] mux_x = sending ? uart_x_pixel : i_x_pixel;
    wire [9:0] mux_y = sending ? {1'b0, uart_y_pixel} : i_y_pixel;

    wire [9:0] eff_x, eff_y;
    downscaler U_DOWNSCALER (
        .i_x_pixel(mux_x),
        .i_y_pixel(mux_y),
        .o_x_pixel(eff_x),
        .o_y_pixel(eff_y)
    );

    wire [9:0] marker_x_s = {1'b0, i_marker_x};
    wire [9:0] marker_y_s = {2'b00, i_marker_y};

    localparam int MARKER_TIMEOUT = 10_000_000;
    logic marker_present_r;
    logic [23:0] marker_age_r;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            marker_present_r <= 1'b0;
            marker_age_r     <= '0;
        end else if (i_marker_valid) begin
            marker_present_r <= 1'b1;
            marker_age_r     <= '0;
        end else if (i_edit_mode == 2'b00) begin
            marker_present_r <= 1'b0;
            marker_age_r     <= '0;
        end else if (marker_age_r == MARKER_TIMEOUT) begin
            marker_present_r <= 1'b0;
        end else begin
            marker_age_r <= marker_age_r + 1'b1;
        end
    end

    wire [16:0] disp_raddr;
    wire [11:0] disp_rdata;

    mem_addr_gen #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MEM_ADDR_GEN (
        .clk          (clk),
        .i_x_pixel    (eff_x),
        .i_y_pixel    (eff_y),
        .i_marker_x   (marker_x_s),
        .i_marker_y   (marker_y_s),
        .i_edit_mode  (i_edit_mode),
        .i_edit_active(i_edit_active),
        .o_mem_raddr  (disp_raddr)
    );

    wire        mw_we;
    wire [16:0] mw_waddr;
    wire [11:0] mw_wdata;
    wire [16:0] mw_raddr;
    wire [11:0] mw_rdata;

    wire [1:0]  mw_stk_idx;
    wire [1:0]  mw_stk_size;
    wire [4:0]  mw_stk_x, mw_stk_y;
    wire [11:0] mw_stk_rgb;
    wire        mw_stk_transparent;

    sticker_rom U_STICKER_ROM_WRITER (
        .clk        (clk),
        .idx        (mw_stk_idx),
        .size       (mw_stk_size),
        .x          (mw_stk_x),
        .y          (mw_stk_y),
        .rgb        (mw_stk_rgb),
        .transparent(mw_stk_transparent)
    );

    mem_writer #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MEM_WRITER (
        .clk           (clk),
        .reset         (rst),
        .i_edit_mode   (i_edit_mode),
        .i_edit_active (i_edit_active),
        .i_stk_id      (i_stk_id),
        .i_stk_size    (i_stk_size),
        .i_stk_place_p (i_stk_place_p),
        .i_draw_color  (i_draw_color),
        .marker_x      (i_marker_x),
        .marker_y      (i_marker_y),
        .marker_valid  (marker_present_r),
        .mem_en        (mw_we),
        .mem_waddr     (mw_waddr),
        .mem_wdata     (mw_wdata),
        .mem_raddr     (mw_raddr),
        .mem_rdata     (mw_rdata),
        .stk_rom_idx   (mw_stk_idx),
        .stk_rom_size  (mw_stk_size),
        .stk_rom_x     (mw_stk_x),
        .stk_rom_y     (mw_stk_y),
        .stk_rom_rgb   (mw_stk_rgb),
        .stk_rom_transparent(mw_stk_transparent)
    );

    wire [16:0] mem_a_addr  = i_pixel_valid ? i_addr  : (mw_we ? mw_waddr : mw_raddr);
    wire [11:0] mem_a_wdata = i_pixel_valid ? i_rgb   : mw_wdata;
    wire        mem_a_we    = i_pixel_valid ? 1'b1    : mw_we;
    wire [11:0] mem_rdata;

    memory #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MEMORY (
        .clk       (clk),
        .rst       (rst),
        .i_we      (mem_a_we),
        .i_addr    (mem_a_addr),
        .i_wdata   (mem_a_wdata),
        .o_rdata_a (mw_rdata),
        .i_raddr   (disp_raddr),
        .o_rdata_b (mem_rdata)
    );

    wire [11:0] composited;

    marker_overlay #(.MEM_W(MEM_W), .MEM_H(MEM_H)) U_MARKER_OVERLAY (
        .clk           (clk),
        .rst           (rst),
        .i_x_pixel     (eff_x),
        .i_y_pixel     (eff_y),
        .i_marker_x    (marker_x_s),
        .i_marker_y    (marker_y_s),
        .i_marker_valid(marker_present_r),
        .i_edit_mode   (i_edit_mode),
        .i_edit_active (i_edit_active),
        .i_stk_id      (i_stk_id),
        .i_stk_size    (i_stk_size),
        .i_stk_place_p (i_stk_place_p),
        .i_draw_color  (i_draw_color),
        .i_frame_sel   (frame_sel_eff),
        .i_mem_rdata   (mem_rdata),
        .o_pixel_data  (composited)
    );

    logic de_d1, de_d2, de_d3;
    always_ff @(posedge clk) begin
        de_d1 <= i_data_en;
        de_d2 <= de_d1;
        de_d3 <= de_d2;
    end

    assign o_pixel_data  = (sending || de_d3) ? composited : 12'h000;
    assign o_pixel_valid = sending ? uart_valid : de_d3;

endmodule
