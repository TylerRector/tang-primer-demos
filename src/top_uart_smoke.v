`timescale 1ns / 1ps

module top #(
    parameter integer HEARTBEAT_TOGGLE_CYCLES = 13_500_000
) (
    input wire Clock,
    input wire UART_RX,
    output wire IO_voltage,
    output wire UART_TX
);
    localparam integer CLK_HZ = 27_000_000;
    localparam integer BAUD = 115200;
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam integer BOOT_MESSAGE_LEN = 15;

    localparam [2:0] RESP_NONE    = 3'd0;
    localparam [2:0] RESP_PONG    = 3'd1;
    localparam [2:0] RESP_VERSION = 3'd2;
    localparam [2:0] RESP_OK      = 3'd3;
    localparam [2:0] RESP_STATUS  = 3'd4;
    localparam [2:0] RESP_ERR     = 3'd5;

    reg reset = 1'b1;
    reg [4:0] reset_count = 5'd0;
    reg [31:0] heartbeat_count = 32'd0;
    reg heartbeat_led = 1'b0;

    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_framing_error;
    wire tx_busy;
    reg tx_start = 1'b0;
    reg [7:0] tx_data = 8'd0;

    reg boot_active = 1'b1;
    reg [4:0] boot_index = 5'd0;
    reg [1:0] boot_state = 2'd0;

    reg [7:0] buffer [0:31];
    reg [5:0] line_len = 6'd0;
    reg [2:0] response = RESP_NONE;
    reg [5:0] response_index = 6'd0;
    reg [31:0] frame_count = 32'd0;
    reg [3:0] render_mode = 4'd0;
    reg [1:0] debug_mode = 2'd0;
    reg [1:0] precision_level = 2'd3;
    reg sync_active = 1'b0;

    assign IO_voltage = heartbeat_led;

    function [7:0] hex_digit;
        input [3:0] value;
        begin
            hex_digit = (value < 4'd10) ? ("0" + value) : ("a" + value - 4'd10);
        end
    endfunction

    function [7:0] boot_byte;
        input [4:0] index;
        begin
            case (index)
                5'd0: boot_byte = "U";
                5'd1: boot_byte = "A";
                5'd2: boot_byte = "R";
                5'd3: boot_byte = "T";
                5'd4: boot_byte = " ";
                5'd5: boot_byte = "S";
                5'd6: boot_byte = "M";
                5'd7: boot_byte = "O";
                5'd8: boot_byte = "K";
                5'd9: boot_byte = "E";
                5'd10: boot_byte = " ";
                5'd11: boot_byte = "V";
                5'd12: boot_byte = "0";
                5'd13: boot_byte = 8'h0d;
                5'd14: boot_byte = 8'h0a;
                default: boot_byte = 8'h0a;
            endcase
        end
    endfunction

    function [7:0] response_byte;
        input [2:0] typ;
        input [5:0] index;
        begin
            response_byte = 8'h0a;
            case (typ)
                RESP_PONG: begin
                    case (index)
                        6'd0: response_byte = "P"; 6'd1: response_byte = "O";
                        6'd2: response_byte = "N"; 6'd3: response_byte = "G";
                        default: response_byte = 8'h0a;
                    endcase
                end
                RESP_VERSION: begin
                    case (index)
                        6'd0: response_byte = "V"; 6'd1: response_byte = "E";
                        6'd2: response_byte = "R"; 6'd3: response_byte = "S";
                        6'd4: response_byte = "I"; 6'd5: response_byte = "O";
                        6'd6: response_byte = "N"; 6'd7: response_byte = " ";
                        6'd8: response_byte = "T"; 6'd9: response_byte = "A";
                        6'd10: response_byte = "N"; 6'd11: response_byte = "G";
                        6'd12: response_byte = "2"; 6'd13: response_byte = "0";
                        6'd14: response_byte = "K"; 6'd15: response_byte = " ";
                        6'd16: response_byte = "U"; 6'd17: response_byte = "A";
                        6'd18: response_byte = "R"; 6'd19: response_byte = "T";
                        6'd20: response_byte = "S"; 6'd21: response_byte = "M";
                        6'd22: response_byte = "O"; 6'd23: response_byte = "K";
                        6'd24: response_byte = "E"; 6'd25: response_byte = " ";
                        6'd26: response_byte = "V"; 6'd27: response_byte = "0";
                        default: response_byte = 8'h0a;
                    endcase
                end
                RESP_OK: begin
                    case (index)
                        6'd0: response_byte = "O"; 6'd1: response_byte = "K";
                        default: response_byte = 8'h0a;
                    endcase
                end
                RESP_STATUS: begin
                    case (index)
                        6'd0: response_byte = "S"; 6'd1: response_byte = "T";
                        6'd2: response_byte = "A"; 6'd3: response_byte = "T";
                        6'd4: response_byte = "U"; 6'd5: response_byte = "S";
                        6'd6: response_byte = " "; 6'd7: response_byte = "f";
                        6'd8: response_byte = "r"; 6'd9: response_byte = "a";
                        6'd10: response_byte = "m"; 6'd11: response_byte = "e";
                        6'd12: response_byte = "="; 6'd13: response_byte = hex_digit(frame_count[31:28]);
                        6'd14: response_byte = hex_digit(frame_count[27:24]); 6'd15: response_byte = hex_digit(frame_count[23:20]);
                        6'd16: response_byte = hex_digit(frame_count[19:16]); 6'd17: response_byte = hex_digit(frame_count[15:12]);
                        6'd18: response_byte = hex_digit(frame_count[11:8]); 6'd19: response_byte = hex_digit(frame_count[7:4]);
                        6'd20: response_byte = hex_digit(frame_count[3:0]); 6'd21: response_byte = " ";
                        6'd22: response_byte = "m"; 6'd23: response_byte = "o";
                        6'd24: response_byte = "d"; 6'd25: response_byte = "e";
                        6'd26: response_byte = "="; 6'd27: response_byte = hex_digit(render_mode);
                        6'd28: response_byte = " "; 6'd29: response_byte = "d";
                        6'd30: response_byte = "e"; 6'd31: response_byte = "b";
                        6'd32: response_byte = "u"; 6'd33: response_byte = "g";
                        6'd34: response_byte = "="; 6'd35: response_byte = hex_digit({2'd0, debug_mode});
                        6'd36: response_byte = " "; 6'd37: response_byte = "p";
                        6'd38: response_byte = "r"; 6'd39: response_byte = "e";
                        6'd40: response_byte = "c"; 6'd41: response_byte = "=";
                        6'd42: response_byte = hex_digit({2'd0, precision_level}); 6'd43: response_byte = " ";
                        6'd44: response_byte = "s"; 6'd45: response_byte = "y";
                        6'd46: response_byte = "n"; 6'd47: response_byte = "c";
                        6'd48: response_byte = "="; 6'd49: response_byte = sync_active ? "1" : "0";
                        default: response_byte = 8'h0a;
                    endcase
                end
                default: begin
                    case (index)
                        6'd0: response_byte = "E"; 6'd1: response_byte = "R";
                        6'd2: response_byte = "R"; 6'd3: response_byte = " ";
                        6'd4: response_byte = "U"; 6'd5: response_byte = "N";
                        6'd6: response_byte = "K"; 6'd7: response_byte = "N";
                        6'd8: response_byte = "O"; 6'd9: response_byte = "W";
                        6'd10: response_byte = "N"; 6'd11: response_byte = "_";
                        6'd12: response_byte = "C"; 6'd13: response_byte = "M";
                        6'd14: response_byte = "D";
                        default: response_byte = 8'h0a;
                    endcase
                end
            endcase
        end
    endfunction

    function [5:0] response_len;
        input [2:0] typ;
        begin
            case (typ)
                RESP_PONG: response_len = 6'd5;
                RESP_VERSION: response_len = 6'd29;
                RESP_OK: response_len = 6'd3;
                RESP_STATUS: response_len = 6'd51;
                default: response_len = 6'd16;
            endcase
        end
    endfunction

    function match_ping;
        input unused;
        begin
            match_ping = line_len == 4 && buffer[0] == "P" && buffer[1] == "I" && buffer[2] == "N" && buffer[3] == "G";
        end
    endfunction

    function match_version;
        input unused;
        begin
            match_version = line_len == 7 && buffer[0] == "V" && buffer[1] == "E" && buffer[2] == "R" && buffer[3] == "S" &&
                            buffer[4] == "I" && buffer[5] == "O" && buffer[6] == "N";
        end
    endfunction

    function match_status;
        input unused;
        begin
            match_status = line_len == 6 && buffer[0] == "S" && buffer[1] == "T" && buffer[2] == "A" && buffer[3] == "T" &&
                           buffer[4] == "U" && buffer[5] == "S";
        end
    endfunction

    function match_start;
        input unused;
        begin
            match_start = line_len == 10 && buffer[0] == "D" && buffer[1] == "E" && buffer[2] == "M" && buffer[3] == "O" &&
                          buffer[4] == "_" && buffer[5] == "S" && buffer[6] == "T" && buffer[7] == "A" &&
                          buffer[8] == "R" && buffer[9] == "T";
        end
    endfunction

    function match_stop;
        input unused;
        begin
            match_stop = line_len == 9 && buffer[0] == "D" && buffer[1] == "E" && buffer[2] == "M" && buffer[3] == "O" &&
                         buffer[4] == "_" && buffer[5] == "S" && buffer[6] == "T" && buffer[7] == "O" && buffer[8] == "P";
        end
    endfunction

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) rx_inst (
        .clk(Clock), .reset(reset), .rx(UART_RX), .data(rx_data), .data_valid(rx_valid), .framing_error(rx_framing_error)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx_inst (
        .clk(Clock), .reset(reset), .tx_start(tx_start), .tx_data(tx_data), .tx(UART_TX), .tx_busy(tx_busy)
    );

    always @(posedge Clock) begin
        if (reset) begin
            if (reset_count == 5'd16) begin
                reset <= 1'b0;
            end else begin
                reset_count <= reset_count + 5'd1;
            end
        end
    end

    always @(posedge Clock) begin
        if (reset) begin
            heartbeat_count <= 32'd0;
            heartbeat_led <= 1'b0;
            frame_count <= 32'd0;
        end else begin
            frame_count <= frame_count + 32'd1;
            if (heartbeat_count == HEARTBEAT_TOGGLE_CYCLES - 1) begin
                heartbeat_count <= 32'd0;
                heartbeat_led <= ~heartbeat_led;
            end else begin
                heartbeat_count <= heartbeat_count + 32'd1;
            end
        end
    end

    always @(posedge Clock) begin
        if (reset) begin
            tx_start <= 1'b0;
            tx_data <= 8'd0;
            boot_active <= 1'b1;
            boot_index <= 5'd0;
            boot_state <= 2'd0;
            response <= RESP_NONE;
            response_index <= 6'd0;
            line_len <= 6'd0;
            render_mode <= 4'd0;
            debug_mode <= 2'd0;
            precision_level <= 2'd3;
            sync_active <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (boot_active) begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= boot_byte(boot_index);
                    tx_start <= 1'b1;
                    if (boot_index == BOOT_MESSAGE_LEN - 1) begin
                        boot_active <= 1'b0;
                        boot_index <= 5'd0;
                    end else begin
                        boot_index <= boot_index + 5'd1;
                    end
                end
            end else if (response != RESP_NONE) begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= response_byte(response, response_index);
                    tx_start <= 1'b1;
                    if (response_index == response_len(response) - 1) begin
                        response <= RESP_NONE;
                        response_index <= 6'd0;
                    end else begin
                        response_index <= response_index + 6'd1;
                    end
                end
            end else if (rx_valid) begin
                if (rx_data == 8'h0d) begin
                end else if (rx_data == 8'h0a) begin
                    if (match_ping(1'b0)) begin
                        response <= RESP_PONG;
                    end else if (match_version(1'b0)) begin
                        response <= RESP_VERSION;
                    end else if (match_status(1'b0)) begin
                        response <= RESP_STATUS;
                    end else if (match_start(1'b0)) begin
                        sync_active <= 1'b1;
                        response <= RESP_OK;
                    end else if (match_stop(1'b0)) begin
                        sync_active <= 1'b0;
                        response <= RESP_OK;
                    end else if (line_len == 6'd6 && buffer[0] == "M" && buffer[1] == "O" && buffer[2] == "D" &&
                                 buffer[3] == "E" && buffer[4] == " " && buffer[5] >= "0" && buffer[5] <= "8") begin
                        render_mode <= buffer[5][3:0];
                        response <= RESP_OK;
                    end else if (line_len == 6'd7 && buffer[0] == "D" && buffer[1] == "E" && buffer[2] == "B" &&
                                 buffer[3] == "U" && buffer[4] == "G" && buffer[5] == " " && buffer[6] >= "0" && buffer[6] <= "2") begin
                        debug_mode <= buffer[6][1:0];
                        response <= RESP_OK;
                    end else if (line_len == 6'd11 && buffer[0] == "P" && buffer[1] == "R" && buffer[2] == "E" &&
                                 buffer[3] == "C" && buffer[4] == "I" && buffer[5] == "S" && buffer[6] == "I" &&
                                 buffer[7] == "O" && buffer[8] == "N" && buffer[9] == " " && buffer[10] >= "0" && buffer[10] <= "3") begin
                        precision_level <= buffer[10][1:0];
                        response <= RESP_OK;
                    end else begin
                        response <= RESP_ERR;
                    end
                    line_len <= 6'd0;
                end else if (line_len < 6'd32) begin
                    buffer[line_len] <= rx_data;
                    line_len <= line_len + 6'd1;
                end
            end
        end
    end
endmodule
