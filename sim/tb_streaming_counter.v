`timescale 1ns / 1ps

module tb_streaming_counter;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg clear_count = 1'b0;
    reg clear_window = 1'b0;
    reg clear_pattern = 1'b0;
    reg pattern_base_valid = 1'b0;
    reg [1:0] pattern_base = 2'b00;
    reg base_valid = 1'b0;
    reg base_valid_d = 1'b0;
    reg [1:0] base_2bit = 2'b00;
    wire [15:0] window;
    wire valid_window;
    wire pattern_loaded;
    wire match_pulse;
    wire [31:0] count;

    kmer_shift_register #(.K(8)) shift(
        .clk(clk), .reset(reset), .clear(clear_window), .base_valid(base_valid),
        .base_2bit(base_2bit), .window(window), .valid_window(valid_window)
    );

    exact_match_counter #(.K(8), .COUNT_WIDTH(32)) counter(
        .clk(clk), .reset(reset), .clear_count(clear_count), .clear_pattern(clear_pattern),
        .pattern_base_valid(pattern_base_valid), .pattern_base(pattern_base),
        .window(window), .valid_window(valid_window), .window_advance(base_valid_d),
        .pattern_loaded(pattern_loaded), .match_pulse(match_pulse), .count(count)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset || clear_window) begin
            base_valid_d <= 1'b0;
        end else begin
            base_valid_d <= base_valid;
        end
    end

    task push_pattern;
        input [1:0] b;
        begin
            @(posedge clk); pattern_base <= b; pattern_base_valid <= 1'b1;
            @(posedge clk); pattern_base_valid <= 1'b0;
        end
    endtask

    task push_base;
        input [1:0] b;
        begin
            @(posedge clk); base_2bit <= b; base_valid <= 1'b1;
            @(posedge clk); base_valid <= 1'b0;
        end
    endtask

    task push_acgt;
        begin
            push_base(2'b00); push_base(2'b01); push_base(2'b10); push_base(2'b11);
        end
    endtask

    task begin_stream;
        begin
            @(posedge clk);
            clear_count <= 1'b1;
            clear_window <= 1'b1;
            @(posedge clk);
            clear_count <= 1'b0;
            clear_window <= 1'b0;
        end
    endtask

    task wait_counter;
        begin
            repeat (3) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset <= 1'b0;

        clear_pattern <= 1'b1; @(posedge clk); clear_pattern <= 1'b0;
        push_pattern(2'b00); push_pattern(2'b01); push_pattern(2'b10); push_pattern(2'b11);
        push_pattern(2'b00); push_pattern(2'b01); push_pattern(2'b10); push_pattern(2'b11);
        wait_counter();
        if (!pattern_loaded) begin
            $display("FAIL pattern not loaded");
            $finish;
        end

        begin_stream();
        push_acgt(); push_acgt(); push_acgt(); push_acgt();
        wait_counter();
        if (count !== 32'd3) begin
            $display("FAIL single stream count=%0d expected=3", count);
            $finish;
        end

        begin_stream();
        push_acgt();
        wait_counter();
        if (count !== 32'd0) begin
            $display("FAIL shorter-than-K count=%0d expected=0", count);
            $finish;
        end

        begin_stream();
        push_acgt();
        push_acgt();
        wait_counter();
        if (count !== 32'd1) begin
            $display("FAIL cross-boundary count=%0d expected=1", count);
            $finish;
        end

        begin_stream();
        push_acgt(); push_acgt(); push_acgt(); push_acgt();
        wait_counter();
        if (count !== 32'd3) begin
            $display("FAIL multi-chunk count=%0d expected=3", count);
            $finish;
        end

        $display("tb_streaming_counter PASS");
        $finish;
    end
endmodule
