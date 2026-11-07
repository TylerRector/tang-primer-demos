`timescale 1ns / 1ps

module debug_overlay (
    input wire [9:0] x,
    input wire [8:0] y,
    input wire [15:0] pixel_in,
    input wire [3:0] mode,
    input wire [1:0] precision_level,
    input wire [31:0] frame_count,
    input wire debug_enable,
    input wire sync_active,
    output reg [15:0] pixel_out
);
    always @* begin
        pixel_out = pixel_in;
        if (debug_enable) begin
            if (x < {6'd0, mode, 2'd0}) begin
                pixel_out = 16'hf800;
            end
            if (x > 10'd310 && y < {6'd0, precision_level, 5'd0}) begin
                pixel_out = 16'h07e0;
            end
            if (y > 9'd232 && x[7:0] < frame_count[7:0]) begin
                pixel_out = 16'h001f;
            end
            if (x < 10'd10 && y < 9'd10) begin
                pixel_out = sync_active ? 16'h07e0 : 16'hf800;
            end
        end
    end
endmodule
