`timescale 1ns / 1ps
//=============================================================================
// scene_menu.v
//   Main menu of the game console.  Purely combinational - a function of
//   (de, x, y, sel, anim) only, so its output is aligned with the "de" pixel.
//
//   anim is a free running frame counter supplied by scene_render; it drives
//   the title pulse and the marquee that runs along the top / bottom border.
//
//   Layout inside the 480 x 320 active window:
//     - a 2 px cyan border with a dark 2 px inlay just inside it, over which a
//       bright yellow marquee segment sweeps from right to left
//     - title  "GAME CONSOLE" @ SCALE 4, amber, with a dark drop shadow
//     - item 0 "SNAKE"        @ SCALE 2, X0 = 200, Y0 = 84
//     - item 1 "TETRIS"       @ SCALE 2, X0 = 192, Y0 = 132
//     - item 2 "FLAPPY BIRD"  @ SCALE 2, X0 = 152, Y0 = 180
//     - item 3 "BREAKOUT"     @ SCALE 2, X0 = 176, Y0 = 228
//     - the selected item sits on a vivid green bar with a bright outline
//
//   Background : 10-band vertical gradient, deep blue at the top through to
//   magenta at the bottom (32 px per band).
//
//   sel = 0 -> SNAKE , 1 -> TETRIS , 2 -> FLAPPY BIRD , 3 -> BREAKOUT
//=============================================================================
module scene_menu (
    input  wire        de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire [2:0]  sel,          // 0 = SNAKE, 1 = TETRIS, 2 = FLAPPY, 3 = BREAKOUT
    input  wire [5:0]  anim,         // free running frame counter
    output reg  [11:0] rgb
);

    //--------------------------------------------------------------------------
    // Palette (RGB444) - deliberately fully saturated : this is the "lively"
    // look, and the tile bevel inside the games derives its highlight and
    // shadow from these hues.
    //--------------------------------------------------------------------------
    localparam [11:0] C_FRAME  = 12'h0FF;   // cyan border
    localparam [11:0] C_INLAY  = 12'h012;   // dark inlay just inside the border
    localparam [11:0] C_MARQ   = 12'hFF0;   // marquee segment
    localparam [11:0] C_TITLE  = 12'hFA0;   // amber
    localparam [11:0] C_TITLE2 = 12'hFF0;   // amber, pulsed brighter
    localparam [11:0] C_SHADOW = 12'h001;   // title drop shadow
    localparam [11:0] C_ITEM   = 12'hFFF;
    localparam [11:0] C_SELBG  = 12'h0F8;   // vivid green bar
    localparam [11:0] C_SELLN  = 12'hFF0;   // bright outline of the bar
    localparam [11:0] C_SELTXT = 12'h000;   // black text on the bar

    //--------------------------------------------------------------------------
    // Background : 10-band vertical gradient
    //--------------------------------------------------------------------------
    function [11:0] bg_at;
        input [8:0] yy;                  // 0..319
        begin
            case (yy[8:5])
                4'd0: bg_at = 12'h103;
                4'd1: bg_at = 12'h105;
                4'd2: bg_at = 12'h207;
                4'd3: bg_at = 12'h209;
                4'd4: bg_at = 12'h30A;
                4'd5: bg_at = 12'h40C;
                4'd6: bg_at = 12'h50C;
                4'd7: bg_at = 12'h60D;
                4'd8: bg_at = 12'h70D;
                default: bg_at = 12'h80E;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Text : the title is drawn twice, once offset by (3,3) as its shadow
    //--------------------------------------------------------------------------
    wire t_in,  t_fg;
    wire t2_in, t2_fg;
    wire s_in,  s_fg;
    wire r_in,  r_fg;

    text_line #(
        .X0 (48), .Y0 (24), .SCALE (4), .NCH (12),
        .TEXT (96'h47414D45_20434F4E_534F4C45)          // "GAME CONSOLE"
    ) u_title (.de(de), .x(x), .y(y), .inside(t_in), .fg(t_fg));

    text_line #(
        .X0 (51), .Y0 (27), .SCALE (4), .NCH (12),
        .TEXT (96'h47414D45_20434F4E_534F4C45)          // "GAME CONSOLE" shifted
    ) u_title_shadow (.de(de), .x(x), .y(y), .inside(t2_in), .fg(t2_fg));

    text_line #(
        .X0 (200), .Y0 (84), .SCALE (2), .NCH (5),
        .TEXT (40'h534E_414B45)                         // "SNAKE"
    ) u_item0 (.de(de), .x(x), .y(y), .inside(s_in), .fg(s_fg));

    text_line #(
        .X0 (192), .Y0 (132), .SCALE (2), .NCH (6),
        .TEXT (48'h5445_5452_4953)                      // "TETRIS"
    ) u_item1 (.de(de), .x(x), .y(y), .inside(r_in), .fg(r_fg));

    wire f_in, f_fg;
    text_line #(
        .X0 (152), .Y0 (180), .SCALE (2), .NCH (11),
        .TEXT (88'h464C_4150_5059_2042_4952_44)         // "FLAPPY BIRD"
    ) u_item2 (.de(de), .x(x), .y(y), .inside(f_in), .fg(f_fg));

    wire b_in, b_fg;
    text_line #(
        .X0 (176), .Y0 (228), .SCALE (2), .NCH (8),
        .TEXT (64'h4252_4541_4B4F_5554)                 // "BREAKOUT"
    ) u_item3 (.de(de), .x(x), .y(y), .inside(b_in), .fg(b_fg));

    //--------------------------------------------------------------------------
    // Border : 2 px cyan ring, 2 px dark inlay inside it
    //--------------------------------------------------------------------------
    wire frame_px = (x < 12'd2) || (x >= 12'd478) || (y < 12'd2) || (y >= 12'd318);

    wire inlay_px = ((x >= 12'd2)  && (x < 12'd4))   || ((x >= 12'd476) && (x < 12'd478)) ||
                    ((y >= 12'd2)  && (y < 12'd4))   || ((y >= 12'd316) && (y < 12'd318));

    // Marquee : a 56 px bright segment travelling leftwards along the border.
    // mx steps 0, 8, 16 ... 248 once per 2 frames, so one lap takes ~2.1 s.
    wire [8:0] mx  = {1'b0, anim[5:1], 3'b000};
    wire marq_on   = de && ((y < 12'd2) || (y >= 12'd318)) &&
                    (x >= 12'd2) && (x < 12'd478) &&
                    ((x[8:0] - mx) < 9'd56);

    //--------------------------------------------------------------------------
    // Selection bars
    //   Each item uses a 240 px selection bar with a 40 px row pitch.
    //--------------------------------------------------------------------------
    wire bar0 = (x >= 12'd120) && (x < 12'd360) && (y >= 12'd74) && (y < 12'd114);
    wire bar1 = (x >= 12'd120) && (x < 12'd360) && (y >= 12'd122) && (y < 12'd162);
    wire bar2 = (x >= 12'd120) && (x < 12'd360) && (y >= 12'd170) && (y < 12'd210);
    wire bar3 = (x >= 12'd120) && (x < 12'd360) && (y >= 12'd218) && (y < 12'd258);

    wire sel_bar = de && ((sel == 3'd0) ? bar0 :
                          (sel == 3'd1) ? bar1 :
                          (sel == 3'd2) ? bar2 : bar3);
    wire sel_px  = sel_bar && ((sel == 3'd0) ? s_fg :
                               (sel == 3'd1) ? r_fg :
                               (sel == 3'd2) ? f_fg : b_fg);

    // 1 px bright ring around the bar
    wire sel_edge = sel_bar && (
        (sel == 3'd0 &&
            ((y == 12'd74) || (y == 12'd113) ||
             (x == 12'd120) || (x == 12'd359))) ||
        (sel == 3'd1 &&
            ((y == 12'd122) || (y == 12'd161) ||
             (x == 12'd120) || (x == 12'd359))) ||
        (sel == 3'd2 &&
            ((y == 12'd170) || (y == 12'd209) ||
             (x == 12'd120) || (x == 12'd359))) ||
        (sel == 3'd3 &&
            ((y == 12'd218) || (y == 12'd257) ||
             (x == 12'd120) || (x == 12'd359))));

    //--------------------------------------------------------------------------
    // Composite
    //--------------------------------------------------------------------------
    wire [11:0] title_now = anim[4] ? C_TITLE2 : C_TITLE;

    always @(*) begin
        if (marq_on)             rgb = C_MARQ;
        else if (frame_px)       rgb = C_FRAME;
        else if (inlay_px)       rgb = C_INLAY;
        else if (sel_px)         rgb = C_SELTXT;
        else if (sel_edge)       rgb = C_SELLN;
        else if (sel_bar)        rgb = C_SELBG;
        else if (t_fg)           rgb = title_now;
        else if (t2_fg)          rgb = C_SHADOW;
        else if (s_fg || r_fg || f_fg || b_fg) rgb = C_ITEM;
        else                     rgb = bg_at(y[8:0]);
    end

endmodule
