`timescale 1ns / 1ps

module response_formatter (
    input wire clk,
    input wire reset,
    input wire response_start,
    input wire [2:0] response_type,
    input wire [31:0] count,
    input wire [31:0] frame_count,
    input wire [3:0] render_mode,
    input wire [1:0] debug_mode,
    input wire [1:0] precision_level,
    input wire sync_active,
    input wire [2:0] error_code,
    input wire uart_tx_busy,
    output reg tx_start,
    output reg [7:0] tx_data,
    output reg response_busy
);

    localparam [2:0] RESP_PONG    = 3'd1;
    localparam [2:0] RESP_VERSION = 3'd2;
    localparam [2:0] RESP_OK      = 3'd3;
    localparam [2:0] RESP_COUNT   = 3'd4;
    localparam [2:0] RESP_ERR     = 3'd5;
    localparam [2:0] RESP_HELP    = 3'd6;
    localparam [2:0] RESP_STATUS  = 3'd7;

    localparam [2:0] ERR_UNKNOWN_CMD   = 3'd1;
    localparam [2:0] ERR_LONG          = 3'd2;
    localparam [2:0] ERR_BAD_PATTERN   = 3'd3;
    localparam [2:0] ERR_BAD_BASE      = 3'd4;
    localparam [2:0] ERR_NO_PATTERN    = 3'd5;
    localparam [2:0] ERR_NOT_STREAMING = 3'd6;
    localparam [2:0] ERR_BAD_ARG       = 3'd7;

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_SEND = 2'd1;
    localparam [1:0] STATE_WAIT_BUSY = 2'd2;
    localparam [1:0] STATE_NEXT = 2'd3;

    reg [1:0] state = STATE_IDLE;
    reg [7:0] buffer [0:63];
    reg [6:0] length = 7'd0;
    reg [6:0] index = 7'd0;
    integer i;
    integer out_idx;
    reg started;
    reg [31:0] power;
    reg [31:0] digit;
    reg [31:0] tmp_value;

    function [7:0] hex_digit;
        input [3:0] value;
        begin
            hex_digit = (value < 4'd10) ? ("0" + value) : ("a" + value - 4'd10);
        end
    endfunction

    task clear_buffer;
        begin
            for (i = 0; i < 64; i = i + 1) begin
                buffer[i] = 8'h00;
            end
        end
    endtask

    task put_error;
        input [2:0] code;
        begin
            buffer[0] = "E";
            buffer[1] = "R";
            buffer[2] = "R";
            buffer[3] = " ";
            case (code)
                ERR_LONG: begin
                    buffer[4] = "L"; buffer[5] = "O"; buffer[6] = "N"; buffer[7] = "G";
                    buffer[8] = 8'h0a; length = 7'd9;
                end
                ERR_BAD_PATTERN: begin
                    buffer[4] = "B"; buffer[5] = "A"; buffer[6] = "D"; buffer[7] = "_";
                    buffer[8] = "P"; buffer[9] = "A"; buffer[10] = "T"; buffer[11] = "T";
                    buffer[12] = "E"; buffer[13] = "R"; buffer[14] = "N";
                    buffer[15] = 8'h0a; length = 7'd16;
                end
                ERR_BAD_BASE: begin
                    buffer[4] = "B"; buffer[5] = "A"; buffer[6] = "D"; buffer[7] = "_";
                    buffer[8] = "B"; buffer[9] = "A"; buffer[10] = "S"; buffer[11] = "E";
                    buffer[12] = 8'h0a; length = 7'd13;
                end
                ERR_NO_PATTERN: begin
                    buffer[4] = "N"; buffer[5] = "O"; buffer[6] = "_"; buffer[7] = "P";
                    buffer[8] = "A"; buffer[9] = "T"; buffer[10] = "T"; buffer[11] = "E";
                    buffer[12] = "R"; buffer[13] = "N";
                    buffer[14] = 8'h0a; length = 7'd15;
                end
                ERR_NOT_STREAMING: begin
                    buffer[4] = "N"; buffer[5] = "O"; buffer[6] = "T"; buffer[7] = "_";
                    buffer[8] = "S"; buffer[9] = "T"; buffer[10] = "R"; buffer[11] = "E";
                    buffer[12] = "A"; buffer[13] = "M"; buffer[14] = "I"; buffer[15] = "N";
                    buffer[16] = "G";
                    buffer[17] = 8'h0a; length = 7'd18;
                end
                ERR_BAD_ARG: begin
                    buffer[4] = "B"; buffer[5] = "A"; buffer[6] = "D"; buffer[7] = "_";
                    buffer[8] = "A"; buffer[9] = "R"; buffer[10] = "G";
                    buffer[11] = 8'h0a; length = 7'd12;
                end
                default: begin
                    buffer[4] = "U"; buffer[5] = "N"; buffer[6] = "K"; buffer[7] = "N";
                    buffer[8] = "O"; buffer[9] = "W"; buffer[10] = "N"; buffer[11] = "_";
                    buffer[12] = "C"; buffer[13] = "M"; buffer[14] = "D";
                    buffer[15] = 8'h0a; length = 7'd16;
                end
            endcase
        end
    endtask

    task append_uint;
        input [31:0] value;
        begin
            if (value == 0) begin
                buffer[out_idx] = "0";
                out_idx = out_idx + 1;
            end else begin
                tmp_value = value;
                started = 1'b0;
                power = 32'd1000000000;
                for (i = 0; i < 10; i = i + 1) begin
                    digit = tmp_value / power;
                    if (digit != 0 || started) begin
                        buffer[out_idx] = "0" + digit[7:0];
                        out_idx = out_idx + 1;
                        started = 1'b1;
                    end
                    tmp_value = tmp_value - digit * power;
                    power = power / 10;
                end
            end
        end
    endtask

    task build_count;
        input [31:0] value;
        begin
            buffer[0] = "C"; buffer[1] = "O"; buffer[2] = "U"; buffer[3] = "N"; buffer[4] = "T"; buffer[5] = " ";
            out_idx = 6;
            if (value == 0) begin
                buffer[out_idx] = "0";
                out_idx = out_idx + 1;
            end else begin
                tmp_value = value;
                started = 1'b0;
                power = 32'd1000000000;
                for (i = 0; i < 10; i = i + 1) begin
                    digit = tmp_value / power;
                    if (digit != 0 || started) begin
                        buffer[out_idx] = "0" + digit[7:0];
                        out_idx = out_idx + 1;
                        started = 1'b1;
                    end
                    tmp_value = tmp_value - digit * power;
                    power = power / 10;
                end
            end
            buffer[out_idx] = 8'h0a;
            length = out_idx[6:0] + 7'd1;
        end
    endtask

    task build_status;
        begin
            buffer[0] = "S"; buffer[1] = "T"; buffer[2] = "A"; buffer[3] = "T"; buffer[4] = "U"; buffer[5] = "S"; buffer[6] = " ";
            buffer[7] = "f"; buffer[8] = "r"; buffer[9] = "a"; buffer[10] = "m"; buffer[11] = "e"; buffer[12] = "=";
            buffer[13] = hex_digit(frame_count[31:28]);
            buffer[14] = hex_digit(frame_count[27:24]);
            buffer[15] = hex_digit(frame_count[23:20]);
            buffer[16] = hex_digit(frame_count[19:16]);
            buffer[17] = hex_digit(frame_count[15:12]);
            buffer[18] = hex_digit(frame_count[11:8]);
            buffer[19] = hex_digit(frame_count[7:4]);
            buffer[20] = hex_digit(frame_count[3:0]);
            buffer[21] = " ";
            buffer[22] = "m"; buffer[23] = "o"; buffer[24] = "d"; buffer[25] = "e"; buffer[26] = "="; buffer[27] = hex_digit(render_mode);
            buffer[28] = " ";
            buffer[29] = "d"; buffer[30] = "e"; buffer[31] = "b"; buffer[32] = "u"; buffer[33] = "g"; buffer[34] = "="; buffer[35] = hex_digit({2'd0, debug_mode});
            buffer[36] = " ";
            buffer[37] = "p"; buffer[38] = "r"; buffer[39] = "e"; buffer[40] = "c"; buffer[41] = "="; buffer[42] = hex_digit({2'd0, precision_level});
            buffer[43] = " ";
            buffer[44] = "s"; buffer[45] = "y"; buffer[46] = "n"; buffer[47] = "c"; buffer[48] = "="; buffer[49] = sync_active ? "1" : "0";
            buffer[50] = 8'h0a;
            length = 7'd51;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            tx_start <= 1'b0;
            tx_data <= 8'd0;
            response_busy <= 1'b0;
            length <= 7'd0;
            index <= 7'd0;
        end else begin
            tx_start <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    response_busy <= 1'b0;
                    index <= 7'd0;
                    if (response_start) begin
                        clear_buffer();
                        case (response_type)
                            RESP_PONG: begin
                                buffer[0] = "P"; buffer[1] = "O"; buffer[2] = "N"; buffer[3] = "G"; buffer[4] = 8'h0a;
                                length = 7'd5;
                            end
                            RESP_VERSION: begin
                                buffer[0] = "V"; buffer[1] = "E"; buffer[2] = "R"; buffer[3] = "S"; buffer[4] = "I"; buffer[5] = "O"; buffer[6] = "N"; buffer[7] = " ";
                                buffer[8] = "T"; buffer[9] = "A"; buffer[10] = "N"; buffer[11] = "G"; buffer[12] = "2"; buffer[13] = "0"; buffer[14] = "K"; buffer[15] = " ";
                                buffer[16] = "R"; buffer[17] = "E"; buffer[18] = "N"; buffer[19] = "D"; buffer[20] = "E"; buffer[21] = "R"; buffer[22] = "D"; buffer[23] = "E"; buffer[24] = "M"; buffer[25] = "O"; buffer[26] = " ";
                                buffer[27] = "V"; buffer[28] = "0"; buffer[29] = 8'h0a;
                                length = 7'd30;
                            end
                            RESP_OK: begin
                                buffer[0] = "O"; buffer[1] = "K"; buffer[2] = 8'h0a;
                                length = 7'd3;
                            end
                            RESP_COUNT: begin
                                build_count(count);
                            end
                            RESP_HELP: begin
                                buffer[0] = "P"; buffer[1] = "I"; buffer[2] = "N"; buffer[3] = "G"; buffer[4] = " ";
                                buffer[5] = "V"; buffer[6] = "E"; buffer[7] = "R"; buffer[8] = "S"; buffer[9] = "I"; buffer[10] = "O"; buffer[11] = "N"; buffer[12] = " ";
                                buffer[13] = "R"; buffer[14] = "E"; buffer[15] = "S"; buffer[16] = "E"; buffer[17] = "T"; buffer[18] = " ";
                                buffer[19] = "S"; buffer[20] = "E"; buffer[21] = "T"; buffer[22] = "P"; buffer[23] = "A"; buffer[24] = "T"; buffer[25] = " ";
                                buffer[26] = "C"; buffer[27] = "O"; buffer[28] = "U"; buffer[29] = "N"; buffer[30] = "T"; buffer[31] = " ";
                                buffer[32] = "M"; buffer[33] = "O"; buffer[34] = "D"; buffer[35] = "E"; buffer[36] = " ";
                                buffer[37] = "D"; buffer[38] = "E"; buffer[39] = "B"; buffer[40] = "U"; buffer[41] = "G"; buffer[42] = " ";
                                buffer[43] = "S"; buffer[44] = "T"; buffer[45] = "A"; buffer[46] = "T"; buffer[47] = "U"; buffer[48] = "S"; buffer[49] = 8'h0a;
                                length = 7'd50;
                            end
                            RESP_STATUS: begin
                                build_status();
                            end
                            default: begin
                                put_error(error_code);
                            end
                        endcase
                        response_busy <= 1'b1;
                        state <= STATE_SEND;
                    end
                end

                STATE_SEND: begin
                    response_busy <= 1'b1;
                    if (!uart_tx_busy) begin
                        tx_data <= buffer[index];
                        tx_start <= 1'b1;
                        state <= STATE_WAIT_BUSY;
                    end
                end

                STATE_WAIT_BUSY: begin
                    response_busy <= 1'b1;
                    if (uart_tx_busy) begin
                        state <= STATE_NEXT;
                    end
                end

                STATE_NEXT: begin
                    response_busy <= 1'b1;
                    if (!uart_tx_busy) begin
                        if (index == length - 1) begin
                            state <= STATE_IDLE;
                        end else begin
                            index <= index + 7'd1;
                            state <= STATE_SEND;
                        end
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    response_busy <= 1'b0;
                    tx_start <= 1'b0;
                end
            endcase
        end
    end

endmodule
