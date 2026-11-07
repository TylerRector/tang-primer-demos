`timescale 1ns / 1ps

module kmer_shift_register #(
    parameter integer K = 8
) (
    input wire clk,
    input wire reset,
    input wire clear,
    input wire base_valid,
    input wire [1:0] base_2bit,
    output reg [2*K-1:0] window,
    output reg valid_window
);

    reg [31:0] valid_count = 32'd0;

    always @(posedge clk) begin
        if (reset || clear) begin
            window <= {2*K{1'b0}};
            valid_window <= 1'b0;
            valid_count <= 32'd0;
        end else if (base_valid) begin
            window <= {window[2*K-3:0], base_2bit};
            if (valid_count < K) begin
                valid_count <= valid_count + 32'd1;
            end
            valid_window <= (valid_count + 32'd1 >= K);
        end
    end

endmodule
