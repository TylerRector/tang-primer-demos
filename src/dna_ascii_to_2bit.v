`timescale 1ns / 1ps

module dna_ascii_to_2bit (
    input wire [7:0] ascii_char,
    output reg [1:0] dna_base,
    output reg valid
);

    always @* begin
        valid = 1'b1;
        case (ascii_char)
            "A": dna_base = 2'b00;
            "C": dna_base = 2'b01;
            "G": dna_base = 2'b10;
            "T": dna_base = 2'b11;
            default: begin
                dna_base = 2'b00;
                valid = 1'b0;
            end
        endcase
    end

endmodule
