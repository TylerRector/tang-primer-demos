`timescale 1ns / 1ps

module tb_command_parser;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [7:0] rx_data = 8'd0;
    reg rx_valid = 1'b0;
    reg response_busy = 1'b0;
    reg pattern_loaded = 1'b0;
    wire clear_pattern;
    wire clear_count;
    wire clear_window;
    wire pattern_base_valid;
    wire [1:0] pattern_base;
    wire count_base_valid;
    wire [1:0] count_base;
    wire response_request;
    wire [2:0] response_type;
    wire [2:0] error_code;
    wire cmd_mode;
    wire [3:0] mode_value;
    wire cmd_debug;
    wire [1:0] debug_value;
    wire cmd_precision;
    wire [1:0] precision_value;
    reg saw_mode3 = 1'b0;
    reg saw_debug1 = 1'b0;
    reg saw_precision2 = 1'b0;

    command_parser #(.COMMAND_BUFFER_BYTES(128), .K(8)) dut(
        .clk(clk), .reset(reset), .rx_data(rx_data), .rx_valid(rx_valid),
        .response_busy(response_busy), .pattern_loaded(pattern_loaded),
        .cmd_ping(), .cmd_version(), .cmd_reset(),
        .cmd_demo_start(), .cmd_demo_stop(), .cmd_status(),
        .cmd_mode(cmd_mode), .mode_value(mode_value),
        .cmd_debug(cmd_debug), .debug_value(debug_value),
        .cmd_precision(cmd_precision), .precision_value(precision_value),
        .clear_pattern(clear_pattern),
        .clear_count(clear_count), .clear_window(clear_window),
        .pattern_base_valid(pattern_base_valid), .pattern_base(pattern_base),
        .cmd_count_begin(), .cmd_count_base_valid(count_base_valid),
        .cmd_count_base(count_base), .cmd_count_done(),
        .response_request(response_request), .response_type(response_type), .error_code(error_code)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (cmd_mode && mode_value == 4'd3) begin
            saw_mode3 <= 1'b1;
        end
        if (cmd_debug && debug_value == 2'd1) begin
            saw_debug1 <= 1'b1;
        end
        if (cmd_precision && precision_value == 2'd2) begin
            saw_precision2 <= 1'b1;
        end
    end

    task putc;
        input [7:0] ch;
        begin
            @(posedge clk);
            rx_data <= ch;
            rx_valid <= 1'b1;
            @(posedge clk);
            rx_valid <= 1'b0;
        end
    endtask

    task send_ping;
        begin
            putc("P"); putc("I"); putc("N"); putc("G"); putc(8'h0a);
        end
    endtask

    task send_setpat;
        begin
            putc("S"); putc("E"); putc("T"); putc("P"); putc("A"); putc("T"); putc(" ");
            putc("A"); putc("C"); putc("G"); putc("T"); putc("A"); putc("C"); putc("G"); putc("T"); putc(8'h0a);
        end
    endtask

    task send_stream_begin;
        begin
            putc("S"); putc("T"); putc("R"); putc("E"); putc("A"); putc("M"); putc("_");
            putc("B"); putc("E"); putc("G"); putc("I"); putc("N"); putc(8'h0a);
        end
    endtask

    task send_stream_begin_quiet;
        begin
            putc("S"); putc("T"); putc("R"); putc("E"); putc("A"); putc("M"); putc("_");
            putc("B"); putc("E"); putc("G"); putc("I"); putc("N"); putc("_");
            putc("Q"); putc("U"); putc("I"); putc("E"); putc("T"); putc(8'h0a);
        end
    endtask

    task send_stream_end;
        begin
            putc("S"); putc("T"); putc("R"); putc("E"); putc("A"); putc("M"); putc("_");
            putc("E"); putc("N"); putc("D"); putc(8'h0a);
        end
    endtask

    task send_stream_acgt;
        begin
            putc("S"); putc("T"); putc("R"); putc("E"); putc("A"); putc("M"); putc(" ");
            putc("A"); putc("C"); putc("G"); putc("T"); putc(8'h0a);
        end
    endtask

    task send_stream_bad;
        begin
            putc("S"); putc("T"); putc("R"); putc("E"); putc("A"); putc("M"); putc(" ");
            putc("A"); putc("N"); putc("G"); putc("T"); putc(8'h0a);
        end
    endtask

    task send_mode3;
        begin
            putc("M"); putc("O"); putc("D"); putc("E"); putc(" "); putc("3"); putc(8'h0a);
        end
    endtask

    task send_debug1;
        begin
            putc("D"); putc("E"); putc("B"); putc("U"); putc("G"); putc(" "); putc("1"); putc(8'h0a);
        end
    endtask

    task send_precision2;
        begin
            putc("P"); putc("R"); putc("E"); putc("C"); putc("I"); putc("S"); putc("I"); putc("O"); putc("N"); putc(" "); putc("2"); putc(8'h0a);
        end
    endtask

    task send_status;
        begin
            putc("S"); putc("T"); putc("A"); putc("T"); putc("U"); putc("S"); putc(8'h0a);
        end
    endtask

    task wait_response;
        input [2:0] exp_type;
        input [2:0] exp_error;
        begin
            wait (response_request);
            #1;
            if (response_type !== exp_type || error_code !== exp_error) begin
                $display("FAIL response type=%0d error=%0d", response_type, error_code);
                $finish;
            end
            @(posedge clk);
        end
    endtask

    task expect_no_response_cycles;
        input integer cycles;
        begin
            repeat (cycles) @(posedge clk);
            #1;
            if (response_request !== 1'b0) begin
                $display("FAIL unexpected response type=%0d error=%0d", response_type, error_code);
                $finish;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset <= 1'b0;
        send_ping();
        wait_response(3'd1, 3'd0);

        send_mode3();
        wait_response(3'd3, 3'd0);
        if (saw_mode3 !== 1'b1) begin
            $display("FAIL MODE pulse/value");
            $finish;
        end

        send_debug1();
        wait_response(3'd3, 3'd0);
        if (saw_debug1 !== 1'b1) begin
            $display("FAIL DEBUG pulse/value");
            $finish;
        end

        send_precision2();
        wait_response(3'd3, 3'd0);
        if (saw_precision2 !== 1'b1) begin
            $display("FAIL PRECISION pulse/value");
            $finish;
        end

        send_status();
        wait_response(3'd7, 3'd0);

        send_setpat();
        wait_response(3'd3, 3'd0);

        putc("C"); putc("O"); putc("U"); putc("N"); putc("T"); putc(" ");
        putc("A"); putc("C"); putc("G"); putc("T"); putc(8'h0a);
        wait_response(3'd5, 3'd5);

        pattern_loaded <= 1'b1;
        putc("C"); putc("O"); putc("U"); putc("N"); putc("T"); putc(" ");
        putc("A"); putc("C"); putc("G"); putc("T"); putc(8'h0a);
        wait_response(3'd4, 3'd0);

        send_stream_acgt();
        wait_response(3'd5, 3'd6);

        send_stream_begin();
        wait_response(3'd3, 3'd0);

        send_stream_bad();
        wait_response(3'd5, 3'd4);

        send_stream_begin();
        wait_response(3'd3, 3'd0);
        send_stream_acgt();
        wait_response(3'd3, 3'd0);
        send_stream_acgt();
        wait_response(3'd3, 3'd0);
        send_stream_end();
        wait_response(3'd4, 3'd0);

        send_stream_begin_quiet();
        wait_response(3'd3, 3'd0);
        send_stream_acgt();
        expect_no_response_cycles(40);
        send_stream_acgt();
        expect_no_response_cycles(40);
        send_stream_end();
        wait_response(3'd4, 3'd0);

        send_stream_begin_quiet();
        wait_response(3'd3, 3'd0);
        send_stream_bad();
        wait_response(3'd5, 3'd4);

        $display("tb_command_parser PASS");
        $finish;
    end
endmodule
