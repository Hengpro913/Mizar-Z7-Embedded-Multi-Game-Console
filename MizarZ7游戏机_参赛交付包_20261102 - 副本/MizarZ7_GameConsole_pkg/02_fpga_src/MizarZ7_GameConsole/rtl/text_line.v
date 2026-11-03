`timescale 1ns / 1ps
//=============================================================================
// text_line.v
//   Renders ONE fixed string, combinationally, at a fixed position.
//
//   It does NOT decide the colour - it only tells the parent whether the
//   current pixel belongs to this string's box, and whether it is a glyph
//   pixel.  The parent composites (background / other text / borders).
//
//     inside : pixel (x,y) lies inside this string's bounding box
//     fg     : ... and is a foreground (glyph) pixel
//
//   TEXT packs the characters with the FIRST character in the MSB, i.e. the
//   same packing used by a Verilog string literal, so character "ci" lives at
//   TEXT[(NCH-1-ci)*8 +: 8].
//
//   SCALE must be a power of two (1 / 2 / 4 / 8).  It is purely combinational
//   and is aligned with "de".
//=============================================================================
module text_line #(
    parameter integer     X0    = 0,        // left edge  (px)
    parameter integer     Y0    = 0,        // top edge   (px)
    parameter integer     SCALE = 2,        // 1 / 2 / 4 / 8
    parameter integer     NCH   = 8,        // number of characters
    parameter [8*NCH-1:0] TEXT  = {8*NCH{1'b0}}
)(
    input  wire        de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    output wire        inside,
    output wire        fg
);

    localparam integer CW = 8 * SCALE;      // character cell size (px)
    localparam integer W  = NCH * CW;       // string width (px)
    localparam integer LS = (SCALE == 1) ? 0 :
                            (SCALE == 2) ? 1 :
                            (SCALE == 4) ? 2 : 3;

    wire in_box = de && (x >= X0) && (x < (X0 + W)) &&
                        (y >= Y0) && (y < (Y0 + CW));

    wire [11:0] dx = x - X0;
    wire [11:0] dy = y - Y0;

    wire [11:0] ci = dx >> (3 + LS);        // character index
    wire [11:0] sx = dx >> LS;              // column inside the cell
    wire [11:0] sy = dy >> LS;              // row    inside the cell

    wire [2:0]  cc = sx[2:0];
    wire [2:0]  ry = sy[2:0];

    wire [11:0] ci_s = (ci < NCH) ? ci : 12'd0;
    wire [7:0]  ch   = TEXT[(NCH - 1 - ci_s)*8 +: 8];

    wire [7:0]  bits;
    font_rom u_font (.ch (ch), .row (ry), .bits (bits));

    assign inside = in_box;
    assign fg     = in_box && bits[7 - cc];

endmodule
