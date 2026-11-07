`timescale 1ns / 1ps

module video_timing #(
    parameter integer H_ACTIVE = 640,
    parameter integer H_FRONT = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BACK = 48,
    parameter integer V_ACTIVE = 480,
    parameter integer V_FRONT = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 33
) (
    input wire clk,
    input wire reset,
    output reg [10:0] x,
    output reg [9:0] y,
    output wire active,
    output wire hsync,
    output wire vsync,
    output reg frame_start
);

    localparam integer H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    assign active = (x < H_ACTIVE) && (y < V_ACTIVE);
    assign hsync = ~((x >= H_ACTIVE + H_FRONT) && (x < H_ACTIVE + H_FRONT + H_SYNC));
    assign vsync = ~((y >= V_ACTIVE + V_FRONT) && (y < V_ACTIVE + V_FRONT + V_SYNC));

    always @(posedge clk) begin
        if (reset) begin
            x <= 11'd0;
            y <= 10'd0;
            frame_start <= 1'b0;
        end else begin
            frame_start <= 1'b0;
            if (x == H_TOTAL - 1) begin
                x <= 11'd0;
                if (y == V_TOTAL - 1) begin
                    y <= 10'd0;
                    frame_start <= 1'b1;
                end else begin
                    y <= y + 10'd1;
                end
            end else begin
                x <= x + 11'd1;
            end
        end
    end
endmodule
