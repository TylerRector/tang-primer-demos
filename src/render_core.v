`timescale 1ns / 1ps
`include "fixed_math.vh"

module render_core (
    input wire [9:0] pixel_x,
    input wire [8:0] pixel_y,
    input wire [31:0] frame_count,
    input wire [3:0] mode,
    input wire [1:0] precision_level,
    output reg [15:0] rgb565,
    output reg [3:0] hit_id,
    output reg [15:0] depth
);
    wire signed [15:0] rx_full = ($signed({1'b0, pixel_x}) - 16'sd160) <<< 3;
    wire signed [15:0] ry_full = (16'sd120 - $signed({1'b0, pixel_y})) <<< 3;
    wire signed [15:0] rx =
        (precision_level == 2'd0) ? {rx_full[15:7], 7'd0} :
        (precision_level == 2'd1) ? {rx_full[15:5], 5'd0} :
        (precision_level == 2'd2) ? {rx_full[15:3], 3'd0} : rx_full;
    wire signed [15:0] ry =
        (precision_level == 2'd0) ? {ry_full[15:7], 7'd0} :
        (precision_level == 2'd1) ? {ry_full[15:5], 5'd0} :
        (precision_level == 2'd2) ? {ry_full[15:3], 3'd0} : ry_full;

    wire signed [15:0] anim = {8'd0, frame_count[7:0]} - 16'sd128;

    wire s0_hit;
    wire s1_hit;
    wire s2_hit;
    wire [15:0] s0_t;
    wire [15:0] s1_t;
    wire [15:0] s2_t;
    wire signed [15:0] s0_nx;
    wire signed [15:0] s0_ny;
    wire signed [15:0] s1_nx;
    wire signed [15:0] s1_ny;
    wire signed [15:0] s2_nx;
    wire signed [15:0] s2_ny;

    sphere_intersect s0(.ray_x(rx), .ray_y(ry), .sphere_x(-16'sd520 + anim), .sphere_y(16'sd160), .radius2(32'd360000), .base_t(16'd700), .hit(s0_hit), .t(s0_t), .normal_x(s0_nx), .normal_y(s0_ny));
    sphere_intersect s1(.ray_x(rx), .ray_y(ry), .sphere_x(16'sd280), .sphere_y(-16'sd40), .radius2(32'd260000), .base_t(16'd930), .hit(s1_hit), .t(s1_t), .normal_x(s1_nx), .normal_y(s1_ny));
    sphere_intersect s2(.ray_x(rx), .ray_y(ry), .sphere_x(16'sd720 - anim), .sphere_y(16'sd260), .radius2(32'd190000), .base_t(16'd810), .hit(s2_hit), .t(s2_t), .normal_x(s2_nx), .normal_y(s2_ny));

    reg signed [15:0] nx;
    reg signed [15:0] ny;
    reg [7:0] shade;
    reg floor_hit;

    always @* begin
        floor_hit = (pixel_y > 9'd172);
        hit_id = 4'd0;
        depth = 16'hffff;
        nx = 16'sd0;
        ny = 16'sd0;

        if (floor_hit) begin
            hit_id = 4'd4;
            depth = {7'd0, pixel_y};
            nx = 16'sd0;
            ny = 16'sd1024;
        end
        if (s0_hit && s0_t < depth) begin
            hit_id = 4'd1;
            depth = s0_t;
            nx = s0_nx;
            ny = s0_ny;
        end
        if (s1_hit && s1_t < depth) begin
            hit_id = 4'd2;
            depth = s1_t;
            nx = s1_nx;
            ny = s1_ny;
        end
        if (s2_hit && s2_t < depth) begin
            hit_id = 4'd3;
            depth = s2_t;
            nx = s2_nx;
            ny = s2_ny;
        end

        shade = 8'd60 + depth[8:2];
        case (mode)
            4'd0: rgb565 = {pixel_x[8:4], pixel_y[7:2], pixel_x[7:3]};
            4'd1: begin
                case (hit_id)
                    4'd1: rgb565 = 16'hf800;
                    4'd2: rgb565 = 16'h07e0;
                    4'd3: rgb565 = 16'h001f;
                    4'd4: rgb565 = 16'h8410;
                    default: rgb565 = 16'h0000;
                endcase
            end
            4'd2: rgb565 = {depth[9:5], depth[9:4], depth[9:5]};
            4'd3: rgb565 = {nx[10:6] + 5'd16, ny[10:5] + 6'd32, 5'd16};
            4'd5: rgb565 = {rx[10:6], ry[10:5], {3'd0, precision_level}};
            4'd6: rgb565 = {16{depth[precision_level + 3]}};
            default: begin
                if (hit_id == 4'd0) begin
                    rgb565 = 16'h0002;
                end else begin
                    rgb565 = {shade[7:3], shade[7:2], shade[7:3]};
                end
            end
        endcase
    end
endmodule
