`timescale 1ns / 1ps

// 27 MHz Dock clock; toggle twice per second for a 1 Hz heartbeat.
module blink #(
    parameter integer TOGGLE_CYCLES = 13_500_000
) (
    input wire Clock,
    output reg IO_voltage = 1'b0
);
    reg [31:0] counter = 32'd0;

    always @(posedge Clock) begin
        if (counter == TOGGLE_CYCLES - 1) begin
            counter <= 32'd0;
            IO_voltage <= ~IO_voltage;
        end else begin
            counter <= counter + 32'd1;
        end
    end
endmodule
