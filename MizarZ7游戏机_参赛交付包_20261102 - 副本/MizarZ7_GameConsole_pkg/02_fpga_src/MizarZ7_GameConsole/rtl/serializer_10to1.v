`timescale 1ns / 1ps
//=============================================================================
// serializer_10to1.v
//   7-series 10:1 DDR serializer for one TMDS channel.
//   OSERDESE2 master + slave cascade (DATA_WIDTH = 10 requires the cascade),
//   followed by an OBUFDS in the same IOB to create the differential pair.
//
//   Bit order : bit 0 of data_in is transmitted FIRST (DVI sends LSB first).
//   Clocks    : CLKDIV = pixel clock (x1), CLK = serial clock (x5, DDR).
//               Both must be phase aligned - they come from the same MMCM.
//=============================================================================
module serializer_10to1 (
    input  wire        pixel_clk,   // TMDS clock x1 -> OSERDES CLKDIV
    input  wire        serial_clk,  // TMDS clock x5 -> OSERDES CLK
    input  wire        aRst,        // asynchronous, active high
    input  wire [9:0]  data_in,     // encoded symbol, bit0 first
    output wire        data_p,
    output wire        data_n
);

    wire        s_data;
    wire        cascade1, cascade2;
    wire [13:4] pdata_q;

    //--------------------------------------------------------------------------
    // Re-order the parallel word for the master/slave cascade.
    //   master D1..D8 = data_in[0..7]   (pdata_q[13..6])
    //   slave  D3,D4  = data_in[8..9]   (pdata_q[5..4])
    //--------------------------------------------------------------------------
    assign pdata_q[13] = data_in[0];
    assign pdata_q[12] = data_in[1];
    assign pdata_q[11] = data_in[2];
    assign pdata_q[10] = data_in[3];
    assign pdata_q[ 9] = data_in[4];
    assign pdata_q[ 8] = data_in[5];
    assign pdata_q[ 7] = data_in[6];
    assign pdata_q[ 6] = data_in[7];
    assign pdata_q[ 5] = data_in[8];
    assign pdata_q[ 4] = data_in[9];
    // pdata_q[3:0] are not used by a 10-bit cascaded OSERDESE2

    //--------------------------------------------------------------------------
    // Differential output buffer (TMDS_33 -> requires a 3.3 V HR bank)
    //--------------------------------------------------------------------------
    OBUFDS #(
        .IOSTANDARD ("TMDS_33")
    ) u_obufds (
        .O  (data_p),
        .OB (data_n),
        .I  (s_data)
    );

    //--------------------------------------------------------------------------
    // Serializer master : drives the output pin
    //--------------------------------------------------------------------------
    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .SERDES_MODE    ("MASTER")
    ) u_master (
        .OQ        (s_data),
        .OFB       (),
        .SHIFTOUT1 (),
        .SHIFTOUT2 (),
        .TBYTEOUT  (),
        .TFB       (),
        .TQ        (),
        .CLK       (serial_clk),
        .CLKDIV    (pixel_clk),
        .D1        (pdata_q[13]),
        .D2        (pdata_q[12]),
        .D3        (pdata_q[11]),
        .D4        (pdata_q[10]),
        .D5        (pdata_q[ 9]),
        .D6        (pdata_q[ 8]),
        .D7        (pdata_q[ 7]),
        .D8        (pdata_q[ 6]),
        .OCE       (1'b1),
        .RST       (aRst),
        .SHIFTIN1  (cascade1),
        .SHIFTIN2  (cascade2),
        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TBYTEIN   (1'b0),
        .TCE       (1'b0)
    );

    //--------------------------------------------------------------------------
    // Serializer slave : supplies bits 8 and 9 through the SHIFT chain
    //--------------------------------------------------------------------------
    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .TRISTATE_WIDTH (1),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .SERDES_MODE    ("SLAVE")
    ) u_slave (
        .OQ        (),
        .OFB       (),
        .SHIFTOUT1 (cascade1),
        .SHIFTOUT2 (cascade2),
        .TBYTEOUT  (),
        .TFB       (),
        .TQ        (),
        .CLK       (serial_clk),
        .CLKDIV    (pixel_clk),
        .D1        (1'b0),
        .D2        (1'b0),
        .D3        (pdata_q[5]),
        .D4        (pdata_q[4]),
        .D5        (1'b0),
        .D6        (1'b0),
        .D7        (1'b0),
        .D8        (1'b0),
        .OCE       (1'b1),
        .RST       (aRst),
        .SHIFTIN1  (1'b0),
        .SHIFTIN2  (1'b0),
        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TBYTEIN   (1'b0),
        .TCE       (1'b0)
    );

endmodule