`timescale 1ns / 1ps

module MarkerDetector_final #(
    parameter IMG_W = 320,
    parameter IMG_H = 240,

    parameter CELL_SHIFT = 4,
    parameter ACQUIRE_MIN_TARGET = 16,

    parameter SEARCH_RADIUS = 32,
    parameter TRACK_MIN_RUN = 4,
    parameter TRACK_MIN_LINES = 3,

    parameter MAX_STEP_X = 28,
    parameter MAX_STEP_Y = 24,

    parameter LUT_MEM_FILE = "marker_lut.mem"
)(
    input  logic        pclk,
    input  logic        reset,

    input  logic [9:0]  i_x_pixel,
    input  logic [8:0]  i_y_pixel,
    input  logic [15:0] i_w_data,
    input  logic        i_marker_track_en,
    input  logic        w_en,

    output logic [9:0]  o_marker_x,
    output logic [8:0]  o_marker_y,
    output logic        o_marker_valid,
    output logic        o_marker_present
);

    logic [4:0] r;
    logic [5:0] g;
    logic [4:0] b;

    logic [9:0] lut_addr;
    logic       lut_hit;
    logic [4:0] g5;
    logic       lime_loose;
    logic       is_target;
    logic       is_red;

    assign r = i_w_data[15:11];
    assign g = i_w_data[10:5];
    assign b = i_w_data[4:0];

    assign lut_addr = {
        r[4:2],
        g[5:2],
        b[4:2]
    };

    (* rom_style = "distributed" *) logic [0:0] target_lut [0:1023];

    initial begin
        $readmemb(LUT_MEM_FILE, target_lut);
    end

    assign lut_hit = target_lut[lut_addr];

    assign g5 = g[5:1];

    assign lime_loose =
        (g5 >= 5'd6) &&
        ({1'b0, g5} + 6'd10 >= {1'b0, r}) &&
        ({1'b0, g5} >= {1'b0, b} + 6'd2);

    assign is_target = lime_loose;

    assign is_red = is_target;

    localparam CELL_SIZE = (1 << CELL_SHIFT);
    localparam GRID_W = (IMG_W + CELL_SIZE - 1) >> CELL_SHIFT;
    localparam GRID_H = (IMG_H + CELL_SIZE - 1) >> CELL_SHIFT;
    localparam NUM_CELLS = GRID_W * GRID_H;
    localparam CELL_CNT_W = (CELL_SHIFT*2 + 1);

    logic [CELL_CNT_W-1:0] cell_count [0:NUM_CELLS-1];
    logic [CELL_CNT_W-1:0] acquire_best_count;
    logic [9:0] acquire_best_cx;
    logic [8:0] acquire_best_cy;

    integer cell_idx;
    integer clear_i;

    always_comb begin
        cell_idx = ((i_y_pixel >> CELL_SHIFT) * GRID_W) +
                   (i_x_pixel >> CELL_SHIFT);
    end

    typedef enum logic {
        ACQUIRE,
        TRACK
    } track_state_t;

    track_state_t state;

    logic [9:0] prev_x;
    logic [8:0] prev_y;

    logic in_search_window;

    always_comb begin
        in_search_window = 1'b0;

        if ((i_x_pixel + SEARCH_RADIUS >= prev_x) &&
            (i_x_pixel <= prev_x + SEARCH_RADIUS) &&
            (i_y_pixel + SEARCH_RADIUS >= prev_y) &&
            (i_y_pixel <= prev_y + SEARCH_RADIUS)) begin
            in_search_window = 1'b1;
        end
    end

    logic [9:0] run_start_x;
    logic [9:0] run_len;

    logic [9:0] line_best_len;
    logic [9:0] line_best_start_x;
    logic [9:0] line_best_end_x;

    logic [8:0] track_first_y;
    logic [8:0] track_last_y;
    logic [8:0] track_line_count;
    logic       track_found_line;

    logic [9:0] track_min_x;
    logic [9:0] track_max_x;

    logic frame_had_output;

    logic [9:0] blob_center_x;
    logic [8:0] blob_center_y;

    logic [9:0] smooth_x;
    logic [8:0] smooth_y;
    logic       smooth_valid;

    logic [9:0] delta_x;
    logic [8:0] delta_y;
    logic [9:0] motion_max;
    logic       candidate_ok;

    logic [11:0] smooth_x_sum;
    logic [10:0] smooth_y_sum;
    logic [9:0]  smooth_next_x;
    logic [8:0]  smooth_next_y;

    always_comb begin
        blob_center_x = (track_min_x + track_max_x) >> 1;
        blob_center_y = (track_first_y + track_last_y) >> 1;

        if (blob_center_x >= prev_x)
            delta_x = blob_center_x - prev_x;
        else
            delta_x = prev_x - blob_center_x;

        if (blob_center_y >= prev_y)
            delta_y = blob_center_y - prev_y;
        else
            delta_y = prev_y - blob_center_y;

        if (delta_x >= {1'b0, delta_y})
            motion_max = delta_x;
        else
            motion_max = {1'b0, delta_y};

        candidate_ok =
            (delta_x <= MAX_STEP_X) &&
            (delta_y <= MAX_STEP_Y);

        smooth_x_sum  = 12'd0;
        smooth_y_sum  = 11'd0;
        smooth_next_x = blob_center_x;
        smooth_next_y = blob_center_y;

        if (motion_max <= 10'd2) begin
            smooth_x_sum  = ({2'b00, smooth_x} << 1)
                          +  {2'b00, smooth_x}
                          +  {2'b00, blob_center_x};

            smooth_y_sum  = ({2'b00, smooth_y} << 1)
                          +  {2'b00, smooth_y}
                          +  {2'b00, blob_center_y};

            smooth_next_x = smooth_x_sum >> 2;
            smooth_next_y = smooth_y_sum >> 2;
        end
        else if (motion_max <= 10'd6) begin
            smooth_next_x = ({1'b0, smooth_x} + {1'b0, blob_center_x}) >> 1;
            smooth_next_y = ({1'b0, smooth_y} + {1'b0, blob_center_y}) >> 1;
        end
        else begin
            smooth_x_sum  = {2'b00, smooth_x}
                          + ({2'b00, blob_center_x} << 1)
                          +  {2'b00, blob_center_x};

            smooth_y_sum  = {2'b00, smooth_y}
                          + ({2'b00, blob_center_y} << 1)
                          +  {2'b00, blob_center_y};

            smooth_next_x = smooth_x_sum >> 2;
            smooth_next_y = smooth_y_sum >> 2;
        end
    end

    always_ff @(posedge pclk or posedge reset) begin
        if (reset) begin
            state <= ACQUIRE;

            o_marker_x       <= 0;
            o_marker_y       <= 0;
            o_marker_valid   <= 0;
            o_marker_present <= 0;

            prev_x <= 0;
            prev_y <= 0;

            smooth_x     <= 0;
            smooth_y     <= 0;
            smooth_valid <= 1'b0;

            acquire_best_count <= 0;
            acquire_best_cx    <= 0;
            acquire_best_cy    <= 0;

            run_start_x       <= 0;
            run_len           <= 0;
            line_best_len     <= 0;
            line_best_start_x <= 0;
            line_best_end_x   <= 0;

            track_first_y    <= 0;
            track_last_y     <= 0;
            track_line_count <= 0;
            track_found_line <= 0;
            track_min_x      <= 0;
            track_max_x      <= 0;
            frame_had_output <= 0;

            for (clear_i = 0; clear_i < NUM_CELLS; clear_i = clear_i + 1)
                cell_count[clear_i] <= 0;
        end

        else if (!i_marker_track_en) begin
            state <= ACQUIRE;

            o_marker_valid   <= 0;
            o_marker_present <= 0;

            smooth_x     <= 0;
            smooth_y     <= 0;
            smooth_valid <= 1'b0;

            acquire_best_count <= 0;
            acquire_best_cx    <= 0;
            acquire_best_cy    <= 0;

            run_start_x       <= 0;
            run_len           <= 0;
            line_best_len     <= 0;
            line_best_start_x <= 0;
            line_best_end_x   <= 0;

            track_first_y    <= 0;
            track_last_y     <= 0;
            track_line_count <= 0;
            track_found_line <= 0;
            track_min_x      <= 0;
            track_max_x      <= 0;
            frame_had_output <= 0;

            for (clear_i = 0; clear_i < NUM_CELLS; clear_i = clear_i + 1)
                cell_count[clear_i] <= 0;
        end

        else begin
            o_marker_valid <= 0;

            if (state == ACQUIRE) begin

                if (w_en && is_red) begin
                    cell_count[cell_idx] <= cell_count[cell_idx] + 1'b1;

                    if ((cell_count[cell_idx] + 1'b1) > acquire_best_count) begin
                        acquire_best_count <= cell_count[cell_idx] + 1'b1;
                        acquire_best_cx <= ((i_x_pixel >> CELL_SHIFT) << CELL_SHIFT)
                                           + (CELL_SIZE >> 1);
                        acquire_best_cy <= ((i_y_pixel >> CELL_SHIFT) << CELL_SHIFT)
                                           + (CELL_SIZE >> 1);
                    end
                end

                if (w_en &&
                    (i_x_pixel == IMG_W-1) &&
                    (i_y_pixel == IMG_H-1)) begin

                    if (acquire_best_count >= ACQUIRE_MIN_TARGET) begin
                        prev_x <= acquire_best_cx;
                        prev_y <= acquire_best_cy;
                        state  <= TRACK;
                    end

                    o_marker_present <= 0;

                    acquire_best_count <= 0;
                    acquire_best_cx    <= 0;
                    acquire_best_cy    <= 0;

                    for (clear_i = 0; clear_i < NUM_CELLS; clear_i = clear_i + 1)
                        cell_count[clear_i] <= 0;
                end
            end

            else begin

                if (w_en && in_search_window && is_red) begin
                    if (run_len == 0)
                        run_start_x <= i_x_pixel;

                    run_len <= run_len + 1'b1;
                end
                else if (w_en) begin
                    if ((run_len >= TRACK_MIN_RUN) &&
                        (run_len > line_best_len)) begin
                        line_best_len     <= run_len;
                        line_best_start_x <= run_start_x;
                        line_best_end_x   <= run_start_x + run_len - 1'b1;
                    end

                    run_len <= 0;
                end

                if (w_en && (i_x_pixel == IMG_W-1)) begin

                    if (line_best_len >= TRACK_MIN_RUN) begin

                        if (track_found_line &&
                            (i_y_pixel == (track_last_y + 1'b1))) begin

                            track_last_y     <= i_y_pixel;
                            track_line_count <= track_line_count + 1'b1;

                            if (line_best_start_x < track_min_x)
                                track_min_x <= line_best_start_x;

                            if (line_best_end_x > track_max_x)
                                track_max_x <= line_best_end_x;
                        end

                        else begin

                            if (track_found_line &&
                                (track_line_count >= TRACK_MIN_LINES)) begin
                                if (candidate_ok) begin
                                    prev_x <= blob_center_x;
                                    prev_y <= blob_center_y;

                                    if (!smooth_valid) begin
                                        smooth_x       <= blob_center_x;
                                        smooth_y       <= blob_center_y;
                                        o_marker_x     <= blob_center_x;
                                        o_marker_y     <= blob_center_y;
                                        smooth_valid   <= 1'b1;
                                    end
                                    else begin
                                        smooth_x       <= smooth_next_x;
                                        smooth_y       <= smooth_next_y;
                                        o_marker_x     <= smooth_next_x;
                                        o_marker_y     <= smooth_next_y;
                                    end

                                    o_marker_present <= 1'b1;
                                    o_marker_valid   <= 1'b1;
                                    frame_had_output <= 1'b1;
                                end

                            end

                            track_first_y    <= i_y_pixel;
                            track_last_y     <= i_y_pixel;
                            track_line_count <= 1;
                            track_found_line <= 1'b1;
                            track_min_x      <= line_best_start_x;
                            track_max_x      <= line_best_end_x;
                        end
                    end

                    else begin
                        if (track_found_line) begin

                            if (track_line_count >= TRACK_MIN_LINES) begin
                                if (candidate_ok) begin
                                    prev_x <= blob_center_x;
                                    prev_y <= blob_center_y;

                                    if (!smooth_valid) begin
                                        smooth_x       <= blob_center_x;
                                        smooth_y       <= blob_center_y;
                                        o_marker_x     <= blob_center_x;
                                        o_marker_y     <= blob_center_y;
                                        smooth_valid   <= 1'b1;
                                    end
                                    else begin
                                        smooth_x       <= smooth_next_x;
                                        smooth_y       <= smooth_next_y;
                                        o_marker_x     <= smooth_next_x;
                                        o_marker_y     <= smooth_next_y;
                                    end

                                    o_marker_present <= 1'b1;
                                    o_marker_valid   <= 1'b1;
                                    frame_had_output <= 1'b1;
                                end

                            end

                            track_found_line <= 1'b0;
                            track_line_count <= 0;
                            track_min_x      <= 0;
                            track_max_x      <= 0;
                        end
                    end

                    run_len           <= 0;
                    line_best_len     <= 0;
                    line_best_start_x <= 0;
                    line_best_end_x   <= 0;
                end

                if (w_en &&
                    (i_x_pixel == IMG_W-1) &&
                    (i_y_pixel == IMG_H-1)) begin

                    if (track_found_line &&
                        (track_line_count >= TRACK_MIN_LINES)) begin
                        if (candidate_ok) begin
                            prev_x <= blob_center_x;
                            prev_y <= blob_center_y;

                            if (!smooth_valid) begin
                                smooth_x       <= blob_center_x;
                                smooth_y       <= blob_center_y;
                                o_marker_x     <= blob_center_x;
                                o_marker_y     <= blob_center_y;
                                smooth_valid   <= 1'b1;
                            end
                            else begin
                                smooth_x       <= smooth_next_x;
                                smooth_y       <= smooth_next_y;
                                o_marker_x     <= smooth_next_x;
                                o_marker_y     <= smooth_next_y;
                            end

                            o_marker_present <= 1'b1;
                            o_marker_valid   <= 1'b1;
                        end
                    end

                    else if (!frame_had_output) begin
                        o_marker_present <= 1'b0;
                        state <= ACQUIRE;

                        smooth_valid <= 1'b0;

                        acquire_best_count <= 0;
                        acquire_best_cx    <= 0;
                        acquire_best_cy    <= 0;

                        for (clear_i = 0; clear_i < NUM_CELLS; clear_i = clear_i + 1)
                            cell_count[clear_i] <= 0;
                    end

                    frame_had_output <= 1'b0;

                    run_start_x       <= 0;
                    run_len           <= 0;
                    line_best_len     <= 0;
                    line_best_start_x <= 0;
                    line_best_end_x   <= 0;

                    track_first_y    <= 0;
                    track_last_y     <= 0;
                    track_line_count <= 0;
                    track_found_line <= 0;
                    track_min_x      <= 0;
                    track_max_x      <= 0;
                end
            end
        end
    end

endmodule
