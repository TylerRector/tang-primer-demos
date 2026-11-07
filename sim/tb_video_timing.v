`timescale 1ns / 1ps

module tb_video_timing;
    reg clk = 1'b0;
    reg reset = 1'b1;
    wire [10:0] x;
    wire [9:0] y;
    wire active;
    wire hsync;
    wire vsync;
    wire frame_start;
    integer active_count = 0;
    integer frames = 0;

    video_timing dut(
        .clk(clk), .reset(reset), .x(x), .y(y), .active(active),
        .hsync(hsync), .vsync(vsync), .frame_start(frame_start)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && frame_start) begin
            frames = frames + 1;
            if (frames == 1 && active_count != 640 * 480) begin
                $display("FAIL active_count=%0d", active_count);
                $finish;
            end
            if (frames == 2) begin
                $display("tb_video_timing PASS");
                $finish;
            end
            active_count = 0;
        end else if (!reset && active) begin
            active_count = active_count + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        reset <= 1'b0;
    end
endmodule
