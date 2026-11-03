`timescale 1ns / 1ps
//=============================================================================
// key_ctrl.v
//   Turns 4 debounced physical keys into LOGICAL key events.
//
//   This is the abstraction layer that isolates the games / menu from the
//   physical input device.  When a real keyboard is added later, only this
//   module has to be replaced - the logical port list stays the same.
//
//   Logical interface (all active high, one pixel-clock wide pulses):
//     left_p / up_p   : fired on the press edge
//     right_p/down_p  : fired on the release edge, but ONLY for a short press
//     ok_p            : fired after RIGHT  (K5) is held for LONG_CNT clocks
//     back_p          : fired after DOWN   (K7) is held for LONG_CNT clocks
//     right_held      : LEVEL, stays high for as long as RIGHT (K5) is pressed
//                       (the games use it to keep a held fast drop engaged)
//
//   A short / long press disambiguation is used for K5 and K7 so that a long
//   press produces ok_p / back_p WITHOUT also producing a direction event.
//
//   LONG_CNT = 10_080_000 -> 0.4 s at a 25.2 MHz pixel clock.
//=============================================================================
module key_ctrl #(
    parameter integer LONG_CNT = 10_080_000,
    parameter integer CNT_W    = 24
)(
    input  wire clk,
    input  wire rst,

    input  wire k_left,     // debounced, active high
    input  wire k_right,
    input  wire k_up,
    input  wire k_down,

    output reg  left_p,
    output reg  right_p,
    output reg  up_p,
    output reg  down_p,
    output reg  ok_p,
    output reg  back_p,
    output reg  right_held
);

    //--------------------------------------------------------------------------
    // LEFT / UP : immediate one-shot pulse on the press edge
    //--------------------------------------------------------------------------
    reg left_d, up_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            left_d <= 1'b0;
            up_d   <= 1'b0;
            left_p <= 1'b0;
            up_p   <= 1'b0;
        end else begin
            left_d <= k_left;
            up_d   <= k_up;
            left_p <= k_left & ~left_d;
            up_p   <= k_up   & ~up_d;
        end
    end

    //--------------------------------------------------------------------------
    // RIGHT / OK   and   DOWN / BACK : short press vs. long press
    //--------------------------------------------------------------------------
    reg r_d, d_d;                 // previous (1 clock old) key value
    reg r_long, d_long;           // long press already reported
    reg [CNT_W-1:0] r_cnt, d_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r_d     <= 1'b0;
            d_d     <= 1'b0;
            r_long  <= 1'b0;
            d_long  <= 1'b0;
            r_cnt   <= {CNT_W{1'b0}};
            d_cnt   <= {CNT_W{1'b0}};
            right_p <= 1'b0;
            down_p  <= 1'b0;
            ok_p    <= 1'b0;
            back_p  <= 1'b0;
            right_held <= 1'b0;
        end else begin
            // pulses are one clock wide
            r_d     <= k_right;
            d_d     <= k_down;
            right_p <= 1'b0;
            down_p  <= 1'b0;
            ok_p    <= 1'b0;
            back_p  <= 1'b0;
            right_held <= k_right;         // level, not a pulse

            // ---------------- RIGHT / OK ----------------
            if (k_right & ~r_d) begin          // press edge
                r_cnt  <= {CNT_W{1'b0}};
                r_long <= 1'b0;
            end else if (k_right) begin        // still held
                if (!r_long) begin
                    if (r_cnt == LONG_CNT - 1) begin
                        r_long <= 1'b1;
                        ok_p   <= 1'b1;
                    end else begin
                        r_cnt <= r_cnt + 1'b1;
                    end
                end
            end else if (r_d) begin            // release edge, short press
                if (!r_long) right_p <= 1'b1;
            end

            // ---------------- DOWN / BACK ----------------
            if (k_down & ~d_d) begin
                d_cnt  <= {CNT_W{1'b0}};
                d_long <= 1'b0;
            end else if (k_down) begin
                if (!d_long) begin
                    if (d_cnt == LONG_CNT - 1) begin
                        d_long <= 1'b1;
                        back_p <= 1'b1;
                    end else begin
                        d_cnt <= d_cnt + 1'b1;
                    end
                end
            end else if (d_d) begin
                if (!d_long) down_p <= 1'b1;
            end
        end
    end

endmodule
