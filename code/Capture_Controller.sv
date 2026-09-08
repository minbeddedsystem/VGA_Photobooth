
`timescale 1ns / 1ps

module Capture_Controller #(
    parameter WIDTH  = $clog2(160) - 1,
    parameter HEIGHT = $clog2(120) - 1
) (

    input logic clk,
    input logic rst,

    input logic            i_pixel_valid,
    input logic [    11:0] i_pixel_data,
    input logic [ WIDTH:0] i_x_pixel,
    input logic [HEIGHT:0] i_y_pixel,

    input logic i_cap_req_valid,

    output logic        o_wr_en,
    output logic [16:0] o_wr_addr,
    output logic [11:0] o_wr_data,

    output logic       o_cap_done,
    output logic [2:0] o_cap_count,
    output logic       o_cap_req_ready,
    output logic       o_all_done
);

    logic w_frame_end;
    assign w_frame_end = i_pixel_valid && (i_x_pixel == 8'd159) && (i_y_pixel == 7'd119);

    logic r_trig_pending;
    logic r_all_done;
    logic [2:0] r_cap_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_trig_pending <= 1'b0;
        end else if (i_cap_req_valid && !r_all_done) begin
            r_trig_pending <= 1'b1;
        end else if (w_frame_end && r_trig_pending) begin
            r_trig_pending <= 1'b0;
        end
    end

    logic w_advance;
    assign w_advance = w_frame_end && r_trig_pending && !r_all_done;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_cap_count <= 3'd0;
            r_all_done  <= 1'b0;
        end else if (w_advance) begin
            if (r_cap_count == 3'd3) r_all_done  <= 1'b1;
            else                     r_cap_count <= r_cap_count + 3'd1;
        end
    end

    always_comb begin
        o_wr_en = i_pixel_valid && !r_all_done;
        case (r_cap_count)
            3'd0:    o_wr_addr = i_y_pixel * 320 + i_x_pixel;
            3'd1:    o_wr_addr = i_y_pixel * 320 + (i_x_pixel + 160);
            3'd2:    o_wr_addr = (i_y_pixel + 120) * 320 + i_x_pixel;
            3'd3:    o_wr_addr = (i_y_pixel + 120) * 320 + (i_x_pixel + 160);
            default: o_wr_addr = 17'd0;
        endcase
        o_wr_data = i_pixel_data;
    end

    assign o_cap_done      = w_advance;
    assign o_cap_count     = r_all_done ? 3'd4 : r_cap_count;
    assign o_cap_req_ready = !r_trig_pending && !r_all_done;
    assign o_all_done      = r_all_done;

endmodule
