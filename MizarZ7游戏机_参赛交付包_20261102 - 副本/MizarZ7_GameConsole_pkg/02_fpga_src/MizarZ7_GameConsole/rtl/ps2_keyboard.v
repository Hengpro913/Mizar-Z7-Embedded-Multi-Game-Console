`timescale 1ns / 1ps

// PS/2 Set-2 receiver and game key mapper.
// Connect ps2_clk to JP2 pin 3 (G17) and ps2_data to JP2 pin 4 (G18).
// Both lines require 4.7 kOhm pull-ups to 3.3 V.
module ps2_keyboard (
    input  wire clk,
    input  wire rst,
    input  wire ps2_clk,
    input  wire ps2_data,

    output reg  left_held,
    output reg  right_held,
    output reg  up_held,
    output reg  down_held,
    output reg  space_pressed,
    output reg  enter_pressed,
    output reg  pause_pressed,
    output reg  restart_pressed,
    output reg  escape_pressed,
    output reg  frame_error_pulse
);

    reg [2:0] clk_sync;
    reg [2:0] data_sync;
    reg [10:0] shift_reg;
    reg [3:0] bit_count;

    reg [7:0] scan_code;
    reg scan_valid;
    reg extended_code;
    reg release_code;

    reg w_held;
    reg s_held;
    reg a_held;
    reg d_held;
    reg left_arrow_held;
    reg right_arrow_held;
    reg up_arrow_held;
    reg down_arrow_held;
    reg space_held;
    reg enter_held;
    reg p_held;
    reg r_held;
    reg esc_held;

    wire ps2_clk_fall = (clk_sync[2:1] == 2'b10);

    always @(posedge clk) begin
        if (rst) begin
            clk_sync      <= 3'b111;
            data_sync     <= 3'b111;
            shift_reg     <= 11'b0;
            bit_count     <= 4'd0;
            scan_code     <= 8'b0;
            scan_valid    <= 1'b0;
            frame_error_pulse <= 1'b0;
        end else begin
            clk_sync  <= {clk_sync[1:0], ps2_clk};
            data_sync <= {data_sync[1:0], ps2_data};
            scan_valid <= 1'b0;
            frame_error_pulse <= 1'b0;

            if (ps2_clk_fall) begin
                if (bit_count == 4'd0) begin
                    // Start bit must be low.
                    if (!data_sync[2]) begin
                        shift_reg[0] <= 1'b0;
                        bit_count <= 4'd1;
                    end
                end else begin
                    shift_reg[bit_count] <= data_sync[2];
                    if (bit_count == 4'd10) begin
                        bit_count <= 4'd0;
                        // Stop bit is high and the frame uses odd parity.
                        if (data_sync[2] &&
                            (^{shift_reg[8:1], shift_reg[9]} == 1'b1)) begin
                            scan_code  <= shift_reg[8:1];
                            scan_valid <= 1'b1;
                        end else begin
                            frame_error_pulse <= 1'b1;
                        end
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            extended_code <= 1'b0;
            release_code  <= 1'b0;

            w_held              <= 1'b0;
            s_held              <= 1'b0;
            a_held              <= 1'b0;
            d_held              <= 1'b0;
            left_arrow_held     <= 1'b0;
            right_arrow_held    <= 1'b0;
            up_arrow_held       <= 1'b0;
            down_arrow_held     <= 1'b0;
            space_held          <= 1'b0;
            enter_held          <= 1'b0;
            p_held              <= 1'b0;
            r_held              <= 1'b0;
            esc_held            <= 1'b0;

            left_held           <= 1'b0;
            right_held          <= 1'b0;
            up_held             <= 1'b0;
            down_held           <= 1'b0;
            space_pressed       <= 1'b0;
            enter_pressed       <= 1'b0;
            pause_pressed       <= 1'b0;
            restart_pressed     <= 1'b0;
            escape_pressed      <= 1'b0;
        end else begin
            space_pressed   <= 1'b0;
            enter_pressed   <= 1'b0;
            pause_pressed   <= 1'b0;
            restart_pressed <= 1'b0;
            escape_pressed  <= 1'b0;

            if (scan_valid) begin
                if (scan_code == 8'hE0) begin
                    extended_code <= 1'b1;
                end else if (scan_code == 8'hF0) begin
                    release_code <= 1'b1;
                end else begin
                    case (scan_code)
                        // W
                        8'h1D: begin
                            if (extended_code) begin
                                if (release_code) w_held <= 1'b0;
                                else              w_held <= 1'b1;
                            end else begin
                                if (release_code) w_held <= 1'b0;
                                else              w_held <= 1'b1;
                            end
                        end
                        // S
                        8'h1B: begin
                            if (release_code) s_held <= 1'b0;
                            else              s_held <= 1'b1;
                        end
                        // A
                        8'h1C: begin
                            if (release_code) a_held <= 1'b0;
                            else              a_held <= 1'b1;
                        end
                        // D
                        8'h23: begin
                            if (release_code) d_held <= 1'b0;
                            else              d_held <= 1'b1;
                        end
                        // Left arrow: E0 6B
                        8'h6B: begin
                            if (extended_code) begin
                                if (release_code) left_arrow_held <= 1'b0;
                                else              left_arrow_held <= 1'b1;
                            end
                        end
                        // Right arrow: E0 74
                        8'h74: begin
                            if (extended_code) begin
                                if (release_code) right_arrow_held <= 1'b0;
                                else              right_arrow_held <= 1'b1;
                            end
                        end
                        // Up arrow: E0 75
                        8'h75: begin
                            if (extended_code) begin
                                if (release_code) up_arrow_held <= 1'b0;
                                else              up_arrow_held <= 1'b1;
                            end
                        end
                        // Down arrow: E0 72
                        8'h72: begin
                            if (extended_code) begin
                                if (release_code) down_arrow_held <= 1'b0;
                                else              down_arrow_held <= 1'b1;
                            end
                        end
                        // Space
                        8'h29: begin
                            if (release_code) begin
                                space_held <= 1'b0;
                            end else if (!space_held) begin
                                space_held    <= 1'b1;
                                space_pressed <= 1'b1;
                            end
                        end
                        // Enter
                        8'h5A: begin
                            if (release_code) begin
                                enter_held <= 1'b0;
                            end else if (!enter_held) begin
                                enter_held    <= 1'b1;
                                enter_pressed <= 1'b1;
                            end
                        end
                        // P
                        8'h4D: begin
                            if (release_code) begin
                                p_held <= 1'b0;
                            end else if (!p_held) begin
                                p_held        <= 1'b1;
                                pause_pressed <= 1'b1;
                            end
                        end
                        // R
                        8'h2D: begin
                            if (release_code) begin
                                r_held <= 1'b0;
                            end else if (!r_held) begin
                                r_held          <= 1'b1;
                                restart_pressed <= 1'b1;
                            end
                        end
                        // Esc: 76
                        8'h76: begin
                            if (release_code) begin
                                esc_held <= 1'b0;
                            end else if (!esc_held) begin
                                esc_held       <= 1'b1;
                                escape_pressed <= 1'b1;
                            end
                        end
                        default: begin
                            // Other keys are intentionally ignored.
                        end
                    endcase

                    extended_code <= 1'b0;
                    release_code  <= 1'b0;
                end
            end

            left_held  <= a_held | left_arrow_held;
            right_held <= d_held | right_arrow_held;
            up_held    <= w_held | up_arrow_held;
            down_held  <= s_held | down_arrow_held;
        end
    end

endmodule
