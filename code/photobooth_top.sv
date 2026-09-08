`timescale 1ns / 1ps

module photobooth_top (
    input  logic        clk,
    input  logic        btnC, btnU, btnD, btnL, btnR,
    input  logic [1:0]  sw,
    input  logic        ext_btn_n,
    output logic [15:0] led,

    output logic        cam_xclk,
    input  logic        cam_pclk,
    input  logic        cam_href,
    input  logic        cam_vsync,
    input  logic [7:0]  cam_data,
    output logic        cam_scl,
    inout  wire         cam_sda,

    output logic [3:0]  vgaRed, vgaGreen, vgaBlue,
    output logic        Hsync, Vsync,

    output logic        uart_tx
);

    wire rst_global;
    wire rst_pclk;

    wire        sc_cam_stream_en;
    wire        sc_marker_track_en;
    wire        sc_cap_req_valid;
    wire [2:0]  sc_filter_sel;
    wire [1:0]  sc_edit_mode;
    wire        sc_edit_active;
    wire [1:0]  sc_stk_id;
    wire [1:0]  sc_stk_size;
    wire        sc_stk_place_p;
    wire [2:0]  sc_drw_color;
    wire        sc_frame_sel;
    wire        sc_img_req_valid;
    wire        sc_send_valid;
    wire [31:0] sc_status_data;

    logic sc_cam_stream_en_r;
    logic sc_marker_track_en_r;

    always_ff @(posedge clk or posedge rst_global) begin
        if (rst_global) begin
            sc_cam_stream_en_r   <= 1'b0;
            sc_marker_track_en_r <= 1'b0;
        end else begin
            sc_cam_stream_en_r   <= sc_cam_stream_en;
            sc_marker_track_en_r <= sc_marker_track_en;
        end
    end

    wire       cam_ready;
    wire       cap_req_ready;
    wire       cap_done;
    wire [2:0] cap_count;
    wire       cap_all_done;
    wire       edit_img_req_ready;
    wire       edit_img_export_done;
    wire       edit_img_export_active;
    wire       uart_status_ready;
    wire       uart_send_done;

    wire        cam_w_en;
    wire [15:0] cam_w_data;
    wire [8:0]  cam_pixel_x;
    wire [7:0]  cam_pixel_y;

    (* ASYNC_REG = "TRUE" *) logic trk_en_ff1, trk_en_ff2;
    (* ASYNC_REG = "TRUE" *) logic stream_en_ff1, stream_en_ff2;

    always_ff @(posedge cam_pclk or posedge rst_pclk) begin
        if (rst_pclk)
            {trk_en_ff2, trk_en_ff1} <= 2'b00;
        else
            {trk_en_ff2, trk_en_ff1} <= {trk_en_ff1, sc_marker_track_en_r};
    end

    always_ff @(posedge cam_pclk or posedge rst_pclk) begin
        if (rst_pclk)
            {stream_en_ff2, stream_en_ff1} <= 2'b00;
        else
            {stream_en_ff2, stream_en_ff1} <= {stream_en_ff1, sc_cam_stream_en_r};
    end

    reset_sync U_RST_PCLK (
        .clk       (cam_pclk),
        .i_rst_raw (rst_global),
        .o_rst     (rst_pclk)
    );

    system_controller_top U_SC (
        .clk               (clk),
        .btnC              (btnC),
        .btnU              (btnU),
        .btnD              (btnD),
        .btnL              (btnL),
        .btnR              (btnR),
        .sw_tool_raw       (sw[0]),
        .sw_frame_raw      (sw[1]),
        .ext_btn_n         (ext_btn_n),
        .led               (led),
        .o_rst_global      (rst_global),
        .i_cam_ready       (cam_ready),
        .o_cam_stream_en   (sc_cam_stream_en),
        .o_marker_track_en (sc_marker_track_en),
        .i_cap_req_ready   (cap_req_ready),
        .i_cap_done        (cap_done),
        .i_capture_count   (cap_count),
        .i_all_done        (cap_all_done),
        .o_cap_req_valid   (sc_cap_req_valid),
        .o_filter_sel      (sc_filter_sel),
        .o_edit_mode       (sc_edit_mode),
        .o_edit_active     (sc_edit_active),
        .o_stk_id          (sc_stk_id),
        .o_stk_size        (sc_stk_size),
        .o_stk_place_p     (sc_stk_place_p),
        .o_drw_color       (sc_drw_color),
        .o_frame_sel       (sc_frame_sel),
        .i_img_req_ready   (edit_img_req_ready),
        .i_img_export_done (edit_img_export_done),
        .o_img_req_valid   (sc_img_req_valid),
        .i_send_ready      (uart_status_ready),
        .i_send_done       (uart_send_done),
        .o_send_valid      (sc_send_valid),
        .o_status_data     (sc_status_data)
    );

    Cam_IF #(
        .IMG_W (320),
        .IMG_H (240),
        .DW    (16)
    ) U_CAM (
        .clk             (clk),
        .reset           (rst_global),
        .reset_pclk      (rst_pclk),
        .i_cam_stream_en (stream_en_ff2),
        .o_cam_ready     (cam_ready),
        .pclk            (cam_pclk),
        .xclk            (cam_xclk),
        .cam_href        (cam_href),
        .cam_vsync       (cam_vsync),
        .cam_data        (cam_data),
        .scl             (cam_scl),
        .sda             (cam_sda),
        .w_en            (cam_w_en),
        .w_data          (cam_w_data),
        .pixel_x         (cam_pixel_x),
        .pixel_y         (cam_pixel_y)
    );

    wire [9:0] marker_cam_x = {1'b0, cam_pixel_x};
    wire [8:0] marker_cam_y = {1'b0, cam_pixel_y};

    wire [9:0] det_x;
    wire [8:0] det_y;
    wire       det_valid;
    wire       det_present;

    MarkerDetector_final #(
        .IMG_W        (320),
        .IMG_H        (240),
        .LUT_MEM_FILE ("marker_lut.mem")
    ) U_MARKER (
        .pclk              (cam_pclk),
        .reset             (rst_pclk),
        .i_x_pixel         (marker_cam_x),
        .i_y_pixel         (marker_cam_y),
        .i_w_data          (cam_w_data),
        .i_marker_track_en (trk_en_ff2),
        .w_en              (cam_w_en),
        .o_marker_x        (det_x),
        .o_marker_y        (det_y),
        .o_marker_valid    (det_valid),
        .o_marker_present  (det_present)
    );

    logic [8:0] cdc_x_hold;
    logic [7:0] cdc_y_hold;
    logic       cdc_event_toggle;

    always_ff @(posedge cam_pclk or posedge rst_pclk) begin
        if (rst_pclk) begin
            cdc_x_hold       <= 9'd0;
            cdc_y_hold       <= 8'd0;
            cdc_event_toggle <= 1'b0;
        end
        else if (det_valid && det_present) begin

            cdc_x_hold       <= det_x[8:0];
            cdc_y_hold       <= det_y[7:0];
            cdc_event_toggle <= ~cdc_event_toggle;
        end
    end

    (* ASYNC_REG = "TRUE" *) logic event_ff1, event_ff2;
    logic event_ff2_d;

    (* ASYNC_REG = "TRUE" *) logic present_ff1, present_ff2;

    logic [8:0] raw_marker_x;
    logic [7:0] raw_marker_y;
    logic       raw_marker_valid;

    always_ff @(posedge clk or posedge rst_global) begin
        if (rst_global) begin
            event_ff1        <= 1'b0;
            event_ff2        <= 1'b0;
            event_ff2_d      <= 1'b0;

            present_ff1      <= 1'b0;
            present_ff2      <= 1'b0;

            raw_marker_x     <= 9'd0;
            raw_marker_y     <= 8'd0;
            raw_marker_valid <= 1'b0;
        end
        else begin
            event_ff1   <= cdc_event_toggle;
            event_ff2   <= event_ff1;
            event_ff2_d <= event_ff2;

            present_ff1 <= det_present;
            present_ff2 <= present_ff1;

            raw_marker_valid <= 1'b0;

            if (event_ff2 != event_ff2_d) begin
                raw_marker_x     <= cdc_x_hold;
                raw_marker_y     <= cdc_y_hold;
                raw_marker_valid <= 1'b1;
            end
        end
    end

    wire [8:0] stroke_marker_x;
    wire [7:0] stroke_marker_y;
    wire       stroke_marker_valid;

    StrokeInterpolator #(
        .SEND_INTERVAL (32),
        .INTERP_MAX_DX (18),
        .INTERP_MAX_DY (18)
    ) U_STROKE (
        .clk              (clk),
        .reset            (rst_global),
        .draw_active      (sc_edit_mode[1]),
        .i_marker_x       (raw_marker_x),
        .i_marker_y       (raw_marker_y),
        .i_marker_valid   (raw_marker_valid),
        .i_marker_present (present_ff2),
        .o_marker_x       (stroke_marker_x),
        .o_marker_y       (stroke_marker_y),
        .o_marker_valid   (stroke_marker_valid),
        .o_marker_present (),
        .o_interp_busy    ()
    );

    wire [32:0] cam_fifo_wdata = {cam_pixel_y[7:0], cam_pixel_x[8:0], cam_w_data[15:0]};
    wire [32:0] cam_fifo_rdata;
    wire        cam_fifo_empty;
    wire        cam_fifo_rd_en;

    wire        cap_pixel_valid;
    wire [15:0] cap_pixel_data;
    wire [8:0]  cap_x_pixel;
    wire [7:0]  cap_y_pixel;

    async_fifo #(
        .DATA_WIDTH (33),
        .ADDR_WIDTH (4)
    ) U_CAM_FIFO (
        .wr_clk  (cam_pclk),
        .wr_rst  (rst_pclk),
        .wr_en   (cam_w_en),
        .wr_data (cam_fifo_wdata),
        .wr_full (),
        .rd_clk  (clk),
        .rd_rst  (rst_global),
        .rd_en   (cam_fifo_rd_en),
        .rd_data (cam_fifo_rdata),
        .rd_empty(cam_fifo_empty)
    );

    assign cam_fifo_rd_en  = ~cam_fifo_empty;
    assign cap_pixel_valid = cam_fifo_rd_en;
    assign cap_pixel_data  = cam_fifo_rdata[15:0];
    assign cap_x_pixel     = cam_fifo_rdata[24:16];
    assign cap_y_pixel     = cam_fifo_rdata[32:25];

    wire        capture_wr_en;
    wire [16:0] capture_wr_addr;
    wire [11:0] capture_wr_data;

    capture_top U_CAPTURE (
        .clk             (clk),
        .rst             (rst_global),
        .i_cap_req_valid (sc_cap_req_valid),
        .i_filter_sel    (sc_filter_sel),
        .i_x_pixel       (cap_x_pixel),
        .i_y_pixel       (cap_y_pixel),
        .i_pixel_data    (cap_pixel_data),
        .i_pixel_valid   (cap_pixel_valid),
        .o_wr_en         (capture_wr_en),
        .o_wr_addr       (capture_wr_addr),
        .o_wr_data       (capture_wr_data),
        .o_cap_done      (cap_done),
        .o_cap_count     (cap_count),
        .o_cap_req_ready (cap_req_ready),
        .o_all_done      (cap_all_done)
    );

    wire       vga_h_sync;
    wire       vga_v_sync;
    wire [9:0] vga_x_pixel;
    wire [9:0] vga_y_pixel;
    wire       vga_data_en;

    vga_controller U_VGA (
        .clk     (clk),
        .reset   (rst_global),
        .h_sync  (vga_h_sync),
        .v_sync  (vga_v_sync),
        .x_pixel (vga_x_pixel),
        .y_pixel (vga_y_pixel),
        .de      (vga_data_en)
    );

    wire [11:0] edit_pixel_data;
    wire        edit_pixel_valid;
    wire        uart_pixel_ready;

    edit_engine U_EDIT (
        .clk                (clk),
        .rst                (rst_global),
        .i_img_req_valid    (sc_img_req_valid),
        .o_img_req_ready    (edit_img_req_ready),
        .o_img_export_done  (edit_img_export_done),
        .o_img_export_active(edit_img_export_active),
        .o_img_export_error (),
        .i_x_pixel          (vga_x_pixel),
        .i_y_pixel          (vga_y_pixel),
        .i_data_en          (vga_data_en),
        .i_marker_x         (stroke_marker_x),
        .i_marker_y         (stroke_marker_y),
        .i_marker_valid     (stroke_marker_valid),
        .i_addr             (capture_wr_addr),
        .i_rgb              (capture_wr_data),
        .i_pixel_valid      (capture_wr_en),
        .o_pixel_data       (edit_pixel_data),
        .o_pixel_valid      (edit_pixel_valid),
        .i_pixel_ready      (uart_pixel_ready),
        .i_edit_mode        (sc_edit_mode),
        .i_edit_active      (sc_edit_active),
        .i_stk_id           (sc_stk_id),
        .i_stk_size         (sc_stk_size),
        .i_stk_place_p      (sc_stk_place_p),
        .i_draw_color       (sc_drw_color),
        .i_frame_sel        (sc_frame_sel)
    );

    UART_Interface_Top U_UART (
        .clk            (clk),
        .rst            (rst_global),
        .i_status_data  (sc_status_data),
        .i_status_valid (sc_send_valid),
        .o_status_ready (uart_status_ready),
        .o_send_done    (uart_send_done),
        .i_pixel_data   (edit_pixel_data),
        .i_pixel_valid  (edit_pixel_valid),
        .o_pixel_ready  (uart_pixel_ready),
        .o_uart_tx      (uart_tx)
    );

    assign vgaRed   = edit_img_export_active ? 4'h0 : edit_pixel_data[11:8];
    assign vgaGreen = edit_img_export_active ? 4'h0 : edit_pixel_data[7:4];
    assign vgaBlue  = edit_img_export_active ? 4'h0 : edit_pixel_data[3:0];
    assign Hsync    = vga_h_sync;
    assign Vsync    = vga_v_sync;

endmodule
