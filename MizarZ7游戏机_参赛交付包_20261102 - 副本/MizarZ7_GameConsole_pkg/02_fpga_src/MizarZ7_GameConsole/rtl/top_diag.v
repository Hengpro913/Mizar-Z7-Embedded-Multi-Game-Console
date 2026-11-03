`timescale 1ns / 1ps
//=============================================================================
// top_diag.v
//   Top level for the Mizar Z7 (XC7Z020-2CLG400) HDMI DIAGNOSTIC bitstream.
//
//   This is a STANDARD 640x480@60 full-screen build, used to decide whether
//   "backlight on but black screen" comes from the non-standard active window
//   (480x320 inside 800x525) or from the TMDS link itself.
//
//   Data flow:
//     50 MHz (H16, Bank35 MRCC)
//        -> clk_hdmi (MMCM) : 25.2 MHz pixel clock / 126 MHz serial clock
//        -> video_timing    : STANDARD 640x480@60 (H_TOTAL=800, V_TOTAL=525)
//        -> scene_diag      : full-screen bars / border / red square (RGB444)
//        -> hdmi_tx         : TMDS encode + 10:1 serialise -> HDMI1 connector
//
//   The 25.2 MHz pixel clock is exactly the 640x480@60 VESA clock
//   (800 x 525 x 60 = 25.2 MHz), so no clock change is required.
//
//   Port list is IDENTICAL to top_game_console.v so the same mizar_z7.xdc is
//   reused unchanged.
//
//   NOTE: there is no dedicated PL reset on this board (POR_nRST only resets
//         the PS), so a power-on reset is generated here from MMCM lock.
//=============================================================================
module top_diag (
    input  wire       sys_clk,       // 50 MHz  : H16
    input  wire [3:0] btn_n,         // PL keys : active low
    output wire [3:0] led_n,         // PL LEDs : active low
    output wire       hdmi_out_en,   // HDMI1 output enable : M20, active high

    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n,
    output wire       hdmi_d0_p,     // blue
    output wire       hdmi_d0_n,
    output wire       hdmi_d1_p,     // green
    output wire       hdmi_d1_n,
    output wire       hdmi_d2_p,     // red
    output wire       hdmi_d2_n
);

    //--------------------------------------------------------------------------
    // Clocking
    //--------------------------------------------------------------------------
    wire pixel_clk;      // 25.2 MHz
    wire serial_clk;     // 126 MHz
    wire mmcm_locked;

    clk_hdmi u_clk (
        .clk_in     (sys_clk),
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .locked     (mmcm_locked)
    );

    //--------------------------------------------------------------------------
    // PL power-on reset : held until the MMCM is locked, then for 255 clocks
    //--------------------------------------------------------------------------
    reg [7:0] rst_cnt;
    reg       aRst;          // asynchronous, active high

    always @(posedge pixel_clk or negedge mmcm_locked) begin
        if (!mmcm_locked) begin
            rst_cnt <= 8'd0;
            aRst    <= 1'b1;
        end else if (rst_cnt != 8'hFF) begin
            rst_cnt <= rst_cnt + 8'd1;
            aRst    <= 1'b1;
        end else begin
            aRst    <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // Video timing : STANDARD 640x480@60
    //   H : 640 active + 16 front porch + 96 sync + 48 back porch = 800
    //   V : 480 active + 10 front porch +  2 sync + 33 back porch = 525
    //--------------------------------------------------------------------------
    wire [11:0] px, py;
    wire        de, hs_n, vs_n;

    video_timing #(
        .H_ACTIVE (640), .H_FP (16), .H_SYNC (96), .H_BP (48),
        .V_ACTIVE (480), .V_FP (10), .V_SYNC (2),  .V_BP (33)
    ) u_vtim (
        .pixel_clk (pixel_clk),
        .rst       (aRst),
        .x         (px),
        .y         (py),
        .de        (de),
        .hsync_n   (hs_n),
        .vsync_n   (vs_n),
        .frame_tick()
    );

    //--------------------------------------------------------------------------
    // Keys : invert (active low on the board) and debounce
    //   (no key_ctrl in the diagnostic build - the pattern is static)
    //--------------------------------------------------------------------------
    wire [3:0] btn_raw = ~btn_n;    // now active high
    wire [3:0] btn;                 // debounced, active high

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_btn
            btn_debounce #(
                .CNT_MAX (252_000),
                .CNT_W   (18)
            ) u_db (
                .clk     (pixel_clk),
                .rst     (aRst),
                .btn_in  (btn_raw[gi]),
                .btn_out (btn[gi])
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Diagnostic scene generator (full-screen standard pattern)
    //--------------------------------------------------------------------------
    wire [11:0] scene;

    scene_diag u_scene (
        .de  (de),
        .x   (px),
        .y   (py),
        .rgb (scene)
    );

    //--------------------------------------------------------------------------
    // RGB444 -> RGB888
    //--------------------------------------------------------------------------
    wire [7:0] r8 = {scene[11:8], scene[11:8]};
    wire [7:0] g8 = {scene[ 7:4], scene[ 7:4]};
    wire [7:0] b8 = {scene[ 3:0], scene[ 3:0]};

    //--------------------------------------------------------------------------
    // HDMI transmitter
    //--------------------------------------------------------------------------
    hdmi_tx u_hdmi (
        .pixel_clk   (pixel_clk),
        .serial_clk  (serial_clk),
        .aRst        (aRst),
        .r           (r8),
        .g           (g8),
        .b           (b8),
        .hs          (hs_n),
        .vs          (vs_n),
        .de          (de),
        .hdmi_clk_p  (hdmi_clk_p),
        .hdmi_clk_n  (hdmi_clk_n),
        .hdmi_d0_p   (hdmi_d0_p),
        .hdmi_d0_n   (hdmi_d0_n),
        .hdmi_d1_p   (hdmi_d1_p),
        .hdmi_d1_n   (hdmi_d1_n),
        .hdmi_d2_p   (hdmi_d2_p),
        .hdmi_d2_n   (hdmi_d2_n)
    );

    //--------------------------------------------------------------------------
    // Board indicators
    //--------------------------------------------------------------------------
    assign hdmi_out_en = 1'b1;      // enable the HDMI1 output buffer
    assign led_n       = ~btn;      // key pressed -> LED lit

endmodule