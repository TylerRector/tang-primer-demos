`timescale 1ns / 1ps

module status_leds #(
    parameter integer CLK_HZ = 27000000,
    parameter integer HEARTBEAT_HZ = 1,
    parameter integer RX_PULSE_CYCLES = 2700000,
    parameter integer MATCH_PULSE_CYCLES = 2700000
) (
    input wire clk,
    input wire rst,
    input wire rx_byte_valid,
    input wire count_active,
    input wire match_pulse,
    input wire protocol_error,
    output reg heartbeat_led,
    output reg rx_activity_led,
    output wire count_active_led,
    output reg match_seen_led,
    output reg error_led
);

    localparam integer HEARTBEAT_TOGGLE_CYCLES = CLK_HZ / (2 * HEARTBEAT_HZ);

    reg [31:0] heartbeat_count = 32'd0;
    reg [31:0] rx_pulse_count = 32'd0;
    reg [31:0] match_pulse_count = 32'd0;

    assign count_active_led = count_active;

    always @(posedge clk) begin
        if (rst) begin
            heartbeat_led <= 1'b0;
            heartbeat_count <= 32'd0;
        end else if (heartbeat_count == HEARTBEAT_TOGGLE_CYCLES - 1) begin
            heartbeat_count <= 32'd0;
            heartbeat_led <= ~heartbeat_led;
        end else begin
            heartbeat_count <= heartbeat_count + 32'd1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rx_activity_led <= 1'b0;
            rx_pulse_count <= 32'd0;
        end else if (rx_byte_valid) begin
            rx_activity_led <= 1'b1;
            rx_pulse_count <= RX_PULSE_CYCLES;
        end else if (rx_pulse_count != 0) begin
            rx_pulse_count <= rx_pulse_count - 32'd1;
            rx_activity_led <= 1'b1;
        end else begin
            rx_activity_led <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            match_seen_led <= 1'b0;
            match_pulse_count <= 32'd0;
        end else if (match_pulse) begin
            match_seen_led <= 1'b1;
            match_pulse_count <= MATCH_PULSE_CYCLES;
        end else if (match_pulse_count != 0) begin
            match_pulse_count <= match_pulse_count - 32'd1;
            match_seen_led <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            error_led <= 1'b0;
        end else if (protocol_error) begin
            error_led <= 1'b1;
        end
    end

endmodule
