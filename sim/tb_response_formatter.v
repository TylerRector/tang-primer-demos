`timescale 1ns / 1ps

module tb_response_formatter;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg response_start = 1'b0;
    reg [2:0] response_type = 3'd0;
    reg [31:0] count = 32'd0;
    reg [2:0] error_code = 3'd0;
    reg uart_tx_busy = 1'b0;
    wire tx_start;
    wire [7:0] tx_data;
    wire response_busy;

    reg [8*64-1:0] captured = 0;
    integer idx = 0;

    response_formatter dut(
        .clk(clk), .reset(reset), .response_start(response_start),
        .response_type(response_type), .count(count),
        .frame_count(32'd42), .render_mode(4'd3), .debug_mode(2'd1),
        .precision_level(2'd2), .sync_active(1'b1), .error_code(error_code),
        .uart_tx_busy(uart_tx_busy), .tx_start(tx_start), .tx_data(tx_data),
        .response_busy(response_busy)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (tx_start) begin
            captured[(63-idx)*8 +: 8] <= tx_data;
            idx <= idx + 1;
            uart_tx_busy <= 1'b1;
        end else begin
            uart_tx_busy <= 1'b0;
        end
    end

    task start_response;
        input [2:0] typ;
        input [31:0] cnt;
        input [2:0] err;
        begin
            idx = 0;
            captured = 0;
            @(posedge clk);
            response_type <= typ;
            count <= cnt;
            error_code <= err;
            response_start <= 1'b1;
            @(posedge clk);
            response_start <= 1'b0;
            wait (response_busy);
            wait (!response_busy);
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset <= 1'b0;
        start_response(3'd4, 32'd3, 3'd0);
        if (captured[511 -: 64] !== "COUNT 3\n") begin
            $display("FAIL COUNT captured=%h", captured);
            $finish;
        end
        start_response(3'd5, 32'd0, 3'd4);
        if (captured[511 -: 104] !== "ERR BAD_BASE\n") begin
            $display("FAIL ERR captured=%h", captured);
            $finish;
        end
        start_response(3'd7, 32'd0, 3'd0);
        if (captured[511 -: 408] !== "STATUS frame=0000002a mode=3 debug=1 prec=2 sync=1\n") begin
            $display("FAIL STATUS captured=%h", captured);
            $finish;
        end
        $display("tb_response_formatter PASS");
        $finish;
    end
endmodule
