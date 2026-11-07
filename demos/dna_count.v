`timescale 1ns / 1ps

module dna_count #(
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
    localparam integer K = 8;
    localparam integer BOOT_MESSAGE_LEN = 28;

    reg reset = 1'b1;
    reg [4:0] reset_count = 5'd0;

    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_framing_error;

    wire parser_response_request;
    wire [2:0] parser_response_type;
    wire [2:0] parser_error_code;
    wire parser_busy_feedback;
    wire cmd_reset;
    wire cmd_demo_start;
    wire cmd_demo_stop;
    wire cmd_status;
    wire cmd_mode;
    wire [3:0] mode_value;
    wire cmd_debug;
    wire [1:0] debug_value;
    wire cmd_precision;
    wire [1:0] precision_value;
    wire clear_pattern_from_parser;
    wire clear_count_from_parser;
    wire clear_window_from_parser;
    wire pattern_base_valid;
    wire [1:0] pattern_base;
    wire count_base_valid;
    wire [1:0] count_base;

    wire [2*K-1:0] kmer_window;
    wire valid_window;
    wire pattern_loaded;
    wire match_pulse;
    wire [31:0] match_count;

    wire formatter_tx_start;
    wire [7:0] formatter_tx_data;
    wire formatter_busy;
    wire tx_busy;
    wire heartbeat_led;
    wire rx_activity_led;
    wire count_active_led;
    wire match_seen_led;
    wire error_led;

    reg boot_active = 1'b1;
    reg [5:0] boot_index = 6'd0;
    reg boot_tx_start = 1'b0;
    reg [7:0] boot_tx_data = 8'd0;
    reg [1:0] boot_state = 2'd0;
    reg count_base_valid_d = 1'b0;
    reg [31:0] render_frame_count = 32'd0;
    reg [3:0] render_mode = 4'd0;
    reg [1:0] render_debug = 2'd0;
    reg [1:0] render_precision = 2'd3;
    reg render_sync_active = 1'b0;

    wire uart_tx_start = boot_active ? boot_tx_start : formatter_tx_start;
    wire [7:0] uart_tx_data = boot_active ? boot_tx_data : formatter_tx_data;
    wire clear_pattern = clear_pattern_from_parser | cmd_reset;
    wire clear_count = clear_count_from_parser | cmd_reset;
    wire clear_window = clear_window_from_parser | cmd_reset;
    wire protocol_error = parser_response_request && parser_response_type == 3'd5;

    assign IO_voltage = heartbeat_led;

    function [7:0] boot_message_byte;
        input [5:0] index;
        begin
            case (index)
                6'd0:  boot_message_byte = "H";
                6'd1:  boot_message_byte = "E";
                6'd2:  boot_message_byte = "L";
                6'd3:  boot_message_byte = "L";
                6'd4:  boot_message_byte = "O";
                6'd5:  boot_message_byte = " ";
                6'd6:  boot_message_byte = "F";
                6'd7:  boot_message_byte = "R";
                6'd8:  boot_message_byte = "O";
                6'd9:  boot_message_byte = "M";
                6'd10: boot_message_byte = " ";
                6'd11: boot_message_byte = "T";
                6'd12: boot_message_byte = "A";
                6'd13: boot_message_byte = "N";
                6'd14: boot_message_byte = "G";
                6'd15: boot_message_byte = " ";
                6'd16: boot_message_byte = "P";
                6'd17: boot_message_byte = "R";
                6'd18: boot_message_byte = "I";
                6'd19: boot_message_byte = "M";
                6'd20: boot_message_byte = "E";
                6'd21: boot_message_byte = "R";
                6'd22: boot_message_byte = " ";
                6'd23: boot_message_byte = "2";
                6'd24: boot_message_byte = "0";
                6'd25: boot_message_byte = "K";
                6'd26: boot_message_byte = 8'h0d;
                6'd27: boot_message_byte = 8'h0a;
                default: boot_message_byte = 8'h20;
            endcase
        end
    endfunction

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) uart_rx_inst (
        .clk(Clock),
        .reset(reset),
        .rx(UART_RX),
        .data(rx_data),
        .data_valid(rx_valid),
        .framing_error(rx_framing_error)
    );

    command_parser #(
        .COMMAND_BUFFER_BYTES(128),
        .K(K)
    ) command_parser_inst (
        .clk(Clock),
        .reset(reset),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .response_busy(parser_busy_feedback),
        .pattern_loaded(pattern_loaded),
        .cmd_ping(),
        .cmd_version(),
        .cmd_reset(cmd_reset),
        .cmd_demo_start(cmd_demo_start),
        .cmd_demo_stop(cmd_demo_stop),
        .cmd_status(cmd_status),
        .cmd_mode(cmd_mode),
        .mode_value(mode_value),
        .cmd_debug(cmd_debug),
        .debug_value(debug_value),
        .cmd_precision(cmd_precision),
        .precision_value(precision_value),
        .clear_pattern(clear_pattern_from_parser),
        .clear_count(clear_count_from_parser),
        .clear_window(clear_window_from_parser),
        .pattern_base_valid(pattern_base_valid),
        .pattern_base(pattern_base),
        .cmd_count_begin(),
        .cmd_count_base_valid(count_base_valid),
        .cmd_count_base(count_base),
        .cmd_count_done(),
        .response_request(parser_response_request),
        .response_type(parser_response_type),
        .error_code(parser_error_code)
    );

    kmer_shift_register #(
        .K(K)
    ) kmer_shift_register_inst (
        .clk(Clock),
        .reset(reset),
        .clear(clear_window),
        .base_valid(count_base_valid),
        .base_2bit(count_base),
        .window(kmer_window),
        .valid_window(valid_window)
    );

    exact_match_counter #(
        .K(K),
        .COUNT_WIDTH(32)
    ) exact_match_counter_inst (
        .clk(Clock),
        .reset(reset),
        .clear_count(clear_count),
        .clear_pattern(clear_pattern),
        .pattern_base_valid(pattern_base_valid),
        .pattern_base(pattern_base),
        .window(kmer_window),
        .valid_window(valid_window),
        .window_advance(count_base_valid_d),
        .pattern_loaded(pattern_loaded),
        .match_pulse(match_pulse),
        .count(match_count)
    );

    status_leds #(
        .CLK_HZ(HEARTBEAT_TOGGLE_CYCLES * 2),
        .HEARTBEAT_HZ(1),
        .RX_PULSE_CYCLES(2_700_000),
        .MATCH_PULSE_CYCLES(2_700_000)
    ) status_leds_inst (
        .clk(Clock),
        .rst(reset | cmd_reset),
        .rx_byte_valid(rx_valid),
        .count_active(count_base_valid | count_base_valid_d),
        .match_pulse(match_pulse),
        .protocol_error(protocol_error),
        .heartbeat_led(heartbeat_led),
        .rx_activity_led(rx_activity_led),
        .count_active_led(count_active_led),
        .match_seen_led(match_seen_led),
        .error_led(error_led)
    );

    response_formatter response_formatter_inst (
        .clk(Clock),
        .reset(reset),
        .response_start(parser_response_request),
        .response_type(parser_response_type),
        .count(match_count),
        .frame_count(render_frame_count),
        .render_mode(render_mode),
        .debug_mode(render_debug),
        .precision_level(render_precision),
        .sync_active(render_sync_active),
        .error_code(parser_error_code),
        .uart_tx_busy(tx_busy || boot_active),
        .tx_start(formatter_tx_start),
        .tx_data(formatter_tx_data),
        .response_busy(formatter_busy)
    );

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) uart_tx_inst (
        .clk(Clock),
        .reset(reset),
        .tx_start(uart_tx_start),
        .tx_data(uart_tx_data),
        .tx(UART_TX),
        .tx_busy(tx_busy)
    );

    assign parser_busy_feedback = formatter_busy | boot_active;

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
        if (reset || clear_window) begin
            count_base_valid_d <= 1'b0;
        end else begin
            count_base_valid_d <= count_base_valid;
        end
    end

    always @(posedge Clock) begin
        if (reset || cmd_reset) begin
            render_frame_count <= 32'd0;
            render_mode <= 4'd0;
            render_debug <= 2'd0;
            render_precision <= 2'd3;
            render_sync_active <= 1'b0;
        end else begin
            render_frame_count <= render_frame_count + 32'd1;
            if (cmd_demo_start) begin
                render_sync_active <= 1'b1;
            end
            if (cmd_demo_stop) begin
                render_sync_active <= 1'b0;
            end
            if (cmd_mode) begin
                render_mode <= mode_value;
            end
            if (cmd_debug) begin
                render_debug <= debug_value;
            end
            if (cmd_precision) begin
                render_precision <= precision_value;
            end
        end
    end

    always @(posedge Clock) begin
        if (reset) begin
            boot_active <= 1'b1;
            boot_index <= 6'd0;
            boot_tx_start <= 1'b0;
            boot_tx_data <= 8'd0;
            boot_state <= 2'd0;
        end else begin
            boot_tx_start <= 1'b0;
            if (boot_active) begin
                case (boot_state)
                    2'd0: begin
                        if (!tx_busy) begin
                            boot_tx_data <= boot_message_byte(boot_index);
                            boot_tx_start <= 1'b1;
                            boot_state <= 2'd1;
                        end
                    end
                    2'd1: begin
                        if (tx_busy) begin
                            boot_state <= 2'd2;
                        end
                    end
                    2'd2: begin
                        if (!tx_busy) begin
                            if (boot_index == BOOT_MESSAGE_LEN - 1) begin
                                boot_active <= 1'b0;
                                boot_state <= 2'd0;
                            end else begin
                                boot_index <= boot_index + 6'd1;
                                boot_state <= 2'd0;
                            end
                        end
                    end
                    default: boot_state <= 2'd0;
                endcase
            end
        end
    end

endmodule
