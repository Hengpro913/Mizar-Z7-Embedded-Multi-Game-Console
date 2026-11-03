`timescale 1ns / 1ps
//=============================================================================
// top_game_console.v
//   Top level for the Mizar Z7 (XC7Z020-2CLG400) game console.
//
//   Data flow:
//     50 MHz (H16, Bank35 MRCC)
//        -> clk_hdmi (MMCM) : 25.2 MHz pixel clock / 126 MHz serial clock
//        -> video_timing    : 480x320 active image inside an 800x525 carrier
//        -> scene_render    : menu / snake / tetris scenes (RGB444)
//        -> hdmi_tx         : TMDS encode + 10:1 serialise -> HDMI1 connector
//
//   Input  : PL_KEY1..4 (K4..K7) : R19, T19, J15, B19 - active LOW
//            PS/2 keyboard       : JP2 pin 3/4 (G17/G18)
//            OpenMV UART RX      : JP2 pin 1 (J18)
//   Output : PL_LED1..4 (D6..D9) : G14, C20, B20, H17 - active LOW
//
//   NOTE: there is no dedicated PL reset on this board (POR_nRST only resets
//         the PS), so a power-on reset is generated here from MMCM lock.
//=============================================================================
module top_game_console (
    input  wire       sys_clk,       // 50 MHz  : H16
    input  wire [3:0] btn_n,         // PL keys : active low
    input  wire       ps2_clk,       // JP2 pin 3 : G17
    input  wire       ps2_data,      // JP2 pin 4 : G18
    input  wire       openmv_rx,     // JP2 pin 1 : J18
    output wire [3:0] led_n,         // PL LEDs : active low
    output wire       hdmi_out_en,   // HDMI1 output enable : M20, ACTIVE LOW

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
    // MPI3508 timing : 480x320 active inside an 800x525 carrier
    //   The carrier rates are standard 640x480@60, which the panel accepts.
    //--------------------------------------------------------------------------
    wire [11:0] px, py;
    wire        de, hs_n, vs_n, ft;

    video_timing #(
        .H_ACTIVE (480), .H_FP (16), .H_SYNC (96), .H_BP (208),
        .V_ACTIVE (320), .V_FP (10), .V_SYNC (2),  .V_BP (193)
    ) u_vtim (
        .pixel_clk (pixel_clk),
        .rst       (aRst),
        .x         (px),
        .y         (py),
        .de        (de),
        .hsync_n   (hs_n),
        .vsync_n   (vs_n),
        .frame_tick(ft)
    );

    //--------------------------------------------------------------------------
    // Keys : invert (active low on the board) and debounce
    //--------------------------------------------------------------------------
    wire [3:0] btn_raw = ~btn_n;    // now active high
    wire [3:0] btn;                 // debounced, active high

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_btn
            btn_debounce #(
                .CNT_MAX (252_000),      // 10 ms @ 25.2 MHz
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
    // Logical key events  (btn[0]=LEFT btn[1]=RIGHT btn[2]=UP btn[3]=DOWN)
    //--------------------------------------------------------------------------
    wire left_p, right_p, up_p, down_p, ok_p, back_p, right_held;

    key_ctrl u_key (
        .clk     (pixel_clk),
        .rst     (aRst),
        .k_left  (btn[0]),
        .k_right (btn[1]),
        .k_up    (btn[2]),
        .k_down  (btn[3]),
        .left_p  (left_p),
        .right_p (right_p),
        .up_p    (up_p),
        .down_p  (down_p),
        .ok_p    (ok_p),
        .back_p  (back_p),
        .right_held (right_held)
    );

    //--------------------------------------------------------------------------
    // PS/2 keyboard : A/Left, D/Right, W/Up, S/Down, Space, Enter, P, R, Esc
    //--------------------------------------------------------------------------
    wire kb_left_held;
    wire kb_right_held;
    wire kb_up_held;
    wire kb_down_held;
    wire kb_space_pressed;
    wire kb_enter_pressed;
    wire kb_pause_pressed;
    wire kb_restart_pressed;
    wire kb_escape_pressed;
    wire kb_frame_error;

    ps2_keyboard u_ps2 (
        .clk                 (pixel_clk),
        .rst                 (aRst),
        .ps2_clk             (ps2_clk),
        .ps2_data            (ps2_data),
        .left_held           (kb_left_held),
        .right_held          (kb_right_held),
        .up_held             (kb_up_held),
        .down_held           (kb_down_held),
        .space_pressed       (kb_space_pressed),
        .enter_pressed       (kb_enter_pressed),
        .pause_pressed       (kb_pause_pressed),
        .restart_pressed     (kb_restart_pressed),
        .escape_pressed      (kb_escape_pressed),
        .frame_error_pulse   (kb_frame_error)
    );

    // Turn the keyboard held levels into one-clock menu press pulses.
    reg kb_left_d, kb_right_d, kb_up_d, kb_down_d;
    always @(posedge pixel_clk or posedge aRst) begin
        if (aRst) begin
            kb_left_d  <= 1'b0;
            kb_right_d <= 1'b0;
            kb_up_d   <= 1'b0;
            kb_down_d <= 1'b0;
        end else begin
            kb_left_d  <= kb_left_held;
            kb_right_d <= kb_right_held;
            kb_up_d   <= kb_up_held;
            kb_down_d <= kb_down_held;
        end
    end

    wire kb_left_p = kb_left_held & ~kb_left_d;
    wire kb_right_p = kb_right_held & ~kb_right_d;
    wire kb_up_p   = kb_up_held & ~kb_up_d;
    wire kb_down_p = kb_down_held & ~kb_down_d;

    // Merge board keys and keyboard into the same logical input bus.
    wire ui_left_p  = left_p | kb_left_p;
    wire ui_right_p = right_p | kb_right_p;
    wire ui_up_p    = up_p | kb_up_p;
    wire ui_down_p  = down_p | kb_down_p;
    wire ui_ok_p    = ok_p | kb_space_pressed | kb_enter_pressed;
    wire ui_back_p  = back_p | kb_escape_pressed;
    wire ui_pause_p = kb_pause_pressed;
    wire ui_restart_p = kb_restart_pressed;

    //--------------------------------------------------------------------------
    // OpenMV UART : 115200 8N1, 6-byte frame
    //--------------------------------------------------------------------------
    wire [7:0]  openmv_target_x;
    wire [7:0]  openmv_target_y;
    wire        openmv_target_valid;
    wire        openmv_target_update;
    wire        openmv_target_event;
    wire [15:0] openmv_good_frames;
    wire [15:0] openmv_bad_frames;

    openmv_uart_rx #(
        .CLK_HZ      (25_200_000),
        .BAUD_RATE   (115_200),
        .TIMEOUT_CLKS(12_600_000)
    ) u_openmv (
        .clk          (pixel_clk),
        .rst          (aRst),
        .uart_rx      (openmv_rx),
        .target_x     (openmv_target_x),
        .target_y     (openmv_target_y),
        .target_valid (openmv_target_valid),
        .target_update(openmv_target_update),
        .target_event (openmv_target_event),
        .good_frames  (openmv_good_frames),
        .bad_frames   (openmv_bad_frames)
    );

    //--------------------------------------------------------------------------
    // Scene generator : menu / snake / tetris / flappy / breakout
    // The game cores render directly at the panel's native 480x320.
    //--------------------------------------------------------------------------
    wire [11:0] scene;

    scene_render u_scene (
        .pixel_clk  (pixel_clk),
        .rst        (aRst),
        .de         (de),
        .x          (px),
        .y          (py),
        .frame_tick (ft),
        .left_p     (ui_left_p),
        .right_p    (ui_right_p),
        .up_p       (ui_up_p),
        .down_p     (ui_down_p),
        .ok_p       (ui_ok_p),
        .back_p     (ui_back_p),
        .right_held (right_held),
        .move_left_held  (btn[0] | kb_left_held),
        .move_right_held (btn[1] | kb_right_held),
        .up_held    (kb_up_held),
        .down_held  (kb_down_held),
        .pause_p    (ui_pause_p),
        .restart_p  (ui_restart_p),
        .k_level    (btn),
        .target_x   (openmv_target_x),
        .target_y   (openmv_target_y),
        .target_valid(openmv_target_valid),
        .target_update(openmv_target_update),
        .target_event(openmv_target_event),
        .rgb        (scene)
    );

    //--------------------------------------------------------------------------
    // RGB444 -> RGB888
    //--------------------------------------------------------------------------
    wire [11:0] display_rgb = scene;
    wire [7:0] r8 = {display_rgb[11:8], display_rgb[11:8]};
    wire [7:0] g8 = {display_rgb[ 7:4], display_rgb[ 7:4]};
    wire [7:0] b8 = {display_rgb[ 3:0], display_rgb[ 3:0]};

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
    assign hdmi_out_en = 1'b0;      // ACTIVE LOW : 1'b0 enables the HDMI1 output buffer
    assign led_n       = ~btn;      // board key pressed -> LED lit

    // K5 / K7 held for 0.6 s produce ok_p / back_p, consumed by scene_render.

endmodule
