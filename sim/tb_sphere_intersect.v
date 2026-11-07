`timescale 1ns / 1ps

module tb_sphere_intersect;
    reg signed [15:0] ray_x = 16'sd0;
    reg signed [15:0] ray_y = 16'sd0;
    wire hit;
    wire [15:0] t;
    wire signed [15:0] normal_x;
    wire signed [15:0] normal_y;

    sphere_intersect dut(
        .ray_x(ray_x), .ray_y(ray_y), .sphere_x(16'sd0), .sphere_y(16'sd0),
        .radius2(32'd1024), .base_t(16'd100), .hit(hit), .t(t),
        .normal_x(normal_x), .normal_y(normal_y)
    );

    initial begin
        #1;
        if (!hit || t != 16'd100) begin
            $display("FAIL center hit hit=%0d t=%0d", hit, t);
            $finish;
        end
        ray_x = 16'sd64;
        #1;
        if (hit) begin
            $display("FAIL miss");
            $finish;
        end
        $display("tb_sphere_intersect PASS");
        $finish;
    end
endmodule
