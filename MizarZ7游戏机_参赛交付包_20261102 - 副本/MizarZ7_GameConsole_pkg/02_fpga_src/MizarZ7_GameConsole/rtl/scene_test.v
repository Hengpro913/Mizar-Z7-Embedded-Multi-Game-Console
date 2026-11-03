`timescale 1ns / 1ps
//=============================================================================
// scene_test.v
//   Phase-1 bring-up pattern.  Two purposes:
//     1) prove that the TMDS link and the video timing are correct
//        (8 colour bars + a white 2 px frame around the 480x320 window);
//     2) prove that the whole input path works
//        (the 48x48 square moves with LEFT / RIGHT / UP / DOWN and changes
//         colour according to the key currently held).
//
//   This module is PURELY COMBINATIONAL on x / y so that rgb is produced in the
//   same cycle as de - which is what hdmi_tx expects.
//=============================================================================
module scene_test (
    input  wire        pixel_clk,
    input  wire        rst,

    input  wire        de,          // active video
    input  wire [11:0] x,
    input  wire [11:0] y,

    input  wire        left_p,
    input  wire        right_p,
    input  wire        up_p,
    input  wire        down_p,
    input  wire [3:0]  k_level,     // debounced keys, active high

    output reg  [11:0] rgb          // RGB444 : {R[3:0], G[3:0], B[3:0]}
);

    localparam integer H_ACTIVE = 480;
    localparam integer V_ACTIVE = 320;
    localparam integer SQ_SIZE  = 48;
    localparam integer SQ_STEP  = 8;

    localparam [11:0] X_MIN = 12'd0;
    localparam [11:0] X_MAX = H_ACTIVE - SQ_SIZE - SQ_STEP;   // 424
    localparam [11:0] Y_MIN = 12'd0;
    localparam [11:0] Y_MAX = V_ACTIVE - SQ_SIZE - SQ_STEP;   // 264

    //--------------------------------------------------------------------------
    // Moving square position
    //--------------------------------------------------------------------------
    reg [11:0] sq_x, sq_y;

    always @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            sq_x <= 12'd216;    // (480 - 48) / 2
            sq_y <= 12'd136;    // (320 - 48) / 2
        end else begin
            if (left_p  && sq_x > X_MIN) sq_x <= sq_x - SQ_STEP;
            if (right_p && sq_x < X_MAX) sq_x <= sq_x + SQ_STEP;
            if (up_p    && sq_y > Y_MIN) sq_y <= sq_y - SQ_STEP;
            if (down_p  && sq_y < Y_MAX) sq_y <= sq_y + SQ_STEP;
        end
    end

    //--------------------------------------------------------------------------
    // 8 colour bars, 60 px wide each
    //--------------------------------------------------------------------------
    reg [2:0] bar;

    always @(*) begin
        if      (x < 12'd60)  bar = 3'd0;
        else if (x < 12'd120) bar = 3'd1;
        else if (x < 12'd180) bar = 3'd2;
        else if (x < 12'd240) bar = 3'd3;
        else if (x < 12'd300) bar = 3'd4;
        else if (x < 12'd360) bar = 3'd5;
        else if (x < 12'd420) bar = 3'd6;
        else                  bar = 3'd7;
    end

    reg [11:0] bar_col;

    always @(*) begin
        case (bar)
            3'd0:    bar_col = 12'hF00;   // red
            3'd1:    bar_col = 12'hFF0;   // yellow
            3'd2:    bar_col = 12'h0F0;   // green
            3'd3:    bar_col = 12'h0FF;   // cyan
            3'd4:    bar_col = 12'h00F;   // blue
            3'd5:    bar_col = 12'hF0F;   // magenta
            3'd6:    bar_col = 12'hFFF;   // white
            default: bar_col = 12'h000;   // black
        endcase
    end

    //--------------------------------------------------------------------------
    // Square overlay
    //--------------------------------------------------------------------------
    wire in_sq = (x >= sq_x) && (x < sq_x + SQ_SIZE) &&
                 (y >= sq_y) && (y < sq_y + SQ_SIZE);

    wire [11:0] sq_col = k_level[0] ? 12'hF00 :   // LEFT   held -> red
                         k_level[1] ? 12'h0F0 :   // RIGHT  held -> green
                         k_level[2] ? 12'h00F :   // UP     held -> blue
                         k_level[3] ? 12'hFF0 :   // DOWN   held -> yellow
                                      12'hFFF;    // idle   -> white

    // 2 px white frame around the active window
    wire border = (x < 12'd2) || (x >= 12'd478) ||
                  (y < 12'd2) || (y >= 12'd318);

    //--------------------------------------------------------------------------
    // Output (same cycle as de)
    //--------------------------------------------------------------------------
    always @(*) begin
        if      (!de)     rgb = 12'h000;
        else if (in_sq)   rgb = sq_col;
        else if (border)  rgb = 12'hFFF;
        else              rgb = bar_col;
    end

endmodule