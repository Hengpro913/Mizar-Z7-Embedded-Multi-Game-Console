`timescale 1ns / 1ps
//=============================================================================
// game_tetris.v
//   TETRIS game.  Pure function of the video beam position plus four logical
//   key pulses, running on the 74.25 MHz pixel clock.
//
//   Playfield : 10 x 20 cells of 16 x 16 px, origin (40, 0) -> 160 x 320 px
//   Panel     : x 208..472 : SCORE / LINES / LEVEL values and a NEXT box
//
//   Board  : 20 rows of 10 bits, bit 0 = leftmost column, 1 = occupied.  A
//            second 40 bit row keeps 4 bits of colour per column so settled
//            blocks keep the hue of the piece they came from.
//   Piece  : 4 x 4 bit mask, bit index r*4+c, c = 0 leftmost.  All seven
//            tetrominoes keep their shape in the top-left of that box and the
//            four rotations come from a pre-computed table, so there is no
//            rotation hardware and no wall-kick logic - a rotation that would
//            collide is simply discarded.
//
//   Gravity : one row every "period" frames, the period shortens with level.
//   Keys    : left_p  (K4)            -> shift left
//             right_p (K5 tap)        -> shift right
//             up_p    (K6)            -> rotate clockwise
//             down_p  (K7 tap)        -> soft drop, one row
//             ok_p    (K5 held 0.6 s) -> fast drop : while K5 stays down the
//                                        piece falls one row every 2 frames and
//                                        returns to normal speed on release
//             right_p (K5 tap) on the game-over overlay -> restart
//
//   Look    : the field sits on a vertical gradient, every block is a chamfered
//             brick with a lit top / left edge and a shaded bottom / right edge,
//             and a completed row flashes white for ~0.3 s before it collapses.
//
//   Held in reset while its state is inactive, so every entry starts a fresh
//   round.
//=============================================================================
module game_tetris (
    input  wire        pixel_clk,
    input  wire        rst,          // held high while the tetris state is inactive

    input  wire        de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        frame_tick,   // one pixel-clock pulse per frame

    input  wire        left_p,
    input  wire        right_p,
    input  wire        up_p,
    input  wire        down_p,
    input  wire        ok_p,         // K5 held 0.6 s : engage the fast drop
    input  wire        right_held,   // K5 still held : keeps the fast drop on

    output reg  [11:0] rgb,
    output wire        game_over
);

    //--------------------------------------------------------------------------
    // Geometry / palette
    //--------------------------------------------------------------------------
    localparam integer CELL = 16;
    localparam integer COLS = 10;
    localparam integer ROWS = 20;
    localparam integer X0   = 40;
    localparam integer FW   = COLS * CELL;      // 160
    localparam integer FH   = ROWS * CELL;      // 320

    localparam [11:0] C_FRAME  = 12'h0FF;   // the two bars flanking the field
    localparam [11:0] C_PANEL  = 12'h114;   // panel background
    localparam [11:0] C_PANELT = 12'h0FF;   // panel top stripe
    localparam [11:0] C_PREVBG = 12'h012;   // NEXT box background
    localparam [11:0] C_PREVED = 12'h0FF;   // NEXT box outline
    localparam [11:0] C_TEXT   = 12'hFFF;   // labels and values
    localparam [11:0] C_FLASH  = 12'hFFF;   // cleared line flash
    localparam [11:0] C_GO_BG  = 12'h213;   // game-over box
    localparam [11:0] C_GO_T1  = 12'hF60;   // "GAME OVER"
    localparam [11:0] C_GO_T2  = 12'hFFF;   // hints

    //--------------------------------------------------------------------------
    // Colour helpers : per channel saturating add / subtract, so a flat hue can
    // be turned into a lit and a shaded version of itself.
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

    // Field background : 10-band vertical gradient (32 px per band), deep navy
    // at the top through to deep blue-violet, so the vividly coloured blocks and
    // the white flash stand out.
    function [11:0] bg_at;
        input [8:0] yy;
        begin
            case (yy[8:5])
                4'd0: bg_at = 12'h012;
                4'd1: bg_at = 12'h013;
                4'd2: bg_at = 12'h114;
                4'd3: bg_at = 12'h215;
                4'd4: bg_at = 12'h216;
                4'd5: bg_at = 12'h317;
                4'd6: bg_at = 12'h418;
                4'd7: bg_at = 12'h419;
                4'd8: bg_at = 12'h51A;
                default: bg_at = 12'h51B;
            endcase
        end
    endfunction

    // Piece colours, indexed by the piece id (0 I .. 6 L).  Fully saturated.
    function [11:0] pal;
        input [3:0] k;
        begin
            case (k)
                4'd0: pal = 12'h0FF;    // I  cyan
                4'd1: pal = 12'hFF0;    // O  yellow
                4'd2: pal = 12'hF0F;    // T  magenta
                4'd3: pal = 12'h0F0;    // S  green
                4'd4: pal = 12'hF40;    // Z  red-orange
                4'd5: pal = 12'h03F;    // J  blue
                default: pal = 12'hF80;// L  orange
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Board and piece tables
    //--------------------------------------------------------------------------
    reg [9:0]  brd    [0:19];       // occupancy, bit 0 = leftmost column
    reg [39:0] brdcol [0:19];       // 4 bits of colour per column, col c = [c*4 +: 4]

    // bit index = r*4 + c, c = 0 is the leftmost column of the 4x4 box
    function [15:0] mask_of;
        input [2:0]  p;                 // 0 I, 1 O, 2 T, 3 S, 4 Z, 5 J, 6 L
        input [1:0]  r;                 // rotation 0..3
        begin
            case ({p, r})
                5'd0:  mask_of = 16'h00F0;   5'd1:  mask_of = 16'h2222;
                5'd2:  mask_of = 16'h0F00;   5'd3:  mask_of = 16'h4444;
                5'd4:  mask_of = 16'h0033;   5'd5:  mask_of = 16'h0033;
                5'd6:  mask_of = 16'h0033;   5'd7:  mask_of = 16'h0033;
                5'd8:  mask_of = 16'h0072;   5'd9:  mask_of = 16'h0262;
                5'd10: mask_of = 16'h0270;   5'd11: mask_of = 16'h0232;
                5'd12: mask_of = 16'h0036;   5'd13: mask_of = 16'h0462;
                5'd14: mask_of = 16'h0360;   5'd15: mask_of = 16'h0231;
                5'd16: mask_of = 16'h0063;   5'd17: mask_of = 16'h0264;
                5'd18: mask_of = 16'h0630;   5'd19: mask_of = 16'h0132;
                5'd20: mask_of = 16'h0071;   5'd21: mask_of = 16'h0226;
                5'd22: mask_of = 16'h0470;   5'd23: mask_of = 16'h0322;
                5'd24: mask_of = 16'h0074;   5'd25: mask_of = 16'h0622;
                5'd26: mask_of = 16'h0170;   5'd27: mask_of = 16'h0223;
                default: mask_of = 16'h0000;
            endcase
        end
    endfunction

    // Test a placement against the walls, the floor and the settled blocks.
    // qx/qy are SIGNED with an extra bit : a rotated piece keeps its shape
    // inside the 4x4 box, so the box origin has to be allowed to move left of
    // column 0 (down to -2) for the piece to actually touch the left wall.
    // rr/cc are integers so every sum stays 32 bit wide and never wraps.
    function collides;
        input signed [5:0] qx;
        input signed [5:0] qy;
        input [15:0]       qm;
        integer            rr, cc;
        reg                hit;
        begin
            hit = 1'b0;
            for (rr = 0; rr < 4; rr = rr + 1)
                for (cc = 0; cc < 4; cc = cc + 1)
                    if (qm[rr*4 + cc]) begin
                        if ((qx + cc) < 0 || (qx + cc) >= 10) hit = 1'b1;
                        else if ((qy + rr) >= 20)             hit = 1'b1;
                        else if (brd[qy + rr][qx + cc])       hit = 1'b1;
                    end
            collides = hit;
        end
    endfunction

    //--------------------------------------------------------------------------
    // State
    //--------------------------------------------------------------------------
    reg [2:0]  pidx;                 // falling piece
    reg [1:0]  prot;                 // its rotation
    reg signed [5:0] px, py;         // top-left of the 4x4 box, in cells
    reg [2:0]  npidx;                // next piece
    reg        alive;
    reg [13:0] score;                // 0..9999
    reg [13:0] lines;                // 0..9999
    reg [5:0]  div;                  // gravity divider
    reg        turbo;                // fast drop engaged (K5 held)
    reg [5:0]  flash_t;              // line clear flash countdown
    reg [19:0] flash_row;            // which rows are flashing
    reg [15:0] lfsr;                 // piece randomiser, seed 0xACE1

    assign game_over = !alive;

    wire restart = !alive && right_p;
    wire init    = rst || restart;

    wire [15:0] mask  = mask_of(pidx,  prot);
    wire [15:0] rmask = mask_of(pidx,  prot + 2'd1);
    wire [15:0] nmask = mask_of(npidx, 2'd0);

    //--------------------------------------------------------------------------
    // Randomiser : 16 bit maximal LFSR, x^16 + x^14 + x^13 + x^11 + 1
    //--------------------------------------------------------------------------
    wire        fb     = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    wire [15:0] lfsr_n = {lfsr[14:0], fb};
    wire [2:0]  rndp_n = (lfsr_n[2:0] >= 3'd7) ? 3'd0 : lfsr_n[2:0];

    //--------------------------------------------------------------------------
    // Level / gravity
    //--------------------------------------------------------------------------
    wire [9:0] level = lines / 14'd10;
    reg  [5:0] period;

    always @(*) begin
        case (level)
            10'd0: period = 6'd45;   10'd1: period = 6'd38;
            10'd2: period = 6'd32;   10'd3: period = 6'd27;
            10'd4: period = 6'd23;   10'd5: period = 6'd19;
            10'd6: period = 6'd15;   10'd7: period = 6'd12;
            10'd8: period = 6'd10;   10'd9: period = 6'd8;
            default: period = 6'd6;
        endcase
    end

    //--------------------------------------------------------------------------
    // Movement decisions
    //--------------------------------------------------------------------------
    // Gravity : one row every "period" frames at normal speed, one row every
    // 2 frames while the fast drop is engaged.
    wire tick     = frame_tick && (div >= (turbo ? 6'd1 : (period - 6'd1)));
    wire soft     = down_p;                          // K7 tap : one row
    wire step     = tick || soft;
    wire lock     = step && collides(px, py + 6'sd1, mask);
    wire hard     = ok_p && alive && !lock;          // K5 held : engage fast drop
    wire ok_left  = !collides(px - 6'sd1, py, mask);
    wire ok_right = !collides(px + 6'sd1, py, mask);
    wire rot_ok   = !collides(px, py, rmask);

    //--------------------------------------------------------------------------
    // Lock : merge the piece, remove the full rows -> next board
    //--------------------------------------------------------------------------
    reg [9:0]   b2  [0:19];
    reg [39:0]  b2c [0:19];
    reg [9:0]   b3  [0:19];
    reg [39:0]  b3c [0:19];
    reg [4:0]   wr;
    reg [2:0]   nclr;
    reg [19:0]  full_mask;
    integer     rr, cc, kk, kcol;

    always @(*) begin
        nclr      = 3'd0;
        full_mask = 20'h00000;
        for (kk = 0; kk < 20; kk = kk + 1) begin
            b2 [kk] = brd[kk];
            b2c[kk] = brdcol[kk];
            b3 [kk] = 10'h000;              // pre-cleared, then filled bottom-up
            b3c[kk] = 40'h0;
        end
        if (lock) begin
            for (rr = 0; rr < 4; rr = rr + 1)
                for (cc = 0; cc < 4; cc = cc + 1)
                    if (mask[rr*4 + cc] && ((py + rr) < 20) &&
                                          ((px + cc) >= 0) && ((px + cc) < 10)) begin
                        kcol = (px + cc) * 4;
                        b2 [py + rr][px + cc]          = 1'b1;
                        b2c[py + rr][kcol +: 4]        = {1'b0, pidx};
                    end

            wr = 5'd19;
            for (kk = 19; kk >= 0; kk = kk - 1) begin
                if (b2[kk] == 10'h3FF) begin
                    nclr = nclr + 3'd1;
                    full_mask[kk] = 1'b1;
                end
                else begin
                    b3 [wr] = b2 [kk];
                    b3c[wr] = b2c[kk];
                    wr = wr - 5'd1;
                end
            end
        end
    end

    // Spawn collision : next piece, rotation 0, top-left of the box at (3,0)
    wire [15:0] spawn_occ = { b3[3][6], b3[3][5], b3[3][4], b3[3][3],
                              b3[2][6], b3[2][5], b3[2][4], b3[2][3],
                              b3[1][6], b3[1][5], b3[1][4], b3[1][3],
                              b3[0][6], b3[0][5], b3[0][4], b3[0][3] };
    wire spawn_hit = |(nmask & spawn_occ);

    wire [13:0] add = (nclr == 3'd1) ? 14'd100 :
                      (nclr == 3'd2) ? 14'd300 :
                      (nclr == 3'd3) ? 14'd500 :
                      (nclr == 3'd4) ? 14'd800 : 14'd0;

    //--------------------------------------------------------------------------
    // Game logic
    //--------------------------------------------------------------------------
    always @(posedge pixel_clk) begin
        if (init) begin
            pidx  <= 3'd0;
            prot  <= 2'd0;
            px    <= 6'sd3;
            py    <= 6'sd0;
            npidx <= 3'd3;
            score <= 14'd0;
            lines <= 14'd0;
            alive <= 1'b1;
            div   <= 6'd0;
            turbo <= 1'b0;
            flash_t   <= 6'd0;
            flash_row <= 20'h00000;
            lfsr  <= 16'hACE1;
            for (kk = 0; kk < 20; kk = kk + 1) begin
                brd[kk]    <= 10'h000;
                brdcol[kk] <= 40'h0;
            end
        end
        else begin
            if ((flash_t != 6'd0) && frame_tick) flash_t <= flash_t - 6'd1;

            if (alive) begin
                if (hard)                     turbo <= 1'b1;
                else if (!right_held || lock) turbo <= 1'b0;

                if (lock) begin
                    for (kk = 0; kk < 20; kk = kk + 1) begin
                        brd[kk]    <= b3[kk];
                        brdcol[kk] <= b3c[kk];
                    end
                    pidx  <= npidx;
                    prot  <= 2'd0;
                    px    <= 6'sd3;
                    py    <= 6'sd0;
                    npidx <= rndp_n;
                    lfsr  <= lfsr_n;
                    lines <= (lines + {11'b0, nclr} > 14'd9999) ? 14'd9999 : lines + {11'b0, nclr};
                    score <= (score + add      > 14'd9999) ? 14'd9999 : score + add;
                    alive <= !spawn_hit;
                    div   <= 6'd0;
                    flash_row <= full_mask;
                    flash_t   <= (nclr != 3'd0) ? 6'd18 : 6'd0;
                end
                else begin
                    if      (up_p    && rot_ok)  prot <= prot + 2'd1;
                    else if (left_p  && ok_left) px   <= px - 6'sd1;
                    else if (right_p && ok_right) px  <= px + 6'sd1;

                    if (step)            py  <= py + 6'sd1;
                    if (step)            div <= 6'd0;
                    else if (frame_tick) div <= div + 6'd1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Pixel -> cell, playfield
    //--------------------------------------------------------------------------
    wire in_board = de && (x >= X0) && (x < (X0 + FW)) && (y < FH);

    wire [11:0] dxb = x - X0;
    wire [3:0]  bcx = dxb[7:4];             // column 0..9
    wire [4:0]  bcy = y[8:4];               // row    0..19
    wire [3:0]  bpx = dxb[3:0];
    wire [3:0]  bpy = y[3:0];

    // Signed differences : 0..3 selects the 4x4 box, anything outside it
    // (including a box pushed to x = -1/-2) is rejected.
    wire signed [5:0] dcx = {2'b0, bcx} - px;
    wire signed [5:0] dcy = {1'b0, bcy} - py;
    wire piece_cell = alive && (dcx >= 0) && (dcx < 6'sd4) &&
                              (dcy >= 0) && (dcy < 6'sd4) &&
                      mask[dcy[1:0]*4 + dcx[1:0]];
    wire locked_cell = brd[bcy][bcx];
    wire grid_line   = (bpx == 4'd0) || (bpy == 4'd0);

    //--------------------------------------------------------------------------
    // Field : gradient, faint grid, chamfered bricks, line clear flash
    //--------------------------------------------------------------------------
    wire [11:0] bg_flat = up4(bg_at(y[8:0]), grid_line ? 4'd1 : 4'd0);

    wire has_blk = locked_cell || piece_cell;
    wire [11:0] blk_flat = piece_cell  ? pal({1'b0, pidx}) :
                           locked_cell ? dn4(pal(brdcol[bcy][bcx*4 +: 4]), 4'd1) :
                                         bg_flat;

    wire b_hi = (bpx == 4'd0)  || (bpy == 4'd0);        // lit   top / left
    wire b_lo = (bpx == 4'd15) || (bpy == 4'd15);       // shaded bottom / right

    wire [4:0] t_tl = {1'b0, bpx}           + {1'b0, bpy};
    wire [4:0] t_tr = {1'b0, (4'd15 - bpx)} + {1'b0, bpy};
    wire [4:0] t_bl = {1'b0, bpx}           + {1'b0, (4'd15 - bpy)};
    wire [4:0] t_br = {1'b0, (4'd15 - bpx)} + {1'b0, (4'd15 - bpy)};
    wire chamfer = (t_tl < 5'd3) || (t_tr < 5'd3) || (t_bl < 5'd3) || (t_br < 5'd3);

    wire [11:0] block_rgb = (has_blk && chamfer) ? bg_flat :
                            (has_blk && b_hi)    ? up4(blk_flat, 4'd2) :
                            (has_blk && b_lo)    ? dn4(blk_flat, 4'd2) : blk_flat;

    wire flash_cell = (flash_t != 6'd0) && flash_row[bcy];

    //--------------------------------------------------------------------------
    // NEXT box : 64 x 64 px at (308, 216), 2 px outline, beveled preview block
    //--------------------------------------------------------------------------
    wire in_prev = de && (x >= 12'd308) && (x < 12'd372) &&
                        (y >= 12'd216) && (y < 12'd280);
    wire prev_edge = de && (x >= 12'd306) && (x < 12'd374) &&
                           (y >= 12'd214) && (y < 12'd282) &&
                     !((x >= 12'd308) && (x < 12'd372) &&
                       (y >= 12'd216) && (y < 12'd280));
    wire [7:0] pdx = x - 12'd308;
    wire [7:0] pdy = y - 12'd216;
    wire [1:0] pcx = pdx[5:4];
    wire [1:0] pcy = pdy[5:4];
    wire prev_cell = nmask[pcy*4 + pcx];

    wire [11:0] next_base = pal({1'b0, npidx});
    wire p_hi = (pdx[3:0] == 4'd0)  || (pdy[3:0] == 4'd0);
    wire p_lo = (pdx[3:0] == 4'd15) || (pdy[3:0] == 4'd15);
    wire [11:0] prev_rgb = prev_cell ? (p_hi ? up4(next_base, 4'd2) :
                                       (p_lo ? dn4(next_base, 4'd2) : next_base))
                                     : C_PREVBG;

    //--------------------------------------------------------------------------
    // Frame and panel backgrounds
    //--------------------------------------------------------------------------
    wire in_frame = de && (((x >= 12'd36) && (x < 12'd40)) || ((x >= 12'd200) && (x < 12'd204)));
    wire in_panel = de && (x >= 12'd208) && (x < 12'd472) && (y < FH);

    //--------------------------------------------------------------------------
    // Panel labels (text_line) and numeric values (font_rom)
    //--------------------------------------------------------------------------
    wire l1_in, l1_fg, l2_in, l2_fg, l3_in, l3_fg, l4_in, l4_fg;

    text_line #(.X0(308), .Y0(16),  .SCALE(2), .NCH(5), .TEXT(40'h53434F5245))
        u_lb_score (.de(de), .x(x), .y(y), .inside(l1_in), .fg(l1_fg));   // "SCORE"

    text_line #(.X0(308), .Y0(76),  .SCALE(2), .NCH(5), .TEXT(40'h4C494E4553))
        u_lb_lines (.de(de), .x(x), .y(y), .inside(l2_in), .fg(l2_fg));   // "LINES"

    text_line #(.X0(308), .Y0(136), .SCALE(2), .NCH(5), .TEXT(40'h4C4556454C))
        u_lb_level (.de(de), .x(x), .y(y), .inside(l3_in), .fg(l3_fg));   // "LEVEL"

    text_line #(.X0(308), .Y0(196), .SCALE(2), .NCH(4), .TEXT(32'h4E455854))
        u_lb_next  (.de(de), .x(x), .y(y), .inside(l4_in), .fg(l4_fg));   // "NEXT"

    // score value, 4 digits at (308, 38)
    localparam integer SCX = 308, SCY = 38, SCS = 2, SCD = 4;
    wire [11:0] scdx = x - SCX;
    wire [11:0] scdy = y - SCY;
    wire sc_in = de && (x >= SCX) && (x < SCX + SCD*8*SCS) && (y >= SCY) && (y < SCY + 8*SCS);
    wire [1:0]  sc_ci = scdx[5:4];
    wire [2:0]  sc_cc = scdx[3:1];
    wire [2:0]  sc_ry = scdy[3:1];
    reg  [3:0]  sc_dig;
    always @(*) begin
        case (sc_ci)
            2'd0:    sc_dig = score / 14'd1000;
            2'd1:    sc_dig = (score / 14'd100) % 14'd10;
            2'd2:    sc_dig = (score / 14'd10) % 14'd10;
            default: sc_dig = score % 14'd10;
        endcase
    end
    wire [7:0] sc_ch = 8'h30 + {4'b0, sc_dig};
    wire [7:0] sc_bits;
    font_rom u_fsc (.ch(sc_ch), .row(sc_ry), .bits(sc_bits));
    wire sc_fg = sc_in && sc_bits[7 - sc_cc];

    // lines value, 4 digits at (308, 98)
    localparam integer LNX = 308, LNY = 98;
    wire [11:0] lndx = x - LNX;
    wire [11:0] lndy = y - LNY;
    wire ln_in = de && (x >= LNX) && (x < LNX + 64) && (y >= LNY) && (y < LNY + 16);
    wire [1:0]  ln_ci = lndx[5:4];
    wire [2:0]  ln_cc = lndx[3:1];
    wire [2:0]  ln_ry = lndy[3:1];
    reg  [3:0]  ln_dig;
    always @(*) begin
        case (ln_ci)
            2'd0:    ln_dig = lines / 14'd1000;
            2'd1:    ln_dig = (lines / 14'd100) % 14'd10;
            2'd2:    ln_dig = (lines / 14'd10) % 14'd10;
            default: ln_dig = lines % 14'd10;
        endcase
    end
    wire [7:0] ln_ch = 8'h30 + {4'b0, ln_dig};
    wire [7:0] ln_bits;
    font_rom u_fln (.ch(ln_ch), .row(ln_ry), .bits(ln_bits));
    wire ln_fg = ln_in && ln_bits[7 - ln_cc];

    // level value, 2 digits at (308, 158)
    localparam integer LVX = 308, LVY = 158;
    wire [11:0] lvdx = x - LVX;
    wire [11:0] lvdy = y - LVY;
    wire lv_in = de && (x >= LVX) && (x < LVX + 32) && (y >= LVY) && (y < LVY + 16);
    wire [0:0]  lv_ci = lvdx[4];
    wire [2:0]  lv_cc = lvdx[3:1];
    wire [2:0]  lv_ry = lvdy[3:1];
    wire [3:0]  lv_dig = lv_ci ? (level % 14'd10) : (level / 14'd10);
    wire [7:0]  lv_ch = 8'h30 + {4'b0, lv_dig};
    wire [7:0]  lv_bits;
    font_rom u_flv (.ch(lv_ch), .row(lv_ry), .bits(lv_bits));
    wire lv_fg = lv_in && lv_bits[7 - lv_cc];

    //--------------------------------------------------------------------------
    // Game-over overlay
    //--------------------------------------------------------------------------
    wire g1_in, g1_fg, g2_in, g2_fg, g3_in, g3_fg;

    text_line #(.X0(168), .Y0(160), .SCALE(2), .NCH(9),
                .TEXT(72'h4741_4D45_204F_5645_52))
        u_go1 (.de(de), .x(x), .y(y), .inside(g1_in), .fg(g1_fg));        // "GAME OVER"

    text_line #(.X0(160), .Y0(188), .SCALE(2), .NCH(10),
                .TEXT(80'h4B35_2052_4553_5441_5254))
        u_go2 (.de(de), .x(x), .y(y), .inside(g2_in), .fg(g2_fg));        // "K5 RESTART"

    text_line #(.X0(136), .Y0(212), .SCALE(2), .NCH(13),
                .TEXT(104'h4B34_204F_5220_4B37_2045_5849_54))
        u_go3 (.de(de), .x(x), .y(y), .inside(g3_in), .fg(g3_fg));        // "K4 OR K7 EXIT"

    wire go_box = !alive && (x >= 12'd120) && (x < 12'd360) &&
                           (y >= 12'd150) && (y < 12'd236);

    //--------------------------------------------------------------------------
    // Composite
    //--------------------------------------------------------------------------
    always @(*) begin
        if (go_box)
            rgb = g1_fg ? C_GO_T1 : ((g2_fg || g3_fg) ? C_GO_T2 : C_GO_BG);
        else if (in_board)             rgb = flash_cell ? C_FLASH : block_rgb;
        else if (in_frame)             rgb = C_FRAME;
        else if (prev_edge)            rgb = C_PREVED;
        else if (in_prev)              rgb = prev_rgb;
        else if (in_panel) begin
            rgb = (y < 12'd3) ? C_PANELT : C_PANEL;
            if (l1_fg || l2_fg || l3_fg || l4_fg ||
                sc_fg || ln_fg || lv_fg) rgb = C_TEXT;
        end
        else rgb = dn4(bg_at(y[8:0]), 4'd1);
    end

endmodule
