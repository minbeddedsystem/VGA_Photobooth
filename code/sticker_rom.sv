`timescale 1ns / 1ps

module sticker_rom (
    input  logic       clk,
    input  logic [1:0] idx,
    input  logic [1:0] size,
    input  logic [4:0] x,
    input  logic [4:0] y,
    output logic [11:0] rgb,
    output logic        transparent
);

    logic [15:0] mem [0:8191];
    initial $readmemh("sticker_rom_4slot.mem", mem);

    logic [10:0] local_addr;
    always_comb begin
        case (size)
            2'd3:    local_addr = 11'd0    + {y, x};
            2'd2:    local_addr = 11'd1024 + (11'(y) << 4) + x;
            2'd1:    local_addr = 11'd1280 + (11'(y) << 3) + x;
            default: local_addr = 11'd1344 + (11'(y) << 2) + x;
        endcase
    end

    logic [12:0] addr;
    assign addr = {idx, local_addr};

    logic [15:0] data_d1;
    always_ff @(posedge clk)
        data_d1 <= mem[addr];

    assign rgb         = data_d1[11:0];
    assign transparent = data_d1[15];

endmodule
