`timescale 1ns / 1ps
//=============================================================================
// clk_hdmi.v
//   MMCM clock generation for the HDMI transmitter.
//
//   Input  : 50 MHz  (board oscillator, pin H16, Bank35 MRCC)
//   Output : pixel_clk  = 25.2 MHz   (x1, OSERDES CLKDIV + all pixel logic)
//            serial_clk = 126  MHz   (x5, OSERDES CLK)
//
//   MMCM maths:
//     DIVCLK_DIVIDE = 5 , CLKFBOUT_MULT_F = 63  -> VCO = 50/5*63 = 630 MHz
//     630 / 5  = 126.0 MHz  (CLKOUT0, serial)
//     630 / 25 =  25.2 MHz  (CLKOUT1, pixel)
//
//   serial_clk MUST be exactly 5 x pixel_clk - the 10:1 DDR OSERDESE2
//   samples one bit on each edge of the 5x clock.
//
//   25.2 MHz pixel clock with an 800 x 525 frame gives
//     HS = 31.50 kHz, VS = 60.00 Hz  ->  exactly the standard 640x480@60
//   rates, which is what the MPI3508 panel accepts.  The 480x320 game window
//   sits inside that frame and is scaled 1:1 onto the native panel.
//
//   NOTE: 12.6 MHz (native 480x320 timing) was tried and REJECTED by the
//   panel - the DVI/HDMI receiver PLL only locks a 25..165 MHz TMDS clock.
//=============================================================================
module clk_hdmi (
    input  wire clk_in,       // 50 MHz
    output wire pixel_clk,    // 25.2 MHz
    output wire serial_clk,   // 126 MHz
    output wire locked
);

    wire clkfb;
    wire clkout0;
    wire clkout1;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (63.000),
        .CLKFBOUT_PHASE     (0.000),
        .CLKIN1_PERIOD      (20.000),   // 50 MHz
        .CLKOUT0_DIVIDE_F   (5.000),    // 630/5  = 126.0 MHz (serial)
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT0_PHASE      (0.000),
        .CLKOUT1_DIVIDE     (25),       // 630/25 =  25.2 MHz (pixel)
        .CLKOUT1_DUTY_CYCLE (0.500),
        .CLKOUT1_PHASE      (0.000),
        .CLKOUT2_DIVIDE     (2),
        .CLKOUT2_DUTY_CYCLE (0.500),
        .CLKOUT2_PHASE      (0.000),
        .CLKOUT3_DIVIDE     (2),
        .CLKOUT3_DUTY_CYCLE (0.500),
        .CLKOUT3_PHASE      (0.000),
        .CLKOUT4_DIVIDE     (2),
        .CLKOUT4_DUTY_CYCLE (0.500),
        .CLKOUT4_PHASE      (0.000),
        .CLKOUT5_DIVIDE     (2),
        .CLKOUT5_DUTY_CYCLE (0.500),
        .CLKOUT5_PHASE      (0.000),
        .CLKOUT6_DIVIDE     (2),
        .CLKOUT6_DUTY_CYCLE (0.500),
        .CLKOUT6_PHASE      (0.000),
        .DIVCLK_DIVIDE      (5),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0  (clkout0),
        .CLKOUT0B (),
        .CLKOUT1  (clkout1),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUT (clkfb),
        .CLKFBOUTB(),
        .CLKFBIN  (clkfb),
        .CLKIN1   (clk_in),
        .PWRDWN   (1'b0),
        .RST      (1'b0),
        .LOCKED   (locked)
    );

    BUFG u_bufg_serial (.I (clkout0), .O (serial_clk));
    BUFG u_bufg_pixel  (.I (clkout1), .O (pixel_clk));

endmodule
