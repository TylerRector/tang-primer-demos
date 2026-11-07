`timescale 1ns / 1ps

module tb_status_leds;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rx_byte_valid = 1'b0;
    reg count_active = 1'b0;
    reg match_pulse = 1'b0;
    reg protocol_error = 1'b0;
    wire heartbeat_led;
    wire rx_activity_led;
    wire count_active_led;
    wire match_seen_led;
    wire error_led;

    status_leds #(
        .CLK_HZ(8),
        .HEARTBEAT_HZ(1),
        .RX_PULSE_CYCLES(3),
        .MATCH_PULSE_CYCLES(3)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_byte_valid(rx_byte_valid),
        .count_active(count_active),
        .match_pulse(match_pulse),
        .protocol_error(protocol_error),
        .heartbeat_led(heartbeat_led),
        .rx_activity_led(rx_activity_led),
        .count_active_led(count_active_led),
        .match_seen_led(match_seen_led),
        .error_led(error_led)
    );

    always #5 clk = ~clk;

    task pulse_rx;
        begin
            @(posedge clk);
            rx_byte_valid <= 1'b1;
            @(posedge clk);
            rx_byte_valid <= 1'b0;
        end
    endtask

    task pulse_match;
        begin
            @(posedge clk);
            match_pulse <= 1'b1;
            @(posedge clk);
            match_pulse <= 1'b0;
        end
    endtask

    task pulse_error;
        begin
            @(posedge clk);
            protocol_error <= 1'b1;
            @(posedge clk);
            protocol_error <= 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst <= 1'b0;

        repeat (4) @(posedge clk);
        #1;
        if (heartbeat_led !== 1'b1) begin
            $display("FAIL heartbeat did not toggle");
            $finish;
        end

        pulse_rx();
        #1;
        if (rx_activity_led !== 1'b1) begin
            $display("FAIL rx_activity_led did not assert");
            $finish;
        end

        count_active <= 1'b1;
        @(posedge clk);
        #1;
        if (count_active_led !== 1'b1) begin
            $display("FAIL count_active_led did not follow count_active");
            $finish;
        end
        count_active <= 1'b0;
        @(posedge clk);
        #1;
        if (count_active_led !== 1'b0) begin
            $display("FAIL count_active_led did not clear");
            $finish;
        end

        pulse_match();
        #1;
        if (match_seen_led !== 1'b1) begin
            $display("FAIL match_seen_led did not assert");
            $finish;
        end

        pulse_error();
        #1;
        if (error_led !== 1'b1) begin
            $display("FAIL error_led did not latch");
            $finish;
        end

        rst <= 1'b1;
        @(posedge clk);
        #1;
        if (rx_activity_led !== 1'b0 || match_seen_led !== 1'b0 || error_led !== 1'b0) begin
            $display("FAIL reset did not clear LED state");
            $finish;
        end

        $display("tb_status_leds PASS");
        $finish;
    end
endmodule
