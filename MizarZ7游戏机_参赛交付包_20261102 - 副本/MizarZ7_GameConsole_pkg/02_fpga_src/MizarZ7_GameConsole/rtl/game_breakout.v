`timescale 1ns / 1ps
//=============================================================================
// game_breakout.v
//   Classic brick-breaker for the 480 x 320 game-console scene.
//
//   K4 / K5 short taps : move paddle left / right
//   K6 tap             : launch ball, retry after game over / win
//   K7 long            : return to menu (handled by scene_render)
//=============================================================================
module game_breakout (
    input  wire        pixel_clk,
    input  wire        rst,

    input  wire        de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        frame_tick,

    input  wire        left_p,
    input  wire        right_p,
    input  wire        move_left_held,
    input  wire        move_right_held,
    input  wire        up_p,
    input  wire        ok_p,
    input  wire        restart_p,
    input  wire [7:0]  target_x,
    input  wire        target_valid,
    input  wire        target_update,

    output reg  [11:0] rgb,
    output wire        game_over
);

    localparam [1:0] ST_READY = 2'd0;
    localparam [1:0] ST_PLAY  = 2'd1;
    localparam [1:0] ST_WIN   = 2'd2;
    localparam [1:0] ST_OVER  = 2'd3;

    localparam integer PLAY_LEFT  = 16;
    localparam integer PLAY_RIGHT = 464;
    localparam integer PLAY_TOP   = 32;
    localparam integer PADDLE_Y   = 286;
    localparam integer PADDLE_W   = 72;
    localparam integer BALL_SZ    = 8;
    localparam integer BRICK_X    = 48;
    localparam integer BRICK_Y    = 48;
    localparam integer BRICK_W    = 32;
    localparam integer BRICK_H    = 16;
    localparam integer BRICK_COLS = 12;
    localparam integer BRICK_ROWS = 6;

    localparam [11:0] C_BG0   = 12'h012;
    localparam [11:0] C_BG1   = 12'h024;
    localparam [11:0] C_FRAME = 12'h0FF;
    localparam [11:0] C_TEXT  = 12'hFFF;
    localparam [11:0] C_PAD   = 12'h0CF;
    localparam [11:0] C_PADHI = 12'h4FF;
    localparam [11:0] C_BALL  = 12'hFFF;
    localparam [11:0] C_DARK  = 12'h012;
    localparam [11:0] C_WIN   = 12'h0F0;
    localparam [11:0] C_OVER  = 12'hF60;

    reg [1:0]  state;
    reg [9:0]  paddle_x;
    reg [9:0]  vision_goal_x;
    reg [9:0]  ball_x;
    reg [9:0]  ball_y;
    reg signed [4:0] vx;
    reg signed [4:0] vy;
    reg [9:0]  score;
    reg [2:0]  lives;
    reg [71:0] bricks;

    reg [9:0]  upd_x;
    reg [9:0]  upd_y;
    reg signed [4:0] upd_vx;
    reg signed [4:0] upd_vy;
    reg        miss;
    reg        brick_hit;
    reg [6:0]  brick_idx;

    assign game_over = (state == ST_OVER) || (state == ST_WIN);

    wire launch = up_p | ok_p;
    wire signed [10:0] next_x = $signed({1'b0, ball_x}) + vx;
    wire signed [10:0] next_y = $signed({1'b0, ball_y}) + vy;
    wire [9:0] paddle_max = PLAY_RIGHT - PADDLE_W;
    wire [9:0] vision_span = paddle_max - PLAY_LEFT;
    wire [16:0] vision_scaled = target_x * vision_span;
    wire [9:0] vision_goal_next = PLAY_LEFT + vision_scaled[16:8];

    //--------------------------------------------------------------------------
    // Ball movement and collision pre-calculation
    //--------------------------------------------------------------------------
    always @(*) begin
        upd_x  = next_x[9:0];
        upd_y  = next_y[9:0];
        upd_vx = vx;
        upd_vy = vy;
        miss   = 1'b0;
        brick_hit = 1'b0;
        brick_idx = 7'd0;

        if (next_x < PLAY_LEFT) begin
            upd_x = PLAY_LEFT;
            upd_vx = 5'sd3;
        end else if (next_x > PLAY_RIGHT - BALL_SZ) begin
            upd_x = PLAY_RIGHT - BALL_SZ;
            upd_vx = -5'sd3;
        end

        if (next_y < PLAY_TOP) begin
            upd_y = PLAY_TOP;
            upd_vy = 5'sd3;
        end

        // Paddle collision
        if ((state == ST_PLAY) && (upd_vy > 0) &&
            (upd_y + BALL_SZ >= PADDLE_Y) &&
            (upd_y < PADDLE_Y + 10) &&
            (upd_x + BALL_SZ >= paddle_x) &&
            (upd_x <= paddle_x + PADDLE_W - 1)) begin
            upd_y = PADDLE_Y - BALL_SZ;
            upd_vy = -5'sd3;
            if (upd_x + 4 < paddle_x + 18)
                upd_vx = -5'sd3;
            else if (upd_x + 4 < paddle_x + 36)
                upd_vx = -5'sd2;
            else if (upd_x + 4 < paddle_x + 54)
                upd_vx = 5'sd2;
            else
                upd_vx = 5'sd3;
        end

        // Brick collision using the ball center
        if ((state == ST_PLAY) &&
            (upd_x + 4 >= BRICK_X) &&
            (upd_x + 4 < BRICK_X + BRICK_COLS * BRICK_W) &&
            (upd_y + 4 >= BRICK_Y) &&
            (upd_y + 4 < BRICK_Y + BRICK_ROWS * BRICK_H)) begin
            brick_idx = ((upd_y + 4 - BRICK_Y) >> 4) * BRICK_COLS +
                        ((upd_x + 4 - BRICK_X) >> 5);
            if (bricks[brick_idx]) begin
                brick_hit = 1'b1;
                upd_x = ball_x;
                upd_y = ball_y;
                upd_vy = -vy;
            end
        end

        if ((state == ST_PLAY) && (upd_y > 300))
            miss = 1'b1;
    end

    //--------------------------------------------------------------------------
    // Paddle and game state
    //--------------------------------------------------------------------------
    always @(posedge pixel_clk) begin
        if (rst) begin
            state    <= ST_READY;
            paddle_x <= 10'd204;
            vision_goal_x <= 10'd204;
            ball_x   <= 10'd240;
            ball_y   <= 10'd278;
            vx       <= 5'sd2;
            vy       <= -5'sd3;
            score    <= 10'd0;
            lives    <= 3'd3;
            bricks   <= {72{1'b1}};
        end else begin
            if (target_update && target_valid)
                vision_goal_x <= vision_goal_next;

            // Short taps move one step; held A/D or arrow keys move smoothly.
            if ((state == ST_READY) || (state == ST_PLAY)) begin
                if (left_p) begin
                    if (paddle_x >= PLAY_LEFT + 16)
                        paddle_x <= paddle_x - 16;
                    else
                        paddle_x <= PLAY_LEFT;
                end else if (right_p) begin
                    if (paddle_x + 16 <= paddle_max)
                        paddle_x <= paddle_x + 16;
                    else
                        paddle_x <= paddle_max;
                end else if (frame_tick) begin
                    if (move_left_held) begin
                        if (paddle_x >= PLAY_LEFT + 4)
                            paddle_x <= paddle_x - 4;
                        else
                            paddle_x <= PLAY_LEFT;
                    end else if (move_right_held) begin
                        if (paddle_x + 4 <= paddle_max)
                            paddle_x <= paddle_x + 4;
                        else
                            paddle_x <= paddle_max;
                    end else if (target_valid) begin
                        if (paddle_x + 10'd8 < vision_goal_x)
                            paddle_x <= paddle_x + 10'd8;
                        else if (paddle_x > vision_goal_x + 10'd8)
                            paddle_x <= paddle_x - 10'd8;
                        else
                            paddle_x <= vision_goal_x;
                    end
                end
            end

            if ((state == ST_OVER) || (state == ST_WIN)) begin
                if (launch || restart_p) begin
                    state    <= ST_PLAY;
                    paddle_x <= 10'd204;
                    ball_x   <= 10'd240;
                    ball_y   <= 10'd240;
                    vx       <= 5'sd2;
                    vy       <= -5'sd3;
                    score    <= 10'd0;
                    lives    <= 3'd3;
                    bricks   <= {72{1'b1}};
                end
            end else if (state == ST_READY) begin
                ball_x <= paddle_x + 32;
                ball_y <= PADDLE_Y - BALL_SZ;
                if (launch) begin
                    state <= ST_PLAY;
                    vx <= 5'sd2;
                    vy <= -5'sd3;
                end
            end else if (state == ST_PLAY) begin
                if (bricks == 72'd0) begin
                    state <= ST_WIN;
                end else if (frame_tick) begin
                    if (miss) begin
                        if (lives > 1) begin
                            lives  <= lives - 1'b1;
                            state  <= ST_READY;
                            ball_x <= paddle_x + 32;
                            ball_y <= PADDLE_Y - BALL_SZ;
                            vx     <= 5'sd2;
                            vy     <= -5'sd3;
                        end else begin
                            lives <= 3'd0;
                            state <= ST_OVER;
                        end
                    end else begin
                        ball_x <= upd_x;
                        ball_y <= upd_y;
                        vx     <= upd_vx;
                        vy     <= upd_vy;
                        if (brick_hit) begin
                            bricks[brick_idx] <= 1'b0;
                            score <= score + 10;
                        end
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Palette / drawing helpers
    //--------------------------------------------------------------------------
    function [11:0] bg_at;
        input [8:0] yy;
        begin
            case (yy[8:6])
                3'd0: bg_at = 12'h012;
                3'd1: bg_at = 12'h023;
                3'd2: bg_at = 12'h034;
                3'd3: bg_at = 12'h045;
                default: bg_at = 12'h056;
            endcase
        end
    endfunction

    function [11:0] brick_color;
        input [2:0] rr;
        begin
            case (rr)
                3'd0: brick_color = 12'hF44;
                3'd1: brick_color = 12'hFA0;
                3'd2: brick_color = 12'hFF0;
                3'd3: brick_color = 12'h4F4;
                3'd4: brick_color = 12'h4CF;
                3'd5: brick_color = 12'h48F;
                default: brick_color = 12'hFFF;
            endcase
        end
    endfunction

    wire in_brick_area = de && (x >= BRICK_X) &&
                         (x < BRICK_X + BRICK_COLS * BRICK_W) &&
                         (y >= BRICK_Y) &&
                         (y < BRICK_Y + BRICK_ROWS * BRICK_H);
    wire [11:0] bx = x - BRICK_X;
    wire [11:0] by = y - BRICK_Y;
    wire [3:0]  bcol = bx[8:5];
    wire [2:0]  brow = by[7:4];
    wire [6:0]  bidx = brow * BRICK_COLS + bcol;
    wire brick_alive = in_brick_area && bricks[bidx];
    wire [11:0] bcolr = brick_color(brow);
    wire brick_edge = (bx[4:0] == 0) || (by[3:0] == 0) ||
                      (bx[4:0] == 31) || (by[3:0] == 15);

    wire paddle_hit = de && (y >= PADDLE_Y) && (y < PADDLE_Y + 10) &&
                      (x >= paddle_x) && (x < paddle_x + PADDLE_W);
    wire ball_hit = de && (x >= ball_x) && (x < ball_x + BALL_SZ) &&
                    (y >= ball_y) && (y < ball_y + BALL_SZ);
    wire vision_dot = de && (x >= 452) && (x < 468) &&
                      (y >= 8) && (y < 24);
    wire frame = de && ((x < 2) || (x >= 478) || (y < 2) || (y >= 318));

    //--------------------------------------------------------------------------
    // HUD
    //--------------------------------------------------------------------------
    wire score_t_in, score_t_fg, lives_t_in, lives_t_fg;
    text_line #(.X0(16), .Y0(8), .SCALE(2), .NCH(5),
                .TEXT(40'h5343_4F52_45))
        u_score_text (.de(de), .x(x), .y(y), .inside(score_t_in), .fg(score_t_fg));
    text_line #(.X0(300), .Y0(8), .SCALE(2), .NCH(5),
                .TEXT(40'h4C49_5645_53))
        u_lives_text (.de(de), .x(x), .y(y), .inside(lives_t_in), .fg(lives_t_fg));

    wire [3:0] score_h = (score / 100) % 10;
    wire [3:0] score_t = (score / 10) % 10;
    wire [3:0] score_o = score % 10;
    wire [7:0] hch = 8'h30 + {4'b0000, score_h};
    wire [7:0] tch = 8'h30 + {4'b0000, score_t};
    wire [7:0] och = 8'h30 + {4'b0000, score_o};
    wire [7:0] lch = 8'h30 + {3'b000, lives};
    wire [7:0] hbits, tbits, obits, lbits;
    wire [2:0] hud_row = (y - 12'd8) >> 1;

    font_rom u_h (.ch(hch), .row(hud_row), .bits(hbits));
    font_rom u_t (.ch(tch), .row(hud_row), .bits(tbits));
    font_rom u_o (.ch(och), .row(hud_row), .bits(obits));
    font_rom u_l (.ch(lch), .row(hud_row), .bits(lbits));

    wire h_in = de && (x >= 104) && (x < 120) && (y >= 8) && (y < 24);
    wire t_in = de && (x >= 120) && (x < 136) && (y >= 8) && (y < 24);
    wire o_in = de && (x >= 136) && (x < 152) && (y >= 8) && (y < 24);
    wire l_in = de && (x >= 388) && (x < 404) && (y >= 8) && (y < 24);
    wire h_fg = h_in && hbits[7 - ((x - 104) >> 1)];
    wire t_fg = t_in && tbits[7 - ((x - 120) >> 1)];
    wire o_fg = o_in && obits[7 - ((x - 136) >> 1)];
    wire l_fg = l_in && lbits[7 - ((x - 388) >> 1)];

    //--------------------------------------------------------------------------
    // Overlays
    //--------------------------------------------------------------------------
    wire go_in, go_fg, retry_in, retry_fg, exit_in, exit_fg;
    wire ready_in, ready_fg, win_in, win_fg;

    text_line #(.X0(168), .Y0(124), .SCALE(2), .NCH(9),
                .TEXT(72'h4741_4D45_204F_5645_52))
        u_go (.de(de), .x(x), .y(y), .inside(go_in), .fg(go_fg));
    text_line #(.X0(160), .Y0(164), .SCALE(2), .NCH(10),
                .TEXT(80'h4B36_2052_4553_5441_5254))
        u_retry (.de(de), .x(x), .y(y), .inside(retry_in), .fg(retry_fg));
    text_line #(.X0(136), .Y0(192), .SCALE(2), .NCH(13),
                .TEXT(104'h4B34_204F_5220_4B37_2045_5849_54))
        u_exit (.de(de), .x(x), .y(y), .inside(exit_in), .fg(exit_fg));
    text_line #(.X0(128), .Y0(164), .SCALE(2), .NCH(14),
                .TEXT(112'h5052_4553_5320_4B36_2054_4F20_474F))
        u_ready (.de(de), .x(x), .y(y), .inside(ready_in), .fg(ready_fg));
    text_line #(.X0(184), .Y0(124), .SCALE(2), .NCH(7),
                .TEXT(56'h594F_5520_5749_4E))
        u_win (.de(de), .x(x), .y(y), .inside(win_in), .fg(win_fg));

    wire ready_box = (state == ST_READY) && (x >= 112) && (x < 368) &&
                     (y >= 150) && (y < 202);
    wire go_box = ((state == ST_OVER) || (state == ST_WIN)) &&
                  (x >= 112) && (x < 368) && (y >= 110) && (y < 224);

    always @(*) begin
        if ((state == ST_OVER) && go_fg)       rgb = C_OVER;
        else if ((state == ST_WIN) && win_fg)  rgb = C_WIN;
        else if ((state == ST_OVER || state == ST_WIN) && retry_fg) rgb = C_TEXT;
        else if ((state == ST_OVER || state == ST_WIN) && exit_fg)  rgb = C_TEXT;
        else if ((state == ST_READY) && ready_fg) rgb = C_TEXT;
        else if (go_box)                       rgb = C_DARK;
        else if (ready_box)                    rgb = 12'h034;
        else if (vision_dot)                   rgb = target_valid ? 12'h0F0 : 12'h700;
        else if (score_t_fg || lives_t_fg || h_fg || t_fg || o_fg || l_fg)
            rgb = C_TEXT;
        else if (ball_hit)                     rgb = C_BALL;
        else if (paddle_hit)                   rgb = (y == PADDLE_Y) ? C_PADHI : C_PAD;
        else if (brick_alive)                  rgb = brick_edge ? C_DARK : bcolr;
        else if (frame)                        rgb = C_FRAME;
        else                                    rgb = bg_at(y[8:0]);
    end

endmodule
