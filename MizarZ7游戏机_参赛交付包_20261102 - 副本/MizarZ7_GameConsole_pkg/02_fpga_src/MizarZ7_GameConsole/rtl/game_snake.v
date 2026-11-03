`timescale 1ns / 1ps
//=============================================================================
// game_snake.v
//   SNAKE game.  The whole module is a function of the video beam position plus
//   four logical key pulses, and it runs on the 74.25 MHz pixel clock.
//
//   Field : 28 x 18 cells of 16 x 16 px, origin (16, 24) -> 448 x 288 px
//   Top strip (y 0..23) carries the "SCORE nn" line.
//
//   Speed : one cell per SPEED frames  (8 frames @60 Hz -> 7.5 cells/s)
//
//   The snake body is a shift register of MAXLEN cells, index 0 = head.
//   Only entries below "len" are ever read, so the tail is always valid.
//
//   Keys : left_p / up_p   -> fire on the PRESS edge
//          right_p/down_p  -> fire on the RELEASE edge of a short press
//     A direction request is latched and applied at the next cell step, and is
//     rejected if it would reverse the current direction.
//
//   Death : wall or self hit.  On the game-over overlay, right_p (K5) restarts.
//=============================================================================
module game_snake (
    input  wire        pixel_clk,
    input  wire        rst,          // held high while the snake state is inactive

    input  wire        de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        frame_tick,   // one pixel-clock pulse per frame

    input  wire        left_p,
    input  wire        right_p,
    input  wire        up_p,
    input  wire        down_p,

    output reg  [11:0] rgb,
    output wire        game_over
);

    //--------------------------------------------------------------------------
    // Geometry
    //--------------------------------------------------------------------------
    localparam integer CELL = 16;
    localparam integer COLS = 28;
    localparam integer ROWS = 18;
    localparam integer X0   = 16;
    localparam integer Y0   = 24;
    localparam integer FW   = COLS * CELL;      // 448
    localparam integer FH   = ROWS * CELL;      // 288

    localparam integer MAXLEN = 64;
    localparam integer SPEED  = 8;

    localparam [1:0] DIR_R = 2'd0;
    localparam [1:0] DIR_L = 2'd1;
    localparam [1:0] DIR_U = 2'd2;
    localparam [1:0] DIR_D = 2'd3;

    //--------------------------------------------------------------------------
    // Palette (RGB444) - fully saturated hues
    //--------------------------------------------------------------------------
    localparam [11:0] C_RING   = 12'h0FF;   // border around the play field
    localparam [11:0] C_BODY   = 12'h0F0;   // snake body, vivid green
    localparam [11:0] C_HEAD   = 12'hFF0;   // snake head, yellow
    localparam [11:0] C_FOOD   = 12'hF00;   // food, red
    localparam [11:0] C_FOOD2  = 12'hF60;   // food, pulsed brighter
    localparam [11:0] C_EAT    = 12'hFFF;   // head flash while swallowing
    localparam [11:0] C_TEXT   = 12'hFFF;   // score / hints
    localparam [11:0] C_GO_BG  = 12'h013;   // game-over box
    localparam [11:0] C_GO_T1  = 12'hF60;   // "GAME OVER"
    localparam [11:0] C_GO_T2  = 12'hFFF;   // hints

    //--------------------------------------------------------------------------
    // Colour helpers : per channel saturating add / subtract, so a flat hue can
    // be turned into a lit and a shaded version of itself.  Keeping the shift on
    // each channel separate is what stops the nibbles bleeding into each other.
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

    //--------------------------------------------------------------------------
    // Field background : 10-band vertical gradient (32 px per band), dark teal
    // through to deep blue.  Every other cell is one step brighter, which keeps
    // the 16 px cell grid readable without drawing a grid.
    //--------------------------------------------------------------------------
    function [11:0] bg_at;
        input [8:0] yy;
        begin
            case (yy[8:5])
                4'd0: bg_at = 12'h012;
                4'd1: bg_at = 12'h013;
                4'd2: bg_at = 12'h014;
                4'd3: bg_at = 12'h025;
                4'd4: bg_at = 12'h026;
                4'd5: bg_at = 12'h037;
                4'd6: bg_at = 12'h038;
                4'd7: bg_at = 12'h049;
                4'd8: bg_at = 12'h04A;
                default: bg_at = 12'h05B;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // State
    //--------------------------------------------------------------------------
    reg [4:0] bx [0:MAXLEN-1];
    reg [4:0] by [0:MAXLEN-1];
    reg [6:0] len;

    reg [1:0] dir, dir_req;         // committed / pending direction

    reg [4:0] fx, fy;               // food
    reg       food_valid;

    reg       alive;
    reg [6:0] score;                // cells eaten (max 99)

    reg [3:0] div;                  // frame divider
    reg [15:0] lfsr;

    reg [5:0] anim;                 // free running frame counter (cosmetics)
    reg [3:0] eat_t;                // head flash countdown after a meal

    integer i, k;

    assign game_over = !alive;

    //--------------------------------------------------------------------------
    // A restart is a full re-init of everything that follows.
    //--------------------------------------------------------------------------
    wire restart = !alive && right_p;
    wire init    = rst || restart;

    //--------------------------------------------------------------------------
    // Timing
    //--------------------------------------------------------------------------
    always @(posedge pixel_clk) begin
        if (init) div <= 4'd0;
        else if (frame_tick) div <= (div == SPEED - 1) ? 4'd0 : (div + 4'd1);
    end

    wire step = frame_tick && (div == SPEED - 1);

    //--------------------------------------------------------------------------
    // 16-bit maximal-length LFSR (x^16 + x^14 + x^13 + x^11 + 1), free running
    //--------------------------------------------------------------------------
    wire lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    always @(posedge pixel_clk) begin
        if (init) lfsr <= 16'hACE1;
        else if (frame_tick) lfsr <= {lfsr[14:0], lfsr_fb};
    end

    // food candidate, clamped into the field
    wire [4:0] rx = lfsr[4:0];
    wire [4:0] ry = lfsr[9:5];
    wire [4:0] nfx = (rx >= COLS) ? (rx - COLS) : rx;   // 0..27
    wire [4:0] nfy = (ry >= ROWS) ? (ry - ROWS) : ry;   // 0..17

    //--------------------------------------------------------------------------
    // Direction request
    //--------------------------------------------------------------------------
    always @(posedge pixel_clk) begin
        if (init) begin
            dir     <= DIR_R;
            dir_req <= DIR_R;
        end else begin
            if (step && alive) begin
                dir <= dir_req;
            end

            // Accept every valid press. A newer press may replace the pending
            // direction before the next cell step, but a direct U-turn is never
            // allowed against the last committed direction.
            if (alive) begin
                if      (left_p  && dir != DIR_R) dir_req <= DIR_L;
                else if (right_p && dir != DIR_L) dir_req <= DIR_R;
                else if (up_p    && dir != DIR_D) dir_req <= DIR_U;
                else if (down_p  && dir != DIR_U) dir_req <= DIR_D;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Next head cell
    //--------------------------------------------------------------------------
    wire [4:0] hx = bx[0];
    wire [4:0] hy = by[0];

    wire [4:0] nx = (dir_req == DIR_R) ? (hx + 5'd1) :
                    (dir_req == DIR_L) ? (hx - 5'd1) : hx;
    wire [4:0] ny = (dir_req == DIR_D) ? (hy + 5'd1) :
                    (dir_req == DIR_U) ? (hy - 5'd1) : hy;

    wire hit_wall = (nx >= COLS) || (ny >= ROWS);

    // The tail cell (index len-1) vacates this step, so it is not a collision.
    reg hit_body;
    always @(*) begin
        hit_body = 1'b0;
        for (i = 0; i < MAXLEN; i = i + 1)
            if (i < len - 1 && bx[i] == nx && by[i] == ny)
                hit_body = 1'b1;
    end

    wire eat = (nx == fx) && (ny == fy) && food_valid;

    // Candidate food cell must not sit on the snake after this move.
    reg food_hit;
    always @(*) begin
        food_hit = (nfx == nx) && (nfy == ny);
        for (i = 0; i < MAXLEN; i = i + 1)
            if (i < len - 1 && bx[i] == nfx && by[i] == nfy)
                food_hit = 1'b1;
    end

    //--------------------------------------------------------------------------
    // Game step
    //--------------------------------------------------------------------------
    always @(posedge pixel_clk) begin
        if (init) begin
            len        <= 7'd3;
            alive      <= 1'b1;
            score      <= 7'd0;
            fx         <= 5'd20;
            fy         <= 5'd9;
            food_valid <= 1'b1;
            anim       <= 6'd0;
            eat_t      <= 4'd0;
            for (k = 0; k < MAXLEN; k = k + 1) begin
                bx[k] <= 5'd0;
                by[k] <= 5'd0;
            end
            bx[0] <= 5'd14; by[0] <= 5'd9;      // head
            bx[1] <= 5'd13; by[1] <= 5'd9;
            bx[2] <= 5'd12; by[2] <= 5'd9;      // tail
        end else begin
            if (frame_tick) anim <= anim + 6'd1;
            if ((eat_t != 4'd0) && frame_tick) eat_t <= eat_t - 4'd1;

            if (step && alive) begin
                if (hit_wall || hit_body) begin
                    alive <= 1'b0;
                end else begin
                    for (k = MAXLEN-1; k > 0; k = k - 1) begin
                        bx[k] <= bx[k-1];
                        by[k] <= by[k-1];
                    end
                    bx[0] <= nx;
                    by[0] <= ny;

                    if (eat) begin
                        if (len   < 7'd63) len   <= len + 7'd1;
                        if (score < 7'd99) score <= score + 7'd1;
                        eat_t <= 4'd12;             // flash the head briefly
                    end

                    if (eat || !food_valid) begin
                        if (!food_hit) begin
                            fx <= nfx; fy <= nfy; food_valid <= 1'b1;
                        end else begin
                            food_valid <= 1'b0;
                        end
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Pixel -> cell
    //--------------------------------------------------------------------------
    wire in_field = de && (x >= X0) && (x < (X0 + FW)) &&
                         (y >= Y0) && (y < (Y0 + FH));

    wire [11:0] dxf = x - X0;
    wire [11:0] dyf = y - Y0;
    wire [4:0]  cx  = dxf[8:4];         // cell column
    wire [4:0]  cy  = dyf[8:4];         // cell row
    wire [3:0]  pxin = dxf[3:0];        // position inside the cell
    wire [3:0]  pyin = dyf[3:0];

    wire chk = cx[0] ^ cy[0];           // 16 px checkerboard

    reg body_hit, head_hit;
    always @(*) begin
        body_hit = 1'b0;
        head_hit = 1'b0;
        for (i = 0; i < MAXLEN; i = i + 1)
            if (i < len && bx[i] == cx && by[i] == cy) begin
                body_hit = 1'b1;
                if (i == 0) head_hit = 1'b1;
            end
    end

    wire food_box = (pxin >= 4'd2) && (pxin < 4'd14) &&
                    (pyin >= 4'd2) && (pyin < 4'd14);
    wire cell_food = food_valid && (cx == fx) && (cy == fy) && food_box;

    //--------------------------------------------------------------------------
    // Score line : "SCORE nn"  (2 digits, SCALE 2, at (8,4))
    //--------------------------------------------------------------------------
    localparam integer SX = 8, SY = 4, SS = 2, SNCH = 8;
    localparam integer SW = SNCH * 8 * SS;      // 128

    wire [11:0] sdx = x - SX;
    wire [11:0] sdy = y - SY;
    wire s_in = de && (x >= SX) && (x < SX + SW) && (y >= SY) && (y < SY + 8*SS);

    wire [2:0] s_ci = sdx[6:4];         // character index  (x >> 4)
    wire [2:0] s_cc = sdx[3:1];         // column inside a cell (x >> 1)
    wire [2:0] s_ry = sdy[3:1];         // row    inside a cell (y >> 1)

    wire [3:0] s_tens = score / 10;
    wire [3:0] s_ones = score % 10;

    reg  [7:0] s_ch;
    always @(*) begin
        case (s_ci)
            3'd0: s_ch = 8'h53;                 // 'S'
            3'd1: s_ch = 8'h43;                 // 'C'
            3'd2: s_ch = 8'h4F;                 // 'O'
            3'd3: s_ch = 8'h52;                 // 'R'
            3'd4: s_ch = 8'h45;                 // 'E'
            3'd5: s_ch = 8'h20;                 // ' '
            3'd6: s_ch = 8'h30 + {4'b0, s_tens};
            default: s_ch = 8'h30 + {4'b0, s_ones};
        endcase
    end

    wire [7:0] s_bits;
    font_rom u_score_font (.ch (s_ch), .row (s_ry), .bits (s_bits));
    wire s_fg = s_in && s_bits[7 - s_cc];

    //--------------------------------------------------------------------------
    // Game-over overlay
    //--------------------------------------------------------------------------
    wire g1_in, g1_fg, g2_in, g2_fg, g3_in, g3_fg;

    text_line #(
        .X0 (168), .Y0 (160), .SCALE (2), .NCH (9),
        .TEXT (72'h4741_4D45_204F_5645_52)              // "GAME OVER"
    ) u_go1 (.de(de), .x(x), .y(y), .inside(g1_in), .fg(g1_fg));

    text_line #(
        .X0 (160), .Y0 (188), .SCALE (2), .NCH (10),
        .TEXT (80'h4B35_2052_4553_5441_5254)            // "K5 RESTART"
    ) u_go2 (.de(de), .x(x), .y(y), .inside(g2_in), .fg(g2_fg));

    text_line #(
        .X0 (136), .Y0 (212), .SCALE (2), .NCH (13),
        .TEXT (104'h4B34_204F_5220_4B37_2045_5849_54)  // "K4 OR K7 EXIT"
    ) u_go3 (.de(de), .x(x), .y(y), .inside(g3_in), .fg(g3_fg));

    wire go_box = !alive && (x >= 12'd120) && (x < 12'd360) &&
                           (y >= 12'd150) && (y < 12'd236);

    //--------------------------------------------------------------------------
    // Composite
    //--------------------------------------------------------------------------
    // Play field : a 2 px ring marks the arena.  Inside it every cell carries a
    // bevel, which is what makes the snake read as one solid body instead of a
    // row of flat squares, and the food read as a pellet.
    wire in_ring = de && (x >= 12'd14) && (x < 12'd466) &&
                         (y >= 12'd22) && (y < 12'd314) &&
                   !((x >= 12'd16) && (x < 12'd464) &&
                     (y >= 12'd24) && (y < 12'd312));

    wire [11:0] bg_flat  = up4(bg_at(dyf[8:0]), chk ? 4'd1 : 4'd0);
    wire [11:0] food_now = anim[3] ? C_FOOD2 : C_FOOD;
    wire        occ      = body_hit | head_hit | cell_food;

    wire [11:0] flat = head_hit  ? (eat_t != 4'd0 ? C_EAT : C_HEAD) :
                       body_hit  ? C_BODY :
                       cell_food ? food_now : bg_flat;

    wire b_hi = (pxin == 4'd0)  || (pyin == 4'd0);      // lit   top / left
    wire b_lo = (pxin == 4'd15) || (pyin == 4'd15);     // shaded bottom / right

    // the food pellet is chamfered at all four corners so it looks round
    wire [4:0] s_tl = {1'b0, pxin}           + {1'b0, pyin};
    wire [4:0] s_tr = {1'b0, (4'd15 - pxin)} + {1'b0, pyin};
    wire [4:0] s_bl = {1'b0, pxin}           + {1'b0, (4'd15 - pyin)};
    wire [4:0] s_br = {1'b0, (4'd15 - pxin)} + {1'b0, (4'd15 - pyin)};
    wire cut = cell_food &&
               ((s_tl < 5'd3) || (s_tr < 5'd3) || (s_bl < 5'd3) || (s_br < 5'd3));

    wire [11:0] cell_rgb = cut           ? bg_flat :
                           (occ && b_hi) ? up4(flat, 4'd2) :
                           (occ && b_lo) ? dn4(flat, 4'd2) : flat;

    always @(*) begin
        if (go_box)
            rgb = g1_fg ? C_GO_T1 : ((g2_fg || g3_fg) ? C_GO_T2 : C_GO_BG);
        else if (in_ring)   rgb = C_RING;
        else if (in_field)  rgb = cell_rgb;
        else if (s_fg)      rgb = C_TEXT;
        else                rgb = dn4(bg_at(y[8:0]), 4'd1);
    end

endmodule
