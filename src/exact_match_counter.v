`timescale 1ns / 1ps

module exact_match_counter #(
    parameter integer K = 8,
    parameter integer COUNT_WIDTH = 32
) (
    input wire clk,
    input wire reset,
    input wire clear_count,
    input wire clear_pattern,
    input wire pattern_base_valid,
    input wire [1:0] pattern_base,
    input wire [2*K-1:0] window,
    input wire valid_window,
    input wire window_advance,
    output reg pattern_loaded,
    output reg match_pulse,
    output reg [COUNT_WIDTH-1:0] count
);

    reg [2*K-1:0] pattern = {2*K{1'b0}};
    reg [31:0] pattern_count = 32'd0;

    always @(posedge clk) begin
        if (reset) begin
            pattern <= {2*K{1'b0}};
            pattern_count <= 32'd0;
            pattern_loaded <= 1'b0;
            count <= {COUNT_WIDTH{1'b0}};
            match_pulse <= 1'b0;
        end else begin
            match_pulse <= 1'b0;

            if (clear_pattern) begin
                pattern <= {2*K{1'b0}};
                pattern_count <= 32'd0;
                pattern_loaded <= 1'b0;
            end else if (pattern_base_valid) begin
                pattern <= {pattern[2*K-3:0], pattern_base};
                if (pattern_count < K) begin
                    pattern_count <= pattern_count + 32'd1;
                end
                pattern_loaded <= (pattern_count + 32'd1 >= K);
            end

            if (clear_count) begin
                count <= {COUNT_WIDTH{1'b0}};
            end else if (window_advance && valid_window && pattern_loaded && window == pattern) begin
                count <= count + {{COUNT_WIDTH-1{1'b0}}, 1'b1};
                match_pulse <= 1'b1;
            end
        end
    end

endmodule
