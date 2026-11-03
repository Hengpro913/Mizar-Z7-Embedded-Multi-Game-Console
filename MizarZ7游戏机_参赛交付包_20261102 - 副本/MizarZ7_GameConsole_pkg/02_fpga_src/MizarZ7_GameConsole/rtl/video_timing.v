`timescale 1ns / 1ps
//=============================================================================
// video_timing.v
//   Parameterised VESA-style sync generator.
//
//   Default configuration (480x320 active window inside an 800x525 frame):
//     H : 480 active + 16 front porch + 96 sync + 208 back porch = 800
//     V : 320 active + 10 front porch +  2 sync + 193 back porch = 525
//     with a 25.2 MHz pixel clock  ->  HS = 31.5 kHz, VS = 60.0 Hz
//
//   HS / VS are the exact rates of standard 640x480@60, which maximises
//   monitor compatibility.  To output a real 640x480 picture instead, simply
//   instantiate with H_ACTIVE = 640 and V_ACTIVE = 480 (clock unchanged).
//
//   x / y are registered counters; de / hsync_n / vsync_n are derived from them
//   combinationally, so every output refers to the SAME pixel.
//=============================================================================
module video_timing #(
    parameter integer H_ACTIVE = 480,
    parameter integer H_FP     = 16,
    parameter integer H_SYNC   = 96,
    parameter integer H_BP     = 208,
    parameter integer V_ACTIVE = 320,
    parameter integer V_FP     = 10,
    parameter integer V_SYNC   = 2,
    parameter integer V_BP     = 193
)(
    input  wire        pixel_clk,
    input  wire        rst,
    output reg  [11:0] x,
    output reg  [11:0] y,
    output reg         de,
    output reg         hsync_n,     // active low
    output reg         vsync_n,     // active low
    output reg         frame_tick    // 1 pixel-clock pulse on the last pixel
);

    localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    localparam integer H_SYNC_START = H_ACTIVE + H_FP;
    localparam integer H_SYNC_END   = H_ACTIVE + H_FP + H_SYNC;
    localparam integer V_SYNC_START = V_ACTIVE + V_FP;
    localparam integer V_SYNC_END   = V_ACTIVE + V_FP + V_SYNC;

    //--------------------------------------------------------------------------
    // Pixel / line counters
    //--------------------------------------------------------------------------
    always @(posedge pixel_clk) begin
        if (rst) begin
            x <= 12'd0;
            y <= 12'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 12'd0;
            y <= (y == V_TOTAL - 1) ? 12'd0 : (y + 12'd1);
        end else begin
            x <= x + 12'd1;
        end
    end

    //--------------------------------------------------------------------------
    // Derived outputs (same cycle as x / y)
    //--------------------------------------------------------------------------
    always @(*) begin
        de         = (x < H_ACTIVE) && (y < V_ACTIVE);
        hsync_n    = ~((x >= H_SYNC_START) && (x < H_SYNC_END));
        vsync_n    = ~((y >= V_SYNC_START) && (y < V_SYNC_END));
        frame_tick = (x == H_TOTAL - 1) && (y == V_TOTAL - 1);
    end

endmodule