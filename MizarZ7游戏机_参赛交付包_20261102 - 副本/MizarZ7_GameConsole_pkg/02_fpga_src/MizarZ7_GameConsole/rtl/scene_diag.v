`timescale 1ns / 1ps
//=============================================================================
// scene_diag.v
//   Full-screen diagnostic pattern for a STANDARD 640x480@60 VESA frame.
//
//   Purpose: determine whether "backlight on but black screen" is caused by
//   the non-standard active window (480x320 inside 800x525) or by the TMDS
//   link itself.  This pattern covers the ENTIRE standard 640x480 active area
//   with no reliance on the monitor guessing a shifted origin.
//
//   Contents:
//     - 8 vertical colour bars, each 80 px wide, full height 480 lines
//       red / green / blue / white / yellow / cyan / magenta / black
//     - an 8 px white border drawn on top of the bars
//     - a 48x48 pure-red square in the top-left corner (orientation check)
//     - 1 px white vertical lines at every multiple of 64 px (x shift check)
//
//   Purely COMBINATIONAL on x / y so that rgb is produced in the same cycle
//   as de - exactly what hdmi_tx expects.  Same coding style as scene_test.v.
//=============================================================================
module scene_diag (
    input  wire        de,          // active video
    input  wire [11:0] x,
    input  wire [11:0] y,

    output reg  [11:0] rgb          // RGB444 : {R[3:0], G[3:0], B[3:0]}
);

    localparam integer H_ACTIVE = 640;
    localparam integer V_ACTIVE = 480;

    //--------------------------------------------------------------------------
    // 8 colour bars, 80 px wide each, full height
    //--------------------------------------------------------------------------
    reg [2:0] bar;

    always @(*) begin
        if      (x < 12'd80)  bar = 3'd0;
        else if (x < 12'd160) bar = 3'd1;
        else if (x < 12'd240) bar = 3'd2;
        else if (x < 12'd320) bar = 3'd3;
        else if (x < 12'd400) bar = 3'd4;
        else if (x < 12'd480) bar = 3'd5;
        else if (x < 12'd560) bar = 3'd6;
        else                  bar = 3'd7;
    end

    reg [11:0] bar_col;

    always @(*) begin
        case (bar)
            3'd0:    bar_col = 12'hF00;   // red
            3'd1:    bar_col = 12'h0F0;   // green
            3'd2:    bar_col = 12'h00F;   // blue
            3'd3:    bar_col = 12'hFFF;   // white
            3'd4:    bar_col = 12'hFF0;   // yellow
            3'd5:    bar_col = 12'h0FF;   // cyan
            3'd6:    bar_col = 12'hF0F;   // magenta
            default: bar_col = 12'h000;   // black
        endcase
    end

    //--------------------------------------------------------------------------
    // Overlays
    //--------------------------------------------------------------------------
    // 48x48 pure-red square in the top-left corner
    wire in_sq = (x < 12'd48) && (y < 12'd48);

    // 8 px white border around the whole 640x480 window
    wire border = (x < 12'd8) || (x >= H_ACTIVE - 8) ||
                  (y < 12'd8) || (y >= V_ACTIVE - 8);

    // 1 px white vertical line at every multiple of 64 px
    wire vline = (x[5:0] == 6'd0) && (x != 12'd0) && (x < H_ACTIVE);

    //--------------------------------------------------------------------------
    // Output (same cycle as de)
    //--------------------------------------------------------------------------
    always @(*) begin
        if      (!de)     rgb = 12'h000;   // non-active area -> black
        else if (in_sq)   rgb = 12'hF00;   // red square on top
        else if (border)  rgb = 12'hFFF;   // white border
        else if (vline)   rgb = 12'hFFF;   // white x-grid lines
        else              rgb = bar_col;
    end

endmodule