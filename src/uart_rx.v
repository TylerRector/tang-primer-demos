`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD = 115200
) (
    input wire clk,
    input wire reset,
    input wire rx,
    output reg [7:0] data,
    output reg data_valid,
    output reg framing_error
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;

    localparam [1:0] STATE_IDLE  = 2'd0;
    localparam [1:0] STATE_START = 2'd1;
    localparam [1:0] STATE_DATA  = 2'd2;
    localparam [1:0] STATE_STOP  = 2'd3;

    reg [1:0] state = STATE_IDLE;
    reg [31:0] clk_count = 32'd0;
    reg [2:0] bit_index = 3'd0;
    reg [7:0] data_shift = 8'd0;
    reg rx_meta = 1'b1;
    reg rx_sync = 1'b1;

    always @(posedge clk) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            clk_count <= 32'd0;
            bit_index <= 3'd0;
            data_shift <= 8'd0;
            data <= 8'd0;
            data_valid <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    clk_count <= 32'd0;
                    bit_index <= 3'd0;
                    if (!rx_sync) begin
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (clk_count == HALF_BIT - 1) begin
                        clk_count <= 32'd0;
                        if (!rx_sync) begin
                            state <= STATE_DATA;
                        end else begin
                            state <= STATE_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 32'd1;
                    end
                end

                STATE_DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'd0;
                        data_shift[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        clk_count <= clk_count + 32'd1;
                    end
                end

                STATE_STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'd0;
                        if (rx_sync) begin
                            data <= data_shift;
                            data_valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                        state <= STATE_IDLE;
                    end else begin
                        clk_count <= clk_count + 32'd1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    clk_count <= 32'd0;
                    bit_index <= 3'd0;
                end
            endcase
        end
    end

endmodule
