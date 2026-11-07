`timescale 1ns / 1ps

module tb_dna_ascii_to_2bit;
    reg [7:0] ascii_char;
    wire [1:0] dna_base;
    wire valid;

    dna_ascii_to_2bit dut(.ascii_char(ascii_char), .dna_base(dna_base), .valid(valid));

    task expect_mapping;
        input [7:0] ch;
        input [1:0] exp_base;
        input exp_valid;
        begin
            ascii_char = ch;
            #1;
            if (dna_base !== exp_base || valid !== exp_valid) begin
                $display("FAIL ascii=%h base=%b valid=%b", ch, dna_base, valid);
                $finish;
            end
        end
    endtask

    initial begin
        expect_mapping("A", 2'b00, 1'b1);
        expect_mapping("C", 2'b01, 1'b1);
        expect_mapping("G", 2'b10, 1'b1);
        expect_mapping("T", 2'b11, 1'b1);
        expect_mapping("N", 2'b00, 1'b0);
        expect_mapping("a", 2'b00, 1'b0);
        expect_mapping(" ", 2'b00, 1'b0);
        expect_mapping(8'h0a, 2'b00, 1'b0);
        $display("tb_dna_ascii_to_2bit PASS");
        $finish;
    end
endmodule
