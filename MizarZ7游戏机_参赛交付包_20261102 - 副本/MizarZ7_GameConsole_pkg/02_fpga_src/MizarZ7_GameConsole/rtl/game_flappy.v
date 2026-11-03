`timescale 1ns / 1ps
//=============================================================================
// game_flappy.v
//   Flappy Bird game core for the 480 x 320 game-console scene.
//
//   Inputs:
//     ok_p/right_p/up_p : start / flap
//     down_p            : dive impulse
//     up_held/down_held : manual keyboard override
//     target_y/valid    : OpenMV face-centre target
//     pause_p           : pause / resume
//     restart_p         : restart round
//
//   While a face is visible, the bird follows the face centre continuously.
//   A per-frame slew limit prevents camera jitter from teleporting the bird.
//=============================================================================
module game_flappy (
    input  wire        pixel_clk,
    input  wire        rst,

    input  wire        de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        frame_tick,

    input  wire        up_p,
    input  wire        down_p,
    input  wire        ok_p,
    input  wire        right_p,
    input  wire        pause_p,
    input  wire        restart_p,
    input  wire        up_held,
    input  wire        down_held,

    input  wire [7:0]  target_y,
    input  wire        target_valid,
    input  wire        target_event,

    output reg  [11:0] rgb,
    output wire        game_over
);

    //--------------------------------------------------------------------------
    // Geometry / palette
    //--------------------------------------------------------------------------
    localparam integer BIRD_X = 96;
    localparam integer BIRD_W = 28;
    localparam integer BIRD_H = 22;
    localparam integer GROUND_Y = 284;
    localparam integer PIPE_SPACING = 220;
    localparam integer PIPE_WRAP_X  = 720;
    localparam integer PIPE_GAP    = 140;
    localparam [12:0] BY_MIN = 13'd16;
    localparam [12:0] BY_MAX = 13'd4192;   // 262 * 16

    localparam [1:0] ST_READY = 2'd0;
    localparam [1:0] ST_PLAY  = 2'd1;
    localparam [1:0] ST_PAUSE = 2'd2;
    localparam [1:0] ST_OVER  = 2'd3;

    localparam [11:0] C_SKY0   = 12'h07D;
    localparam [11:0] C_SKY1   = 12'h08E;
    localparam [11:0] C_CLOUD  = 12'hEEF;
    localparam [11:0] C_CLOUD2 = 12'hCCE;
    localparam [11:0] C_PIPE   = 12'h0B0;
    localparam [11:0] C_PIPE_H = 12'h4F2;
    localparam [11:0] C_PIPE_L = 12'h060;
    localparam [11:0] C_GRASS  = 12'h4C0;
    localparam [11:0] C_GRASS2 = 12'h2A0;
    localparam [11:0] C_DIRT   = 12'h852;
    localparam [11:0] C_DIRT2  = 12'h631;
    localparam [11:0] C_BIRD   = 12'hFF0;
    localparam [11:0] C_WING   = 12'hF80;
    localparam [11:0] C_BEAK   = 12'hF40;
    localparam [11:0] C_EYE    = 12'hFFF;
    localparam [11:0] C_PUPIL  = 12'h000;
    localparam [11:0] C_TEXT   = 12'hFFF;
    localparam [11:0] C_SHADOW = 12'h001;
    localparam [11:0] C_TITLE  = 12'hFF0;
    localparam [11:0] C_READY  = 12'hFF0;
    localparam [11:0] C_OVER   = 12'hF60;
    localparam [11:0] C_DARK   = 12'h012;

    //--------------------------------------------------------------------------
    // State / physics
    //--------------------------------------------------------------------------
    reg [1:0]  state;
    reg [12:0] by_q4;          // bird top, 1/16 pixel units
    reg signed [8:0] vy_q4;    // bird vertical velocity, 1/16 px/frame
    reg [6:0]  score;

    reg [9:0] px0, px1, px2;
    reg [7:0] gap0, gap1, gap2;
    reg       scored0, scored1, scored2;

    reg [15:0] lfsr;
    reg [5:0]  anim;
    reg        flap_req;
    reg        dive_req;
    reg        pipe_div;

    assign game_over = (state == ST_OVER);

    wire manual_flap_event = ok_p | right_p | up_p;
    wire flap_event = manual_flap_event;
    wire dive_event = down_p;

    wire restart_game = restart_p | ((state == ST_OVER) && manual_flap_event);
    wire init_game    = rst | restart_game;

    // Pipe motion is one pixel every two video frames: 30 px/s at 60 Hz.
    wire pipe_tick = frame_tick && pipe_div;

    //--------------------------------------------------------------------------
    // LFSR for new pipe gaps
    //--------------------------------------------------------------------------
    wire lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    wire [7:0] new_gap0 = 8'd32 + {lfsr[6:3], 3'b000};
    wire [7:0] new_gap1 = 8'd32 + {lfsr[10:7], 3'b000};
    wire [7:0] new_gap2 = 8'd32 + {lfsr[14:11], 3'b000};

    //--------------------------------------------------------------------------
    // Velocity controller
    //--------------------------------------------------------------------------

    wire flap_now = flap_req | ((state == ST_PLAY) && flap_event);
    wire dive_now = dive_req | ((state == ST_PLAY) && dive_event);

    reg signed [8:0] vy_ctrl;

    always @(*) begin
        vy_ctrl = vy_q4;

        if (flap_now) begin
            vy_ctrl = -9'sd56;
        end else if (dive_now) begin
            vy_ctrl = 9'sd40;
        end else if (up_held) begin
            if (vy_q4 > -9'sd64) vy_ctrl = vy_q4 - 9'sd8;
        end else if (down_held) begin
            if (vy_q4 < 9'sd64) vy_ctrl = vy_q4 + 9'sd8;
        end else begin
            vy_ctrl = vy_q4 + 9'sd2;
        end

        if (vy_ctrl > 9'sd48)      vy_ctrl = 9'sd48;
        else if (vy_ctrl < -9'sd56) vy_ctrl = -9'sd56;
    end

    wire signed [13:0] next_by_s =
        $signed({1'b0, by_q4}) + $signed(vy_ctrl);

    reg [12:0] next_by;
    always @(*) begin
        if (next_by_s < $signed({1'b0, BY_MIN}))
            next_by = BY_MIN;
        else if (next_by_s > $signed({1'b0, BY_MAX}))
            next_by = BY_MAX;
        else
            next_by = next_by_s[12:0];
    end

    // Map fixed-image eye Y directly into game Y. The midpoint of the eye
    // coordinate range maps to the vertical centre of the bird's safe range.
    wire [15:0] vision_y_scaled = target_y * 16'd226;
    wire [8:0]  vision_top_target = 9'd36 + vision_y_scaled[15:8];
    wire [12:0] vision_target_q4 = {vision_top_target, 4'b0000};

    reg [12:0] vision_next_by;
    always @(*) begin
        if (vision_target_q4 > by_q4 + 13'd64)
            vision_next_by = by_q4 + 13'd64;      // at most 4 px/frame
        else if (vision_target_q4 + 13'd64 < by_q4)
            vision_next_by = by_q4 - 13'd64;
        else
            vision_next_by = vision_target_q4;
    end

    wire vision_follow_enabled = (state == ST_PLAY) && target_valid &&
                                 !up_held && !down_held &&
                                 !flap_now && !dive_now;
    wire [12:0] controlled_next_by =
        vision_follow_enabled ? vision_next_by : next_by;

    wire [8:0] bird_top_next = {1'b0, controlled_next_by[12:4]};
    wire [8:0] bird_bottom_next = bird_top_next + 9'd21;

    //--------------------------------------------------------------------------
    // Collision / scoring
    //--------------------------------------------------------------------------
    wire [9:0] bird_left  = 10'd96;
    wire [9:0] bird_right = 10'd123;
    wire [9:0] p0_right = px0 + 10'd47;
    wire [9:0] p1_right = px1 + 10'd47;
    wire [9:0] p2_right = px2 + 10'd47;

    wire pipe0_overlap = (bird_right >= px0) && (bird_left <= p0_right);
    wire pipe1_overlap = (bird_right >= px1) && (bird_left <= p1_right);
    wire pipe2_overlap = (bird_right >= px2) && (bird_left <= p2_right);

    wire [8:0] gap0_bottom = {1'b0, gap0} + PIPE_GAP;
    wire [8:0] gap1_bottom = {1'b0, gap1} + PIPE_GAP;
    wire [8:0] gap2_bottom = {1'b0, gap2} + PIPE_GAP;

    wire pipe0_hit = pipe0_overlap &&
        ((bird_top_next < {1'b0, gap0}) ||
         (bird_bottom_next > gap0_bottom));
    wire pipe1_hit = pipe1_overlap &&
        ((bird_top_next < {1'b0, gap1}) ||
         (bird_bottom_next > gap1_bottom));
    wire pipe2_hit = pipe2_overlap &&
        ((bird_top_next < {1'b0, gap2}) ||
         (bird_bottom_next > gap2_bottom));

    wire collision = (bird_bottom_next >= 9'd284) ||
                     (bird_top_next <= 9'd2) ||
                     pipe0_hit || pipe1_hit || pipe2_hit;

    //--------------------------------------------------------------------------
    // Main state / game update
    //--------------------------------------------------------------------------
    always @(posedge pixel_clk) begin
        if (init_game) begin
            state    <= ST_READY;
            by_q4    <= 13'd2048;       // y = 128
            vy_q4    <= 9'sd0;
            score    <= 7'd0;
            px0      <= 10'd280;
            px1      <= 10'd500;
            px2      <= 10'd720;
            gap0     <= 8'd58;
            gap1     <= 8'd112;
            gap2     <= 8'd80;
            scored0  <= 1'b0;
            scored1  <= 1'b0;
            scored2  <= 1'b0;
            lfsr     <= 16'hACE1;
            anim     <= 6'd0;
            flap_req <= 1'b0;
            dive_req <= 1'b0;
            pipe_div <= 1'b0;
        end else begin
            if (frame_tick) begin
                anim  <= anim + 6'd1;
                lfsr  <= {lfsr[14:0], lfsr_fb};
                flap_req <= 1'b0;
                dive_req <= 1'b0;
                pipe_div <= ~pipe_div;
            end else begin
                if ((state == ST_PLAY) && flap_event) flap_req <= 1'b1;
                if ((state == ST_PLAY) && dive_event) dive_req <= 1'b1;
            end

            case (state)
                ST_READY: begin
                    if (frame_tick && target_valid) begin
                        by_q4 <= vision_next_by;
                        vy_q4 <= 9'sd0;
                    end
                    if (flap_event) begin
                        state <= ST_PLAY;
                        vy_q4 <= -9'sd56;
                    end
                end

                ST_PLAY: begin
                    if (pause_p) begin
                        state <= ST_PAUSE;
                    end else begin
                        if (frame_tick) begin
                            if (vision_follow_enabled) begin
                                by_q4 <= vision_next_by;
                                vy_q4 <= 9'sd0;
                            end else begin
                                by_q4 <= next_by;
                                vy_q4 <= vy_ctrl;
                            end
                            if (collision) begin
                                state <= ST_OVER;
                            end
                        end

                        if (pipe_tick) begin
                            if (px0 == 0) begin
                                px0 <= 10'd720;
                                gap0 <= new_gap0;
                                scored0 <= 1'b0;
                            end else begin
                                px0 <= px0 - 1'b1;
                            end

                            if (px1 == 0) begin
                                px1 <= 10'd720;
                                gap1 <= new_gap1;
                                scored1 <= 1'b0;
                            end else begin
                                px1 <= px1 - 1'b1;
                            end

                            if (px2 == 0) begin
                                px2 <= 10'd720;
                                gap2 <= new_gap2;
                                scored2 <= 1'b0;
                            end else begin
                                px2 <= px2 - 1'b1;
                            end

                            if (!scored0 && (px0 < 10'd50)) begin
                                scored0 <= 1'b1;
                                if (score < 7'd99) score <= score + 1'b1;
                            end
                            if (!scored1 && (px1 < 10'd50)) begin
                                scored1 <= 1'b1;
                                if (score < 7'd99) score <= score + 1'b1;
                            end
                            if (!scored2 && (px2 < 10'd50)) begin
                                scored2 <= 1'b1;
                                if (score < 7'd99) score <= score + 1'b1;
                            end
                        end
                    end
                end

                ST_PAUSE: begin
                    if (pause_p) state <= ST_PLAY;
                end

                ST_OVER: begin
                    // restart_game handles R / Space / Up / K5.
                end

                default: state <= ST_READY;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Colour helpers
    //--------------------------------------------------------------------------
    function [11:0] up4;
        input [11:0] c;
        input [3:0]  a;
        reg [4:0] r, g, b;
        begin
            r = {1'b0, c[11:8]} + {1'b0, a};
            g = {1'b0, c[ 7:4]} + {1'b0, a};
            b = {1'b0, c[ 3:0]} + {1'b0, a};
            if (r > 5'd15) r = 5'd15;
            if (g > 5'd15) g = 5'd15;
            if (b > 5'd15) b = 5'd15;
            up4 = {r[3:0], g[3:0], b[3:0]};
        end
    endfunction

    function [11:0] dn4;
        input [11:0] c;
        input [3:0]  a;
        reg [3:0] r, g, b;
        begin
            r = (c[11:8] > a) ? (c[11:8] - a) : 4'h0;
            g = (c[ 7:4] > a) ? (c[ 7:4] - a) : 4'h0;
            b = (c[ 3:0] > a) ? (c[ 3:0] - a) : 4'h0;
            dn4 = {r, g, b};
        end
    endfunction

    function [11:0] sky_at;
        input [8:0] yy;
        begin
            case (yy[8:5])
                4'd0: sky_at = 12'h07D;
                4'd1: sky_at = 12'h08E;
                4'd2: sky_at = 12'h09F;
                4'd3: sky_at = 12'h08E;
                4'd4: sky_at = 12'h07D;
                4'd5: sky_at = 12'h06C;
                4'd6: sky_at = 12'h05B;
                4'd7: sky_at = 12'h04A;
                4'd8: sky_at = 12'h039;
                default: sky_at = 12'h028;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Pipe drawing
    //--------------------------------------------------------------------------
    wire [11:0] p0_end = {2'b00, px0} + 12'd47;
    wire [11:0] p1_end = {2'b00, px1} + 12'd47;
    wire [11:0] p2_end = {2'b00, px2} + 12'd47;
    wire [11:0] gap0x = {4'b0000, gap0};
    wire [11:0] gap1x = {4'b0000, gap1};
    wire [11:0] gap2x = {4'b0000, gap2};
    wire [11:0] gap0b = gap0x + PIPE_GAP;
    wire [11:0] gap1b = gap1x + PIPE_GAP;
    wire [11:0] gap2b = gap2x + PIPE_GAP;

    wire pipe0_top = de && (y < 12'd284) &&
                     (x >= {2'b00, px0}) && (x < p0_end) && (y < gap0x);
    wire pipe0_bot = de && (y >= gap0b) && (y < 12'd284) &&
                     (x >= {2'b00, px0}) && (x < p0_end);
    wire pipe1_top = de && (y < 12'd284) &&
                     (x >= {2'b00, px1}) && (x < p1_end) && (y < gap1x);
    wire pipe1_bot = de && (y >= gap1b) && (y < 12'd284) &&
                     (x >= {2'b00, px1}) && (x < p1_end);
    wire pipe2_top = de && (y < 12'd284) &&
                     (x >= {2'b00, px2}) && (x < p2_end) && (y < gap2x);
    wire pipe2_bot = de && (y >= gap2b) && (y < 12'd284) &&
                     (x >= {2'b00, px2}) && (x < p2_end);

    wire pipe_hit = pipe0_top || pipe0_bot ||
                    pipe1_top || pipe1_bot ||
                    pipe2_top || pipe2_bot;

    wire pipe0_edge = pipe0_top || pipe0_bot;
    wire pipe1_edge = pipe1_top || pipe1_bot;
    wire pipe2_edge = pipe2_top || pipe2_bot;
    wire pipe_hi =
        (pipe0_edge && (((x >= {2'b00, px0}) && (x < {2'b00, px0} + 12'd4)) ||
                        (pipe0_top && (y + 12'd1 >= gap0x)) ||
                        (pipe0_bot && (y < gap0b + 12'd4)))) ||
        (pipe1_edge && (((x >= {2'b00, px1}) && (x < {2'b00, px1} + 12'd4)) ||
                        (pipe1_top && (y + 12'd1 >= gap1x)) ||
                        (pipe1_bot && (y < gap1b + 12'd4)))) ||
        (pipe2_edge && (((x >= {2'b00, px2}) && (x < {2'b00, px2} + 12'd4)) ||
                        (pipe2_top && (y + 12'd1 >= gap2x)) ||
                        (pipe2_bot && (y < gap2b + 12'd4))));
    wire pipe_lo =
        (pipe0_edge && (x >= p0_end - 12'd4)) ||
        (pipe1_edge && (x >= p1_end - 12'd4)) ||
        (pipe2_edge && (x >= p2_end - 12'd4));

    //--------------------------------------------------------------------------
    // Bird drawing
    //--------------------------------------------------------------------------
    wire [11:0] bird_top_draw = {3'b000, by_q4[12:4]} +
        (((state == ST_READY) && anim[4]) ? 12'd2 : 12'd0);
    wire [11:0] bird_dx = x - 12'd96;
    wire [11:0] bird_dy = y - bird_top_draw;

    wire bird_box = de && (x >= 12'd96) && (x < 12'd134) &&
                    (y >= bird_top_draw) &&
                    (y < bird_top_draw + 12'd22);
    wire bird_body_raw = bird_box && (bird_dx < 12'd28) &&
                         (bird_dy < 12'd22);
    wire bird_corner_cut = bird_body_raw &&
        ((bird_dx < 12'd3) || (bird_dx >= 12'd25)) &&
        ((bird_dy < 12'd3) || (bird_dy >= 12'd19));
    wire bird_body = bird_body_raw && !bird_corner_cut;
    wire bird_wing = bird_body &&
                     (bird_dx >= 12'd6) && (bird_dx < 12'd19) &&
                     (bird_dy >= 12'd8) && (bird_dy < 12'd16);
    wire bird_eye = bird_body &&
                    (bird_dx >= 12'd18) && (bird_dx < 12'd25) &&
                    (bird_dy >= 12'd3) && (bird_dy < 12'd10);
    wire bird_pupil = bird_body &&
                      (bird_dx >= 12'd20) && (bird_dx < 12'd23) &&
                      (bird_dy >= 12'd5) && (bird_dy < 12'd9);
    wire bird_beak = bird_box &&
                     (bird_dx >= 12'd24) && (bird_dx < 12'd38) &&
                     (bird_dy >= 12'd10) && (bird_dy < 12'd16);

    //--------------------------------------------------------------------------
    // Text overlays
    //--------------------------------------------------------------------------
    wire title_in, title_fg;
    wire ready_in, ready_fg;
    wire over_in, over_fg;
    wire retry_in, retry_fg;
    wire restart_in, restart_fg;
    wire pause_in, pause_fg;
    wire resume_in, resume_fg;
    wire score_in, score_fg;

    text_line #(
        .X0 (152), .Y0 (36), .SCALE (2), .NCH (11),
        .TEXT (88'h464C415050592042495244)
    ) u_title (.de(de), .x(x), .y(y), .inside(title_in), .fg(title_fg));

    text_line #(
        .X0 (152), .Y0 (178), .SCALE (2), .NCH (11),
        .TEXT (88'h5052455353205350414345)
    ) u_ready (.de(de), .x(x), .y(y), .inside(ready_in), .fg(ready_fg));

    text_line #(
        .X0 (168), .Y0 (124), .SCALE (2), .NCH (9),
        .TEXT (72'h47414D45204F564552)
    ) u_over (.de(de), .x(x), .y(y), .inside(over_in), .fg(over_fg));

    text_line #(
        .X0 (160), .Y0 (164), .SCALE (2), .NCH (10),
        .TEXT (80'h4B35_2052_4553_5441_5254)
    ) u_retry (.de(de), .x(x), .y(y), .inside(retry_in), .fg(retry_fg));

    text_line #(
        .X0 (136), .Y0 (192), .SCALE (2), .NCH (13),
        .TEXT (104'h4B34_204F_5220_4B37_2045_5849_54)
    ) u_restart (.de(de), .x(x), .y(y), .inside(restart_in), .fg(restart_fg));

    text_line #(
        .X0 (192), .Y0 (136), .SCALE (2), .NCH (6),
        .TEXT (48'h504155534544)
    ) u_pause (.de(de), .x(x), .y(y), .inside(pause_in), .fg(pause_fg));

    text_line #(
        .X0 (168), .Y0 (180), .SCALE (2), .NCH (8),
        .TEXT (64'h5020524553554D45)
    ) u_resume (.de(de), .x(x), .y(y), .inside(resume_in), .fg(resume_fg));

    text_line #(
        .X0 (332), .Y0 (8), .SCALE (2), .NCH (5),
        .TEXT (40'h53434F5245)
    ) u_score (.de(de), .x(x), .y(y), .inside(score_in), .fg(score_fg));

    wire [3:0] score_tens = score / 10;
    wire [3:0] score_ones = score % 10;
    wire [7:0] tens_ch = 8'h30 + {4'b0000, score_tens};
    wire [7:0] ones_ch = 8'h30 + {4'b0000, score_ones};
    wire [7:0] tens_bits, ones_bits;

    font_rom u_tens (.ch(tens_ch), .row((y - 12'd8) >> 1), .bits(tens_bits));
    font_rom u_ones (.ch(ones_ch), .row((y - 12'd8) >> 1), .bits(ones_bits));

    wire tens_in = de && (x >= 12'd424) && (x < 12'd440) &&
                   (y >= 12'd8) && (y < 12'd24);
    wire ones_in = de && (x >= 12'd444) && (x < 12'd460) &&
                   (y >= 12'd8) && (y < 12'd24);
    wire [2:0] tens_col = (x - 12'd424) >> 1;
    wire [2:0] ones_col = (x - 12'd444) >> 1;
    wire tens_fg = tens_in && tens_bits[7 - tens_col];
    wire ones_fg = ones_in && ones_bits[7 - ones_col];

    //--------------------------------------------------------------------------
    // Background / ground / clouds
    //--------------------------------------------------------------------------
    wire cloud_a = de && (x >= 12'd38) && (x < 12'd122) &&
                   (y >= 12'd42) && (y < 12'd62);
    wire cloud_b = de && (x >= 12'd208) && (x < 12'd292) &&
                   (y >= 12'd78) && (y < 12'd98);
    wire cloud_c = de && (x >= 12'd344) && (x < 12'd428) &&
                   (y >= 12'd52) && (y < 12'd72);
    wire cloud =
        (cloud_a && !((x < 12'd46) && (y > 12'd56))) ||
        (cloud_b && !((x > 12'd284) && (y < 12'd84))) ||
        (cloud_c && !((x < 12'd352) && (y < 12'd58)));

    wire ground = de && (y >= 12'd284);
    wire grass = ground && (y < 12'd292);
    wire dirt_stripe = ground && (y >= 12'd292) && (((x >> 4) + (y >> 3)) & 1);

    //--------------------------------------------------------------------------
    // Composite
    //--------------------------------------------------------------------------
    wire over_box = (state == ST_OVER) &&
                    (x >= 12'd112) && (x < 12'd368) &&
                    (y >= 12'd102) && (y < 12'd220);
    wire pause_box = (state == ST_PAUSE) &&
                     (x >= 12'd144) && (x < 12'd336) &&
                     (y >= 12'd112) && (y < 12'd212);
    wire ready_box = (state == ST_READY) &&
                     (x >= 12'd132) && (x < 12'd348) &&
                     (y >= 12'd166) && (y < 12'd206);

    wire vision_dot = de && (x >= 12'd460) && (x < 12'd472) &&
                      (y >= 12'd8) && (y < 12'd20);

    always @(*) begin
        if (state == ST_OVER && over_fg)         rgb = C_OVER;
        else if (state == ST_OVER && retry_fg)   rgb = C_TEXT;
        else if (state == ST_OVER && restart_fg) rgb = C_TEXT;
        else if (state == ST_PAUSE && pause_fg)  rgb = C_TITLE;
        else if (state == ST_PAUSE && resume_fg) rgb = C_TEXT;
        else if (state == ST_READY && title_fg)  rgb = C_TITLE;
        else if (state == ST_READY && ready_fg)  rgb = C_READY;
        else if (over_box)                 rgb = C_DARK;
        else if (pause_box)                rgb = C_DARK;
        else if (ready_box)                rgb = 12'h024;
        else if (score_fg || tens_fg || ones_fg) rgb = C_TEXT;
        else if (vision_dot) rgb = target_valid ? 12'h0F0 : 12'h700;
        else if (bird_pupil) rgb = C_PUPIL;
        else if (bird_eye)   rgb = C_EYE;
        else if (bird_wing)  rgb = C_WING;
        else if (bird_beak)  rgb = C_BEAK;
        else if (bird_body)  rgb = C_BIRD;
        else if (pipe_hit)   rgb = pipe_hi ? C_PIPE_H :
                                    pipe_lo ? C_PIPE_L : C_PIPE;
        else if (grass)      rgb = ((x >> 5) & 1) ? C_GRASS : C_GRASS2;
        else if (ground)     rgb = dirt_stripe ? C_DIRT : C_DIRT2;
        else if (cloud)      rgb = ((x >> 4) & 1) ? C_CLOUD : C_CLOUD2;
        else                  rgb = sky_at(y[8:0]);
    end

endmodule
