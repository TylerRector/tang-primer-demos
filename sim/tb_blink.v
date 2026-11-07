`timescale 1ns / 1ps
module tb_blink;
    reg clk = 0;
    wire led;
    integer cycle;
    blink #(.TOGGLE_CYCLES(4)) dut (.Clock(clk), .IO_voltage(led));
    always #5 clk = ~clk;
    initial begin
        for (cycle = 1; cycle <= 20; cycle = cycle + 1) begin
            @(posedge clk); #1;
            if (led !== ((cycle / 4) % 2))
                $fatal(1, "Incorrect LED state at cycle %0d", cycle);
        end
        $display("tb_blink PASS");
        $finish;
    end
endmodule
