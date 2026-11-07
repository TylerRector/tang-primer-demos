`timescale 1ns / 1ps

module command_parser #(
    parameter integer COMMAND_BUFFER_BYTES = 128,
    parameter integer K = 8
) (
    input wire clk,
    input wire reset,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire response_busy,
    input wire pattern_loaded,
    output reg cmd_ping,
    output reg cmd_version,
    output reg cmd_reset,
    output reg cmd_demo_start,
    output reg cmd_demo_stop,
    output reg cmd_status,
    output reg cmd_mode,
    output reg [3:0] mode_value,
    output reg cmd_debug,
    output reg [1:0] debug_value,
    output reg cmd_precision,
    output reg [1:0] precision_value,
    output reg clear_pattern,
    output reg clear_count,
    output reg clear_window,
    output reg pattern_base_valid,
    output reg [1:0] pattern_base,
    output reg cmd_count_begin,
    output reg cmd_count_base_valid,
    output reg [1:0] cmd_count_base,
    output reg cmd_count_done,
    output reg response_request,
    output reg [2:0] response_type,
    output reg [2:0] error_code
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

    localparam [2:0] STATE_COLLECT      = 3'd0;
    localparam [2:0] STATE_EMIT_PATTERN = 3'd1;
    localparam [2:0] STATE_COUNT_BEGIN  = 3'd2;
    localparam [2:0] STATE_EMIT_COUNT   = 3'd3;
    localparam [2:0] STATE_COUNT_DONE   = 3'd4;
    localparam [2:0] STATE_RESPOND      = 3'd5;
    localparam [2:0] STATE_EMIT_STREAM  = 3'd6;
    localparam [2:0] STATE_STREAM_DONE  = 3'd7;

    reg [2:0] state = STATE_COLLECT;
    reg [7:0] buffer [0:COMMAND_BUFFER_BYTES-1];
    reg [7:0] line_len = 8'd0;
    reg overlong = 1'b0;
    reg [7:0] emit_index = 8'd0;
    reg [7:0] emit_len = 8'd0;
    reg [2:0] pending_response = 3'd0;
    reg [2:0] pending_error = 3'd0;
    reg stream_active = 1'b0;
    reg stream_quiet = 1'b0;

    integer i;
    reg dna_ok;

    function is_base;
        input [7:0] ch;
        begin
            is_base = (ch == "A" || ch == "C" || ch == "G" || ch == "T");
        end
    endfunction

    function [1:0] encode_base;
        input [7:0] ch;
        begin
            case (ch)
                "A": encode_base = 2'b00;
                "C": encode_base = 2'b01;
                "G": encode_base = 2'b10;
                "T": encode_base = 2'b11;
                default: encode_base = 2'b00;
            endcase
        end
    endfunction

    function match_ping;
        input unused;
        begin
            match_ping = (line_len == 4 && buffer[0] == "P" && buffer[1] == "I" &&
                          buffer[2] == "N" && buffer[3] == "G");
        end
    endfunction

    function match_version;
        input unused;
        begin
            match_version = (line_len == 7 && buffer[0] == "V" && buffer[1] == "E" &&
                             buffer[2] == "R" && buffer[3] == "S" && buffer[4] == "I" &&
                             buffer[5] == "O" && buffer[6] == "N");
        end
    endfunction

    function match_reset;
        input unused;
        begin
            match_reset = (line_len == 5 && buffer[0] == "R" && buffer[1] == "E" &&
                           buffer[2] == "S" && buffer[3] == "E" && buffer[4] == "T");
        end
    endfunction

    function match_help;
        input unused;
        begin
            match_help = (line_len == 4 && buffer[0] == "H" && buffer[1] == "E" &&
                          buffer[2] == "L" && buffer[3] == "P");
        end
    endfunction

    function prefix_setpat;
        input unused;
        begin
            prefix_setpat = (line_len >= 7 && buffer[0] == "S" && buffer[1] == "E" &&
                             buffer[2] == "T" && buffer[3] == "P" && buffer[4] == "A" &&
                             buffer[5] == "T" && buffer[6] == " ");
        end
    endfunction

    function prefix_count;
        input unused;
        begin
            prefix_count = (line_len >= 6 && buffer[0] == "C" && buffer[1] == "O" &&
                            buffer[2] == "U" && buffer[3] == "N" && buffer[4] == "T" &&
                            buffer[5] == " ");
        end
    endfunction

    function match_stream_begin;
        input unused;
        begin
            match_stream_begin = (line_len == 12 && buffer[0] == "S" && buffer[1] == "T" &&
                                  buffer[2] == "R" && buffer[3] == "E" && buffer[4] == "A" &&
                                  buffer[5] == "M" && buffer[6] == "_" && buffer[7] == "B" &&
                                  buffer[8] == "E" && buffer[9] == "G" && buffer[10] == "I" &&
                                  buffer[11] == "N");
        end
    endfunction

    function match_stream_begin_quiet;
        input unused;
        begin
            match_stream_begin_quiet = (line_len == 18 && buffer[0] == "S" && buffer[1] == "T" &&
                                        buffer[2] == "R" && buffer[3] == "E" && buffer[4] == "A" &&
                                        buffer[5] == "M" && buffer[6] == "_" && buffer[7] == "B" &&
                                        buffer[8] == "E" && buffer[9] == "G" && buffer[10] == "I" &&
                                        buffer[11] == "N" && buffer[12] == "_" && buffer[13] == "Q" &&
                                        buffer[14] == "U" && buffer[15] == "I" && buffer[16] == "E" &&
                                        buffer[17] == "T");
        end
    endfunction

    function match_stream_end;
        input unused;
        begin
            match_stream_end = (line_len == 10 && buffer[0] == "S" && buffer[1] == "T" &&
                                buffer[2] == "R" && buffer[3] == "E" && buffer[4] == "A" &&
                                buffer[5] == "M" && buffer[6] == "_" && buffer[7] == "E" &&
                                buffer[8] == "N" && buffer[9] == "D");
        end
    endfunction

    function prefix_stream;
        input unused;
        begin
            prefix_stream = (line_len >= 7 && buffer[0] == "S" && buffer[1] == "T" &&
                             buffer[2] == "R" && buffer[3] == "E" && buffer[4] == "A" &&
                             buffer[5] == "M" && buffer[6] == " ");
        end
    endfunction

    function is_digit;
        input [7:0] ch;
        begin
            is_digit = (ch >= "0" && ch <= "9");
        end
    endfunction

    function match_demo_start;
        input unused;
        begin
            match_demo_start = (line_len == 10 && buffer[0] == "D" && buffer[1] == "E" &&
                                buffer[2] == "M" && buffer[3] == "O" && buffer[4] == "_" &&
                                buffer[5] == "S" && buffer[6] == "T" && buffer[7] == "A" &&
                                buffer[8] == "R" && buffer[9] == "T");
        end
    endfunction

    function match_demo_stop;
        input unused;
        begin
            match_demo_stop = (line_len == 9 && buffer[0] == "D" && buffer[1] == "E" &&
                               buffer[2] == "M" && buffer[3] == "O" && buffer[4] == "_" &&
                               buffer[5] == "S" && buffer[6] == "T" && buffer[7] == "O" &&
                               buffer[8] == "P");
        end
    endfunction

    function match_status;
        input unused;
        begin
            match_status = (line_len == 6 && buffer[0] == "S" && buffer[1] == "T" &&
                            buffer[2] == "A" && buffer[3] == "T" && buffer[4] == "U" &&
                            buffer[5] == "S");
        end
    endfunction

    function prefix_mode;
        input unused;
        begin
            prefix_mode = (line_len == 6 && buffer[0] == "M" && buffer[1] == "O" &&
                           buffer[2] == "D" && buffer[3] == "E" && buffer[4] == " ");
        end
    endfunction

    function prefix_debug;
        input unused;
        begin
            prefix_debug = (line_len == 7 && buffer[0] == "D" && buffer[1] == "E" &&
                            buffer[2] == "B" && buffer[3] == "U" && buffer[4] == "G" &&
                            buffer[5] == " ");
        end
    endfunction

    function prefix_precision;
        input unused;
        begin
            prefix_precision = (line_len == 11 && buffer[0] == "P" && buffer[1] == "R" &&
                                buffer[2] == "E" && buffer[3] == "C" && buffer[4] == "I" &&
                                buffer[5] == "S" && buffer[6] == "I" && buffer[7] == "O" &&
                                buffer[8] == "N" && buffer[9] == " ");
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_COLLECT;
            line_len <= 8'd0;
            overlong <= 1'b0;
            emit_index <= 8'd0;
            emit_len <= 8'd0;
            pending_response <= 3'd0;
            pending_error <= 3'd0;
            stream_active <= 1'b0;
            stream_quiet <= 1'b0;
            cmd_ping <= 1'b0;
            cmd_version <= 1'b0;
            cmd_reset <= 1'b0;
            cmd_demo_start <= 1'b0;
            cmd_demo_stop <= 1'b0;
            cmd_status <= 1'b0;
            cmd_mode <= 1'b0;
            mode_value <= 4'd0;
            cmd_debug <= 1'b0;
            debug_value <= 2'd0;
            cmd_precision <= 1'b0;
            precision_value <= 2'd0;
            clear_pattern <= 1'b0;
            clear_count <= 1'b0;
            clear_window <= 1'b0;
            pattern_base_valid <= 1'b0;
            pattern_base <= 2'b00;
            cmd_count_begin <= 1'b0;
            cmd_count_base_valid <= 1'b0;
            cmd_count_base <= 2'b00;
            cmd_count_done <= 1'b0;
            response_request <= 1'b0;
            response_type <= 3'd0;
            error_code <= 3'd0;
        end else begin
            cmd_ping <= 1'b0;
            cmd_version <= 1'b0;
            cmd_reset <= 1'b0;
            cmd_demo_start <= 1'b0;
            cmd_demo_stop <= 1'b0;
            cmd_status <= 1'b0;
            cmd_mode <= 1'b0;
            cmd_debug <= 1'b0;
            cmd_precision <= 1'b0;
            clear_pattern <= 1'b0;
            clear_count <= 1'b0;
            clear_window <= 1'b0;
            pattern_base_valid <= 1'b0;
            cmd_count_begin <= 1'b0;
            cmd_count_base_valid <= 1'b0;
            cmd_count_done <= 1'b0;
            response_request <= 1'b0;

            case (state)
                STATE_COLLECT: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h0d) begin
                        end else if (rx_data == 8'h0a) begin
                            if (overlong) begin
                                pending_response <= RESP_ERR;
                                pending_error <= ERR_LONG;
                                state <= STATE_RESPOND;
                            end else if (line_len == 0) begin
                                pending_response <= RESP_ERR;
                                pending_error <= ERR_UNKNOWN_CMD;
                                state <= STATE_RESPOND;
                            end else if (match_ping(1'b0)) begin
                                cmd_ping <= 1'b1;
                                pending_response <= RESP_PONG;
                                pending_error <= 3'd0;
                                state <= STATE_RESPOND;
                            end else if (match_version(1'b0)) begin
                                cmd_version <= 1'b1;
                                pending_response <= RESP_VERSION;
                                pending_error <= 3'd0;
                                state <= STATE_RESPOND;
                            end else if (match_help(1'b0)) begin
                                pending_response <= RESP_HELP;
                                pending_error <= 3'd0;
                                state <= STATE_RESPOND;
                            end else if (match_status(1'b0)) begin
                                cmd_status <= 1'b1;
                                pending_response <= RESP_STATUS;
                                pending_error <= 3'd0;
                                state <= STATE_RESPOND;
                            end else if (match_demo_start(1'b0)) begin
                                cmd_demo_start <= 1'b1;
                                pending_response <= RESP_OK;
                                pending_error <= 3'd0;
                                state <= STATE_RESPOND;
                            end else if (match_demo_stop(1'b0)) begin
                                cmd_demo_stop <= 1'b1;
                                pending_response <= RESP_OK;
                                pending_error <= 3'd0;
                                state <= STATE_RESPOND;
                            end else if (prefix_mode(1'b0)) begin
                                if (!is_digit(buffer[5]) || buffer[5] > "8") begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_BAD_ARG;
                                end else begin
                                    mode_value <= buffer[5][3:0];
                                    cmd_mode <= 1'b1;
                                    pending_response <= RESP_OK;
                                    pending_error <= 3'd0;
                                end
                                state <= STATE_RESPOND;
                            end else if (prefix_debug(1'b0)) begin
                                if (!is_digit(buffer[6]) || buffer[6] > "2") begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_BAD_ARG;
                                end else begin
                                    debug_value <= buffer[6][1:0];
                                    cmd_debug <= 1'b1;
                                    pending_response <= RESP_OK;
                                    pending_error <= 3'd0;
                                end
                                state <= STATE_RESPOND;
                            end else if (prefix_precision(1'b0)) begin
                                if (!is_digit(buffer[10]) || buffer[10] > "3") begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_BAD_ARG;
                                end else begin
                                    precision_value <= buffer[10][1:0];
                                    cmd_precision <= 1'b1;
                                    pending_response <= RESP_OK;
                                    pending_error <= 3'd0;
                                end
                                state <= STATE_RESPOND;
                            end else if (match_reset(1'b0)) begin
                                cmd_reset <= 1'b1;
                                clear_pattern <= 1'b1;
                                clear_count <= 1'b1;
                                clear_window <= 1'b1;
                                stream_active <= 1'b0;
                                stream_quiet <= 1'b0;
                                pending_response <= RESP_OK;
                                pending_error <= 3'd0;
                                state <= STATE_RESPOND;
                            end else if (prefix_setpat(1'b0)) begin
                                if (line_len != 7 + K) begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_BAD_PATTERN;
                                    state <= STATE_RESPOND;
                                end else begin
                                    dna_ok = 1'b1;
                                    for (i = 0; i < K; i = i + 1) begin
                                        if (!is_base(buffer[7+i])) begin
                                            dna_ok = 1'b0;
                                        end
                                    end
                                    if (!dna_ok) begin
                                        pending_response <= RESP_ERR;
                                        pending_error <= ERR_BAD_PATTERN;
                                        state <= STATE_RESPOND;
                                    end else begin
                                        clear_pattern <= 1'b1;
                                        stream_active <= 1'b0;
                                        stream_quiet <= 1'b0;
                                        emit_index <= 8'd0;
                                        emit_len <= K;
                                        state <= STATE_EMIT_PATTERN;
                                    end
                                end
                            end else if (prefix_count(1'b0)) begin
                                if (!pattern_loaded) begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_NO_PATTERN;
                                    state <= STATE_RESPOND;
                                end else if (line_len == 6) begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_BAD_BASE;
                                    state <= STATE_RESPOND;
                                end else begin
                                    dna_ok = 1'b1;
                                    for (i = 6; i < COMMAND_BUFFER_BYTES; i = i + 1) begin
                                        if (i < line_len && !is_base(buffer[i])) begin
                                            dna_ok = 1'b0;
                                        end
                                    end
                                    if (!dna_ok) begin
                                        pending_response <= RESP_ERR;
                                        pending_error <= ERR_BAD_BASE;
                                        state <= STATE_RESPOND;
                                    end else begin
                                        emit_index <= 8'd0;
                                        emit_len <= line_len - 8'd6;
                                        state <= STATE_COUNT_BEGIN;
                                    end
                                end
                            end else if (match_stream_begin(1'b0) || match_stream_begin_quiet(1'b0)) begin
                                if (!pattern_loaded) begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_NO_PATTERN;
                                    state <= STATE_RESPOND;
                                end else begin
                                    clear_count <= 1'b1;
                                    clear_window <= 1'b1;
                                    stream_active <= 1'b1;
                                    stream_quiet <= match_stream_begin_quiet(1'b0);
                                    pending_response <= RESP_OK;
                                    pending_error <= 3'd0;
                                    state <= STATE_RESPOND;
                                end
                            end else if (match_stream_end(1'b0)) begin
                                if (!stream_active) begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_NOT_STREAMING;
                                    state <= STATE_RESPOND;
                                end else begin
                                    stream_active <= 1'b0;
                                    stream_quiet <= 1'b0;
                                    pending_response <= RESP_COUNT;
                                    pending_error <= 3'd0;
                                    state <= STATE_RESPOND;
                                end
                            end else if (prefix_stream(1'b0)) begin
                                if (!stream_active) begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_NOT_STREAMING;
                                    state <= STATE_RESPOND;
                                end else if (line_len == 7) begin
                                    pending_response <= RESP_ERR;
                                    pending_error <= ERR_BAD_BASE;
                                    state <= STATE_RESPOND;
                                end else begin
                                    dna_ok = 1'b1;
                                    for (i = 7; i < COMMAND_BUFFER_BYTES; i = i + 1) begin
                                        if (i < line_len && !is_base(buffer[i])) begin
                                            dna_ok = 1'b0;
                                        end
                                    end
                                    if (!dna_ok) begin
                                        stream_active <= 1'b0;
                                        stream_quiet <= 1'b0;
                                        pending_response <= RESP_ERR;
                                        pending_error <= ERR_BAD_BASE;
                                        state <= STATE_RESPOND;
                                    end else begin
                                        emit_index <= 8'd0;
                                        emit_len <= line_len - 8'd7;
                                        state <= STATE_EMIT_STREAM;
                                    end
                                end
                            end else begin
                                pending_response <= RESP_ERR;
                                pending_error <= ERR_UNKNOWN_CMD;
                                state <= STATE_RESPOND;
                            end

                            line_len <= 8'd0;
                            overlong <= 1'b0;
                        end else if (line_len < COMMAND_BUFFER_BYTES) begin
                            buffer[line_len] <= rx_data;
                            line_len <= line_len + 8'd1;
                        end else begin
                            overlong <= 1'b1;
                        end
                    end
                end

                STATE_EMIT_PATTERN: begin
                    pattern_base <= encode_base(buffer[7 + emit_index]);
                    pattern_base_valid <= 1'b1;
                    if (emit_index == emit_len - 1) begin
                        pending_response <= RESP_OK;
                        pending_error <= 3'd0;
                        state <= STATE_RESPOND;
                    end
                    emit_index <= emit_index + 8'd1;
                end

                STATE_COUNT_BEGIN: begin
                    clear_count <= 1'b1;
                    clear_window <= 1'b1;
                    cmd_count_begin <= 1'b1;
                    emit_index <= 8'd0;
                    state <= STATE_EMIT_COUNT;
                end

                STATE_EMIT_COUNT: begin
                    cmd_count_base <= encode_base(buffer[6 + emit_index]);
                    cmd_count_base_valid <= 1'b1;
                    if (emit_index == emit_len - 1) begin
                        state <= STATE_COUNT_DONE;
                    end
                    emit_index <= emit_index + 8'd1;
                end

                STATE_COUNT_DONE: begin
                    cmd_count_done <= 1'b1;
                    pending_response <= RESP_COUNT;
                    pending_error <= 3'd0;
                    state <= STATE_RESPOND;
                end

                STATE_EMIT_STREAM: begin
                    cmd_count_base <= encode_base(buffer[7 + emit_index]);
                    cmd_count_base_valid <= 1'b1;
                    if (emit_index == emit_len - 1) begin
                        state <= STATE_STREAM_DONE;
                    end
                    emit_index <= emit_index + 8'd1;
                end

                STATE_STREAM_DONE: begin
                    if (stream_quiet) begin
                        state <= STATE_COLLECT;
                    end else begin
                        pending_response <= RESP_OK;
                        pending_error <= 3'd0;
                        state <= STATE_RESPOND;
                    end
                end

                STATE_RESPOND: begin
                    if (!response_busy) begin
                        response_type <= pending_response;
                        error_code <= pending_error;
                        response_request <= 1'b1;
                        state <= STATE_COLLECT;
                    end
                end

                default: begin
                    state <= STATE_COLLECT;
                    line_len <= 8'd0;
                    overlong <= 1'b0;
                end
            endcase
        end
    end

endmodule
