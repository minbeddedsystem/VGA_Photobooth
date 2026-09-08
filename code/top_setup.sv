`timescale 1ns / 1ps

module top_setup(
    input  logic clk,
    input  logic reset,

    output logic scl,
    inout  wire  sda,

    output logic setup_done
);

    logic [6:0] idx;
    logic [7:0] reg_addr;
    logic [7:0] reg_data;

    logic [7:0] tx_data;

    logic cmd_start;
    logic cmd_write;
    logic cmd_stop;

    logic done;

    logic [7:0] rx_data;
    logic ack_out;
    logic busy;

    setup_rom u_setup_rom (
        .setup_idx (idx),
        .reg_addr  (reg_addr),
        .reg_data  (reg_data)
    );

    setup_fsm u_setup_fsm (
        .clk          (clk),
        .reset        (reset),

        .idx          (idx),
        .reg_addr     (reg_addr),
        .reg_data     (reg_data),

        .tx_data      (tx_data),
        .o_cmd_start  (cmd_start),
        .o_cmd_write  (cmd_write),
        .o_cmd_stop   (cmd_stop),
        .o_setup_done (setup_done),

        .done         (done)
    );

    I2C_Master_top u_i2c_master (
        .clk       (clk),
        .reset     (reset),

        .cmd_start (cmd_start),
        .cmd_write (cmd_write),
        .cmd_read  (1'b0),
        .cmd_stop  (cmd_stop),

        .tx_data   (tx_data),
        .rx_data   (rx_data),

        .ack_in    (1'b1),
        .ack_out   (ack_out),

        .busy      (busy),
        .done      (done),

        .scl       (scl),
        .sda       (sda)
    );

endmodule
