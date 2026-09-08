`timescale 1ns / 1ps

module StrokeInterpolator #(
    parameter SEND_INTERVAL = 32,
    parameter INTERP_MAX_DX = 18,
    parameter INTERP_MAX_DY = 18
)(
    input  logic       clk,
    input  logic       reset,

    input  logic       draw_active,

    input  logic [8:0] i_marker_x,
    input  logic [7:0] i_marker_y,
    input  logic       i_marker_valid,
    input  logic       i_marker_present,

    output logic [8:0] o_marker_x,
    output logic [7:0] o_marker_y,
    output logic       o_marker_valid,
    output logic       o_marker_present,

    output logic       o_interp_busy
);

    logic       segment_busy;

    assign o_marker_present = i_marker_present;
    assign o_interp_busy    = segment_busy;

    function automatic [8:0] clamp_draw_x(input logic [8:0] x);
        begin
            if (x < 9'd1)
                clamp_draw_x = 9'd1;
            else if (x > 9'd318)
                clamp_draw_x = 9'd318;
            else
                clamp_draw_x = x;
        end
    endfunction

    function automatic [7:0] clamp_draw_y(input logic [7:0] y);
        begin
            if (y < 8'd1)
                clamp_draw_y = 8'd1;
            else if (y > 8'd238)
                clamp_draw_y = 8'd238;
            else
                clamp_draw_y = y;
        end
    endfunction

    logic [8:0] pending_x;
    logic [7:0] pending_y;
    logic       pending_valid;

    logic [8:0] prev_x;
    logic [7:0] prev_y;
    logic       have_prev;

    logic [8:0] line_x;
    logic [7:0] line_y;
    logic [8:0] target_x;
    logic [7:0] target_y;

    logic signed [10:0] dx_b;
    logic signed [10:0] dy_b;
    logic signed [10:0] sx_b;
    logic signed [10:0] sy_b;
    logic signed [11:0] err_b;

    logic [7:0] cooldown;

    logic [8:0] seg_dx;
    logic [7:0] seg_dy;
    logic       segment_connect_ok;

    always_comb begin
        if (pending_x >= prev_x)
            seg_dx = pending_x - prev_x;
        else
            seg_dx = prev_x - pending_x;

        if (pending_y >= prev_y)
            seg_dy = pending_y - prev_y;
        else
            seg_dy = prev_y - pending_y;

        segment_connect_ok =
            (seg_dx <= INTERP_MAX_DX) &&
            (seg_dy <= INTERP_MAX_DY);
    end

    logic [8:0] bres_next_x;
    logic [7:0] bres_next_y;
    logic signed [11:0] bres_next_err;
    logic signed [12:0] bres_e2;

    always_comb begin
        bres_next_x   = line_x;
        bres_next_y   = line_y;
        bres_next_err = err_b;
        bres_e2       = $signed(err_b) <<< 1;

        if (bres_e2 > -$signed(dy_b)) begin
            bres_next_err = bres_next_err - $signed(dy_b);

            if (sx_b > 0)
                bres_next_x = line_x + 1'b1;
            else
                bres_next_x = line_x - 1'b1;
        end

        if (bres_e2 < $signed(dx_b)) begin
            bres_next_err = bres_next_err + $signed(dx_b);

            if (sy_b > 0)
                bres_next_y = line_y + 1'b1;
            else
                bres_next_y = line_y - 1'b1;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            o_marker_x     <= 9'd0;
            o_marker_y     <= 8'd0;
            o_marker_valid <= 1'b0;

            pending_x      <= 9'd0;
            pending_y      <= 8'd0;
            pending_valid  <= 1'b0;

            prev_x         <= 9'd0;
            prev_y         <= 8'd0;
            have_prev      <= 1'b0;

            segment_busy   <= 1'b0;
            line_x         <= 9'd0;
            line_y         <= 8'd0;
            target_x       <= 9'd0;
            target_y       <= 8'd0;

            dx_b           <= '0;
            dy_b           <= '0;
            sx_b           <= '0;
            sy_b           <= '0;
            err_b          <= '0;

            cooldown       <= 8'd0;
        end
        else begin

            o_marker_valid <= 1'b0;

            if (!draw_active) begin
                have_prev     <= 1'b0;
                segment_busy  <= 1'b0;
                pending_valid <= 1'b0;
                cooldown      <= 8'd0;

                if (i_marker_valid) begin
                    o_marker_x     <= i_marker_x;
                    o_marker_y     <= i_marker_y;
                    o_marker_valid <= 1'b1;
                end
            end

            else if (!i_marker_present) begin
                have_prev     <= 1'b0;
                segment_busy  <= 1'b0;
                pending_valid <= 1'b0;
                cooldown      <= 8'd0;
            end

            else begin

                if (cooldown != 0)
                    cooldown <= cooldown - 1'b1;

                if (segment_busy) begin
                    if (cooldown == 0) begin
                        o_marker_x     <= bres_next_x;
                        o_marker_y     <= bres_next_y;
                        o_marker_valid <= 1'b1;

                        line_x <= bres_next_x;
                        line_y <= bres_next_y;
                        err_b  <= bres_next_err;

                        if (SEND_INTERVAL > 1)
                            cooldown <= SEND_INTERVAL - 1;
                        else
                            cooldown <= 0;

                        if ((bres_next_x == target_x) &&
                            (bres_next_y == target_y)) begin
                            prev_x       <= target_x;
                            prev_y       <= target_y;
                            have_prev    <= 1'b1;
                            segment_busy <= 1'b0;
                        end
                    end
                end

                else if ((cooldown == 0) && pending_valid) begin
                    pending_valid <= 1'b0;

                    if (!have_prev) begin
                        o_marker_x     <= pending_x;
                        o_marker_y     <= pending_y;
                        o_marker_valid <= 1'b1;

                        prev_x      <= pending_x;
                        prev_y      <= pending_y;
                        have_prev   <= 1'b1;

                        if (SEND_INTERVAL > 1)
                            cooldown <= SEND_INTERVAL - 1;
                        else
                            cooldown <= 0;
                    end

                    else if ((pending_x == prev_x) &&
                             (pending_y == prev_y)) begin
                        prev_x <= pending_x;
                        prev_y <= pending_y;
                    end

                    else if (segment_connect_ok) begin
                        line_x   <= prev_x;
                        line_y   <= prev_y;
                        target_x <= pending_x;
                        target_y <= pending_y;

                        dx_b <= $signed({1'b0, seg_dx});
                        dy_b <= $signed({2'b00, seg_dy});

                        if (pending_x >= prev_x)
                            sx_b <= 11'sd1;
                        else
                            sx_b <= -11'sd1;

                        if (pending_y >= prev_y)
                            sy_b <= 11'sd1;
                        else
                            sy_b <= -11'sd1;

                        err_b <= $signed({2'b00, seg_dx})
                               - $signed({3'b000, seg_dy});

                        segment_busy <= 1'b1;
                    end

                    else begin
                        o_marker_x     <= pending_x;
                        o_marker_y     <= pending_y;
                        o_marker_valid <= 1'b1;

                        prev_x      <= pending_x;
                        prev_y      <= pending_y;
                        have_prev   <= 1'b1;

                        if (SEND_INTERVAL > 1)
                            cooldown <= SEND_INTERVAL - 1;
                        else
                            cooldown <= 0;
                    end
                end

                if (i_marker_valid) begin
                    pending_x     <= clamp_draw_x(i_marker_x);
                    pending_y     <= clamp_draw_y(i_marker_y);
                    pending_valid <= 1'b1;
                end
            end
        end
    end

endmodule
