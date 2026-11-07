`timescale 1ns / 1ps

module top_tb;
    localparam integer CLKS_PER_BIT = 234;

    reg Clock = 1'b0;
    reg UART_RX = 1'b1;
    wire IO_voltage;
    wire UART_TX;
    integer uart_edges = 0;
    reg [8*64-1:0] line;

    dna_count #(
        .HEARTBEAT_TOGGLE_CYCLES(64)
    ) dut (
        .Clock(Clock),
        .UART_RX(UART_RX),
        .IO_voltage(IO_voltage),
        .UART_TX(UART_TX)
    );

    always #18.518 Clock = ~Clock;

    always @(negedge UART_TX) begin
        uart_edges = uart_edges + 1;
    end

    task bit_time;
        begin
            repeat (CLKS_PER_BIT) @(posedge Clock);
        end
    endtask

    task send_byte;
        input [7:0] value;
        integer i;
        begin
            UART_RX <= 1'b0; bit_time();
            for (i = 0; i < 8; i = i + 1) begin
                UART_RX <= value[i]; bit_time();
            end
            UART_RX <= 1'b1; bit_time();
        end
    endtask

    task send_command;
        input [8*32-1:0] text;
        integer i;
        reg [7:0] ch;
        begin
            for (i = 31; i >= 0; i = i - 1) begin
                ch = text[i*8 +: 8];
                if (ch != 8'h00) begin
                    send_byte(ch);
                end
            end
            send_byte(8'h0a);
        end
    endtask

    task read_byte;
        output [7:0] value;
        integer i;
        begin
            wait (UART_TX == 1'b0);
            repeat (CLKS_PER_BIT + (CLKS_PER_BIT / 2)) @(posedge Clock);
            for (i = 0; i < 8; i = i + 1) begin
                value[i] = UART_TX;
                bit_time();
            end
            repeat (CLKS_PER_BIT / 2) @(posedge Clock);
        end
    endtask

    task read_line;
        output [8*64-1:0] line;
        integer idx;
        reg [7:0] ch;
        begin
            line = {64{8'h00}};
            idx = 0;
            ch = 8'h00;
            while (ch != 8'h0a && idx < 64) begin
                read_byte(ch);
                line[(63-idx)*8 +: 8] = ch;
                idx = idx + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("build/sim/top_tb.vcd");
        $dumpvars(0, top_tb);

        read_line(line);
        if (line[511 -: 26*8] !== "HELLO FROM TANG PRIMER 20K" ||
            line[(63-26)*8 +: 8] !== 8'h0d ||
            line[(63-27)*8 +: 8] !== 8'h0a) begin
            $display("ERROR: bad boot line: %h", line);
            $finish;
        end

        send_command("PING");
        read_line(line);
        if (line[511 -: 5*8] !== "PONG\n") begin
            $display("ERROR: bad PING reply: %h", line);
            $finish;
        end

        send_command("VERSION");
        read_line(line);
        if (line[511 -: 8*8] !== "VERSION ") begin
            $display("ERROR: bad VERSION reply: %h", line);
            $finish;
        end

        send_command("STATUS");
        read_line(line);
        if (line[511 -: 7*8] !== "STATUS ") begin
            $display("ERROR: bad STATUS reply: %h", line);
            $finish;
        end

        if (uart_edges == 0) begin
            $display("ERROR: no UART_TX activity observed");
            $finish;
        end

        $display("top_tb PASS: boot, PING, VERSION, STATUS");
        $finish;
    end
endmodule
