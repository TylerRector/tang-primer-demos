`timescale 1ns / 1ps

module tb_uart_rx;
    localparam integer CLK_HZ = 1000000;
    localparam integer BAUD = 10000;
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg rx = 1'b1;
    wire [7:0] data;
    wire data_valid;
    wire framing_error;
    reg [7:0] last_data = 8'd0;
    integer valid_count = 0;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut(
        .clk(clk), .reset(reset), .rx(rx), .data(data),
        .data_valid(data_valid), .framing_error(framing_error)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (data_valid) begin
            last_data <= data;
            valid_count <= valid_count + 1;
        end
    end

    task bit_time;
        begin
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task send_byte;
        input [7:0] value;
        integer i;
        begin
            rx <= 1'b0; bit_time();
            for (i = 0; i < 8; i = i + 1) begin
                rx <= value[i]; bit_time();
            end
            rx <= 1'b1; bit_time();
        end
    endtask

    task expect_byte;
        input [7:0] value;
        integer start_count;
        begin
            start_count = valid_count;
            send_byte(value);
            wait (valid_count > start_count);
            #1;
            if (last_data !== value || framing_error) begin
                $display("FAIL got=%h expected=%h framing=%b", last_data, value, framing_error);
                $finish;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset <= 1'b0;
        expect_byte("A");
        expect_byte("C");
        expect_byte("G");
        expect_byte("T");
        expect_byte(8'h0a);
        $display("tb_uart_rx PASS");
        $finish;
    end
endmodule
