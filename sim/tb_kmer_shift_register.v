`timescale 1ns / 1ps

module tb_kmer_shift_register;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg clear = 1'b0;
    reg base_valid = 1'b0;
    reg [1:0] base_2bit = 2'b00;
    wire [15:0] window;
    wire valid_window;

    kmer_shift_register #(.K(8)) dut(
        .clk(clk), .reset(reset), .clear(clear), .base_valid(base_valid),
        .base_2bit(base_2bit), .window(window), .valid_window(valid_window)
    );

    always #5 clk = ~clk;

    task push;
        input [1:0] b;
        begin
            @(posedge clk);
            base_2bit <= b;
            base_valid <= 1'b1;
            @(posedge clk);
            base_valid <= 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset <= 1'b0;
        push(2'b00); push(2'b01); push(2'b10); push(2'b11);
        push(2'b00); push(2'b01); push(2'b10); push(2'b11);
        #1;
        if (window !== 16'b0001101100011011 || valid_window !== 1'b1) begin
            $display("FAIL window=%b valid=%b", window, valid_window);
            $finish;
        end
        push(2'b00);
        #1;
        if (window !== 16'b0110110001101100) begin
            $display("FAIL overlapping window=%b", window);
            $finish;
        end
        $display("tb_kmer_shift_register PASS");
        $finish;
    end
endmodule
