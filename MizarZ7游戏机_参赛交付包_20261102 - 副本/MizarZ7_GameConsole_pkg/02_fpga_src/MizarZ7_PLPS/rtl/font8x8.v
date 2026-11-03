`timescale 1ns / 1ps
//=============================================================================
// font8x8.v
//   8x8 ASCII font, thin wrapper that EXTENDS the baseline font_rom.
//
//   font_rom.v (in MizarZ7_GameConsole/rtl) only defines the glyphs the three
//   game scenes need.  The on-screen Bluetooth status console needs the whole
//   alphabet, so the missing glyphs live here and are OR-ed on top.  The
//   baseline file is therefore NOT modified and the p2d3 bitstream stays valid.
//
//   Encoding (identical to font_rom):
//     bits[7] = leftmost pixel, bits[0] = rightmost ; 1 = draw
//     eight row-bytes, row 0 in the LOW byte
//=============================================================================
module font8x8 (
    input  wire [7:0] ch,      // ASCII code (lower case must be folded first)
    input  wire [2:0] row,     // 0 = top ... 7 = bottom
    output wire [7:0] bits
);

    wire [7:0] b_base;

    font_rom u_base (
        .ch   (ch),
        .row  (row),
        .bits (b_base)
    );

    reg [63:0] g;

    always @(*) begin
        case (ch)
            //---------------- letters missing in font_rom -------------
            8'h42: g = 64'h00F0_8888_F088_88F0;   // 'B'
            8'h44: g = 64'h00F0_8888_8888_88F0;   // 'D'
            8'h46: g = 64'h00F8_8080_F080_8080;   // 'F'
            8'h48: g = 64'h0088_8888_F888_8888;   // 'H'
            8'h4A: g = 64'h0060_9010_1010_1038;   // 'J'
            8'h50: g = 64'h0080_8080_F088_88F0;   // 'P'
            8'h51: g = 64'h0068_90A8_8888_8870;   // 'Q'
            8'h57: g = 64'h0088_D8A8_A888_8888;   // 'W'
            8'h59: g = 64'h0020_2020_2050_8888;   // 'Y'
            8'h5A: g = 64'h00F8_8040_2010_08F8;   // 'Z'

            //---------------- punctuation ------------------------------
            8'h3A: g = 64'h0000_6060_0060_6000;   // ':'
            8'h2E: g = 64'h0000_6060_0000_0000;   // '.'
            8'h2F: g = 64'h0080_4040_2010_1008;   // '/'
            8'h28: g = 64'h0010_2040_4040_2010;   // '('
            8'h29: g = 64'h0040_2010_1010_2040;   // ')'
            8'h3F: g = 64'h0020_0020_1008_8870;   // '?'
            8'h21: g = 64'h0020_0020_2020_2020;   // '!'
            8'h2B: g = 64'h0000_2020_F820_2000;   // '+'
            8'h2A: g = 64'h0000_A870_F870_A800;   // '*'
            8'h5F: g = 64'h00F8_0000_0000_0000;   // '_'
            8'h23: g = 64'h0050_50F8_50F8_5050;   // '#'
            8'h2C: g = 64'h0020_6000_0000_0000;   // ','

            default: g = 64'h0000_0000_0000_0000;
        endcase
    end

    assign bits = b_base | g[row*8 +: 8];

endmodule
