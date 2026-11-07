`timescale 1ns / 1ps

module sphere_intersect (
    input wire signed [15:0] ray_x,
    input wire signed [15:0] ray_y,
    input wire signed [15:0] sphere_x,
    input wire signed [15:0] sphere_y,
    input wire [31:0] radius2,
    input wire [15:0] base_t,
    output wire hit,
    output wire [15:0] t,
    output wire signed [15:0] normal_x,
    output wire signed [15:0] normal_y
);
    wire signed [16:0] dx = ray_x - sphere_x;
    wire signed [16:0] dy = ray_y - sphere_y;
    wire [33:0] dx2 = dx * dx;
    wire [33:0] dy2 = dy * dy;
    wire [34:0] dist2 = dx2 + dy2;

    assign hit = dist2 <= radius2;
    assign t = base_t + dist2[25:10];
    assign normal_x = dx[15:0];
    assign normal_y = dy[15:0];
endmodule
