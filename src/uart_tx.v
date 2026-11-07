`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input wire clk,
    input wire reset,
    input wire tx_start,
    input wire [7:0] tx_data,
    output reg tx,
    output reg tx_busy
);

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_START = 3'd1;
    localparam [2:0] STATE_DATA  = 3'd2;
    localparam [2:0] STATE_STOP  = 3'd3;

    reg [2:0] state = STATE_IDLE;
    reg [31:0] clk_count = 32'd0;
    reg [2:0] bit_index = 3'd0;
    reg [7:0] data_reg = 8'd0;

    initial begin
        tx = 1'b1;
        tx_busy = 1'b0;
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            clk_count <= 32'd0;
            bit_index <= 3'd0;
            data_reg <= 8'd0;
            tx <= 1'b1;
            tx_busy <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_count <= 32'd0;
                    bit_index <= 3'd0;

                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy <= 1'b1;
                        tx <= 1'b0;
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    tx <= 1'b0;
                    tx_busy <= 1'b1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'd0;
                        tx <= data_reg[0];
                        state <= STATE_DATA;
                    end else begin
                        clk_count <= clk_count + 32'd1;
                    end
                end

                STATE_DATA: begin
                    tx <= data_reg[bit_index];
                    tx_busy <= 1'b1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'd0;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            tx <= 1'b1;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                            tx <= data_reg[bit_index + 3'd1];
                        end
                    end else begin
                        clk_count <= clk_count + 32'd1;
                    end
                end

                STATE_STOP: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 32'd0;
                        tx_busy <= 1'b0;
                        state <= STATE_IDLE;
                    end else begin
                        clk_count <= clk_count + 32'd1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_count <= 32'd0;
                    bit_index <= 3'd0;
                end
            endcase
        end
    end

endmodule
