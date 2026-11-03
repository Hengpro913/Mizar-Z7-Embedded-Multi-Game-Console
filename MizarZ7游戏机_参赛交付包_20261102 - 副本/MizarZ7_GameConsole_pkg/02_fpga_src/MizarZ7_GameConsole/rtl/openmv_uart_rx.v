`timescale 1ns / 1ps
//=============================================================================
// openmv_uart_rx.v
//   Small 8N1 UART receiver and OpenMV frame parser.
//
//   OpenMV frame (6 bytes):
//     AA  X  Y  CONF  SEQ  XOR(X,Y,CONF,SEQ)
//
//   A valid frame with CONF != 0 updates target_x/target_y, raises target_valid
//   and emits a one-clock target_update pulse.
//   A valid frame with CONF == 0 lowers target_valid.  If no UART byte arrives
//   for TIMEOUT_CLKS, target_valid is also lowered.
//=============================================================================
module openmv_uart_rx #(
    parameter integer CLK_HZ      = 25_200_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer TIMEOUT_CLKS = 12_600_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       uart_rx,

    output reg  [7:0] target_x,
    output reg  [7:0] target_y,
    output reg        target_valid,
    output reg        target_update,
    output reg        target_event,
    output reg [15:0] good_frames,
    output reg [15:0] bad_frames
);

    localparam integer BIT_CLKS = (CLK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer HALF_CLKS = BIT_CLKS / 2;

    localparam [1:0] UART_IDLE  = 2'd0;
    localparam [1:0] UART_START = 2'd1;
    localparam [1:0] UART_DATA  = 2'd2;
    localparam [1:0] UART_STOP  = 2'd3;

    reg [1:0]  uart_sync;
    reg [1:0]  uart_state;
    reg [15:0] uart_count;
    reg [2:0]  uart_bit;
    reg [7:0]  uart_shift;
    reg [7:0]  uart_byte;
    reg        uart_byte_valid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_sync       <= 2'b11;
            uart_state      <= UART_IDLE;
            uart_count      <= 16'd0;
            uart_bit        <= 3'd0;
            uart_shift      <= 8'd0;
            uart_byte       <= 8'd0;
            uart_byte_valid <= 1'b0;
        end else begin
            uart_sync       <= {uart_sync[0], uart_rx};
            uart_byte_valid <= 1'b0;

            case (uart_state)
                UART_IDLE: begin
                    if (!uart_sync[1]) begin
                        uart_count <= HALF_CLKS - 1;
                        uart_state <= UART_START;
                    end
                end

                UART_START: begin
                    if (uart_count == 0) begin
                        if (!uart_sync[1]) begin
                            uart_count <= BIT_CLKS - 1;
                            uart_bit   <= 3'd0;
                            uart_state <= UART_DATA;
                        end else begin
                            uart_state <= UART_IDLE;
                        end
                    end else begin
                        uart_count <= uart_count - 1'b1;
                    end
                end

                UART_DATA: begin
                    if (uart_count == 0) begin
                        uart_shift[uart_bit] <= uart_sync[1];
                        uart_count <= BIT_CLKS - 1;
                        if (uart_bit == 3'd7) begin
                            uart_state <= UART_STOP;
                        end else begin
                            uart_bit <= uart_bit + 1'b1;
                        end
                    end else begin
                        uart_count <= uart_count - 1'b1;
                    end
                end

                UART_STOP: begin
                    if (uart_count == 0) begin
                        if (uart_sync[1]) begin
                            uart_byte       <= uart_shift;
                            uart_byte_valid <= 1'b1;
                        end
                        uart_state <= UART_IDLE;
                    end else begin
                        uart_count <= uart_count - 1'b1;
                    end
                end

                default: uart_state <= UART_IDLE;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Packet parser
    //--------------------------------------------------------------------------
    reg [2:0]  packet_index;
    reg [7:0]  frame_x;
    reg [7:0]  frame_y;
    reg [7:0]  frame_conf;
    reg [7:0]  frame_seq;
    reg [23:0] timeout_count;

    wire [7:0] expected_checksum = frame_x ^ frame_y ^ frame_conf ^ frame_seq;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            packet_index <= 3'd0;
            frame_x      <= 8'd0;
            frame_y      <= 8'd0;
            frame_conf   <= 8'd0;
            frame_seq    <= 8'd0;
            target_x     <= 8'd127;
            target_y     <= 8'd127;
            target_valid <= 1'b0;
            target_update <= 1'b0;
            target_event <= 1'b0;
            good_frames  <= 16'd0;
            bad_frames   <= 16'd0;
            timeout_count <= 24'd0;
        end else begin
            target_update <= 1'b0;
            target_event  <= 1'b0;

            if (timeout_count != 0) begin
                timeout_count <= timeout_count - 1'b1;
            end else if (target_valid) begin
                target_valid <= 1'b0;
            end

            if (uart_byte_valid) begin
                timeout_count <= TIMEOUT_CLKS;

                case (packet_index)
                    3'd0: begin
                        if (uart_byte == 8'hAA) begin
                            packet_index <= 3'd1;
                        end
                    end
                    3'd1: begin
                        frame_x <= uart_byte;
                        packet_index <= 3'd2;
                    end
                    3'd2: begin
                        frame_y <= uart_byte;
                        packet_index <= 3'd3;
                    end
                    3'd3: begin
                        frame_conf <= uart_byte;
                        packet_index <= 3'd4;
                    end
                    3'd4: begin
                        frame_seq <= uart_byte;
                        packet_index <= 3'd5;
                    end
                    default: begin
                        if (uart_byte == expected_checksum) begin
                            good_frames <= good_frames + 1'b1;
                            if (frame_conf != 0) begin
                                target_x     <= frame_x;
                                target_y     <= frame_y;
                                target_valid <= 1'b1;
                                target_update <= 1'b1;
                                target_event <= frame_seq[7];
                            end else begin
                                target_valid <= 1'b0;
                            end
                        end else begin
                            bad_frames <= bad_frames + 1'b1;
                            target_valid <= 1'b0;
                        end
                        packet_index <= 3'd0;
                    end
                endcase
            end
        end
    end

endmodule
