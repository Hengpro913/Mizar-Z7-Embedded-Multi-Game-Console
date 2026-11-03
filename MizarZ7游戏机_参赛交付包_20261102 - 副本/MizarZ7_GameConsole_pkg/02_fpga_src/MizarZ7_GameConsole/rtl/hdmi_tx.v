`timescale 1ns / 1ps
//=============================================================================
// hdmi_tx.v
//   HDMI / DVI transmitter built from scratch:
//     - 3 x tmds_encoder   (blue carries HS/VS in its control bits)
//     - 4 x serializer_10to1 (3 data channels + 1 clock channel)
//   The clock channel simply serialises the constant pattern 10'b1111100000,
//   which produces a clean 50 % duty square wave at the pixel clock rate and
//   keeps the same OSERDES latency as the data channels.
//
//   Channel mapping (DVI 1.0):
//     D0 / blue  : din = B, c1 = VSYNC, c0 = HSYNC
//     D1 / green : din = G, c1 = 0,     c0 = 0
//     D2 / red   : din = R, c1 = 0,     c0 = 0
//=============================================================================
module hdmi_tx (
    input  wire        pixel_clk,
    input  wire        serial_clk,
    input  wire        aRst,

    input  wire [7:0]  r,
    input  wire [7:0]  g,
    input  wire [7:0]  b,
    input  wire        hs,        // horizontal sync, active LOW
    input  wire        vs,        // vertical   sync, active LOW
    input  wire        de,        // data enable

    output wire        hdmi_clk_p,
    output wire        hdmi_clk_n,
    output wire        hdmi_d0_p, // blue
    output wire        hdmi_d0_n,
    output wire        hdmi_d1_p, // green
    output wire        hdmi_d1_n,
    output wire        hdmi_d2_p, // red
    output wire        hdmi_d2_n
);

    wire [9:0] q_blue, q_green, q_red;

    // constant clock-channel symbol: 5 ones then 5 zeros
    wire [9:0] q_clk = 10'b1111100000;

    tmds_encoder u_enc_blue (
        .PixelClk (pixel_clk), .aRst (aRst),
        .din (b), .c0 (hs), .c1 (vs), .de (de), .dout (q_blue)
    );

    tmds_encoder u_enc_green (
        .PixelClk (pixel_clk), .aRst (aRst),
        .din (g), .c0 (1'b0), .c1 (1'b0), .de (de), .dout (q_green)
    );

    tmds_encoder u_enc_red (
        .PixelClk (pixel_clk), .aRst (aRst),
        .din (r), .c0 (1'b0), .c1 (1'b0), .de (de), .dout (q_red)
    );

    serializer_10to1 u_ser_clk (
        .pixel_clk (pixel_clk), .serial_clk (serial_clk), .aRst (aRst),
        .data_in (q_clk), .data_p (hdmi_clk_p), .data_n (hdmi_clk_n)
    );

    serializer_10to1 u_ser_d0 (
        .pixel_clk (pixel_clk), .serial_clk (serial_clk), .aRst (aRst),
        .data_in (q_blue), .data_p (hdmi_d0_p), .data_n (hdmi_d0_n)
    );

    serializer_10to1 u_ser_d1 (
        .pixel_clk (pixel_clk), .serial_clk (serial_clk), .aRst (aRst),
        .data_in (q_green), .data_p (hdmi_d1_p), .data_n (hdmi_d1_n)
    );

    serializer_10to1 u_ser_d2 (
        .pixel_clk (pixel_clk), .serial_clk (serial_clk), .aRst (aRst),
        .data_in (q_red), .data_p (hdmi_d2_p), .data_n (hdmi_d2_n)
    );

endmodule