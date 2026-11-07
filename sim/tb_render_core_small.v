`timescale 1ns / 1ps

module tb_render_core_small;
    reg [9:0] x = 10'd0;
    reg [8:0] y = 9'd0;
    reg [3:0] mode = 4'd1;
    wire [15:0] rgb565;
    wire [3:0] hit_id;
    wire [15:0] depth;
    integer fd;
    integer px;
    integer py;
    reg [7:0] r;
    reg [7:0] g;
    reg [7:0] b;

    render_core dut(
        .pixel_x(x), .pixel_y(y), .frame_count(32'd64), .mode(mode),
        .precision_level(2'd3), .rgb565(rgb565), .hit_id(hit_id), .depth(depth)
    );

    task write_frame;
        input [3:0] frame_mode;
        input [1023:0] path;
        begin
            mode = frame_mode;
            fd = $fopen(path, "w");
            if (fd == 0) begin
                $display("FAIL open %0s", path);
                $finish;
            end
            $fwrite(fd, "P3\n64 48\n255\n");
            for (py = 0; py < 48; py = py + 1) begin
                for (px = 0; px < 64; px = px + 1) begin
                    x = px * 5;
                    y = py * 5;
                    #1;
                    r = {rgb565[15:11], rgb565[15:13]};
                    g = {rgb565[10:5], rgb565[10:9]};
                    b = {rgb565[4:0], rgb565[4:2]};
                    $fwrite(fd, "%0d %0d %0d\n", r, g, b);
                end
            end
            $fclose(fd);
        end
    endtask

    initial begin
        write_frame(4'd0, "results/frames/test_pattern_64x48.ppm");
        write_frame(4'd1, "results/frames/hit_id_64x48.ppm");
        write_frame(4'd2, "results/frames/depth_64x48.ppm");
        write_frame(4'd4, "results/frames/shaded_64x48.ppm");
        x = 10'd160;
        y = 9'd120;
        mode = 4'd1;
        #1;
        if (hit_id == 4'd0) begin
            $display("FAIL expected center/floor hit");
            $finish;
        end
        $display("tb_render_core_small PASS");
        $finish;
    end
endmodule
