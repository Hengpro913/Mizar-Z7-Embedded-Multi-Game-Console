`timescale 1ns / 1ps
//=============================================================================
// text_overlay.v
//   Character-cell overlay driven by a PS-writable dual-port BRAM.
//
//   The PS writes a small text frame into BRAM through an AXI BRAM Controller
//   (port A); this module reads the same BRAM through port B, in the pixel
//   clock domain, and composites a dark console panel on top of the game
//   picture.
//
//   Layout inside the BRAM: 32 bytes (= 8 words) per row, 6 rows
//     row*32 + col   : ASCII character, col = 0..29 visible (480 px), 30..31 pad
//     cell = 16x16 px -> 480 x 96 px panel
//
//   ADDRESS MAP (hardware verified):
//   The block design wires  blk_mem_gen_0/addra = BRAM_PORTA_ADDR[9:0]
//   (see system.v).  In EXTERNAL mode the AXI BRAM Controller drives a
//   *byte* address there, so the memory's word address ends up equal to the
//   byte address instead of byte>>2.  Consequence: a 32-bit PS write at byte
//   offset b lands in word (b & 1023), and only 4-byte aligned addresses can
//   produce back-to-back words.
//   Therefore port B reads word  256 + 4*(cell/4)  and the PS must write at
//   byte address  0x42000100 + 4*m  (m = character-group index, 48 words).
//
//   A byte of 0x00 is rendered as a space, so an un-initialised BRAM shows
//   nothing.  The panel itself is only painted while "show" is high (PS bit).
//
//   Timing: BRAM port B has one clock of read latency, therefore the whole
//   video pipeline (rgb / de / hs / vs) is delayed by exactly one pixel clock
//   here.  Everything downstream sees a consistent stream.
//=============================================================================
module text_overlay #(
    parameter integer NCOL  = 30,            // 30 x 16 px = 480 px = full width
    parameter integer NROW  = 6,
    parameter integer SCALE = 2,             // 8x8 glyph -> 16x16 cell
    parameter         FORCE_OVL = 1'b0       // 1 = 忽略 show，始终绘制面板（仅调试用）
)(
    input  wire        clk,
    input  wire        rst,

    // video in (combinational, aligned with the timing generator)
    input  wire        de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        hs_n,
    input  wire        vs_n,
    input  wire [11:0] rgb_in,

    input  wire        show,                 // 1 = paint the panel
    output wire [9:0]  bram_addr,            // port B word address (combinational)
    input  wire [31:0] bram_dout,            // port B data

    // video out (delayed one pixel clock)
    output wire        de_o,
    output wire        hs_n_o,
    output wire        vs_n_o,
    output wire [11:0] rgb_o
);

    localparam integer CW = 8 * SCALE;                       // 16
    localparam integer BW = NCOL * CW;                       // 480 (visible)
    localparam integer BH = NROW * CW;                       // 96

    //--------------------------------------------------------------------------
    // Colours (RGB444).  Saturated, matching the console palette.
    //--------------------------------------------------------------------------
    localparam [11:0] C_BACK  = 12'h013;     // panel background : near-black navy
    localparam [11:0] C_EDGE  = 12'h0DF;     // panel border     : saturated blue
    localparam [11:0] C_HEAD  = 12'h0EF;     // header text  : cyan
    localparam [11:0] C_STATE = 12'hFD0;     // state text   : amber
    localparam [11:0] C_INFO  = 12'hFFF;     // body text    : white

    //--------------------------------------------------------------------------
    // Address generation (combinational from the incoming pixel)
    //--------------------------------------------------------------------------
    wire in_box = de && (x < BW) && (y < BH);

    //--------------------------------------------------------------------------
    // Character index.
    //   可见区仍是 NCOL=30 列（480 px），但 BRAM 里每行按 STRIDE=32 字节存放，
    //   即一行恰好 8 个 32-bit 字。这样每行都从新字的 byte0 开始：
    //     · 行首不再出现 (row*30) mod 4 的字节相位跳变（30 mod 4 = 2），
    //       否则相邻行会横向错开 2 个字符，屏幕上表现为"阶梯"；
    //     · PS 侧按每行 32 字符（30 内容 + 2 空格）写入即可，无需跨行拼字节。
    //   最大 cidx = 5*32+29 = 189，waddr 最大 = 64+47 = 111，均在 1024 字内。
    //--------------------------------------------------------------------------
    localparam integer STRIDE = 32;

    wire [4:0] col   = x[8:4];
    wire [2:0] row   = y[6:4];
    wire [7:0] cidx  = row * STRIDE + col;                   // 0 .. 189
    //--------------------------------------------------------------------------
    // 面板字基址 = 256，每个字组装 4 个字符，字地址按 4 跳。
    //   根因（已在生成的 system.v 中查证）：BD 把 blk_mem_gen_0/addra 接到了
    //   axi_bram_ctrl_0/BRAM_PORTA_addr[9:0]，而该端口在 EXTERNAL 模式下是
    //   「字节地址」；正确接法应为 [11:2]。于是 BRAM 的字地址 == PS 的字节地址，
    //   只有 4 字节对齐的地址才能写出连续的字。
    //   因此端口 B 读字 256 + 4*(cidx>>2)，PS 用字节地址 0x42000100 + 4*m 写入，
    //   m = cidx>>2（0..47），正好一一对应，共 48 个字。
    //--------------------------------------------------------------------------
    wire [9:0] waddr = 10'd256 + {2'b00, cidx[7:2], 2'b00};  // 256 + 4*(cidx>>2)

    //--------------------------------------------------------------------------
    // BRAM 端口 B：地址必须组合输出。
    //   BRAM 本身自带 1 拍读延迟（doutb 在 addrb 之后一个时钟有效），
    //   若这里再打一拍地址，数据就会比像素晚 2 拍，字符会整体错位一格。
    //   因此地址保持组合，整条视频流水只延迟 1 拍（见下方 *_q 寄存器组）。
    //--------------------------------------------------------------------------
    assign bram_addr = waddr;

    //--------------------------------------------------------------------------
    // One-clock delay of the whole video pipeline
    //--------------------------------------------------------------------------
    reg [11:0] x_q, y_q, rgb_q;
    reg        de_q, hs_q, vs_q, box_q, show_q;
    reg [1:0]  sel_q;

    always @(posedge clk) begin
        if (rst) begin
            x_q <= 12'd0;  y_q <= 12'd0;  rgb_q <= 12'd0;
            de_q <= 1'b0;  hs_q <= 1'b1;  vs_q <= 1'b1;
            box_q <= 1'b0; show_q <= 1'b0; sel_q <= 2'd0;
        end else begin
            x_q    <= x;      y_q    <= y;      rgb_q  <= rgb_in;
            de_q   <= de;     hs_q   <= hs_n;   vs_q   <= vs_n;
            box_q  <= in_box; show_q <= show;
            sel_q  <= cidx[1:0];
        end
    end

    //--------------------------------------------------------------------------
    // Character fetch from the BRAM word
    //--------------------------------------------------------------------------
    reg [7:0] ch_byte;

    always @(*) begin
        case (sel_q)
            2'd0: ch_byte = bram_dout[7:0];
            2'd1: ch_byte = bram_dout[15:8];
            2'd2: ch_byte = bram_dout[23:16];
            default: ch_byte = bram_dout[31:24];
        endcase
    end

    // lower case -> upper case (font only carries capitals)
    wire [7:0] ch = (ch_byte >= 8'h61 && ch_byte <= 8'h7A) ? (ch_byte - 8'h20) : ch_byte;

    wire [2:0] gcol = x_q[3:1];
    wire [2:0] grow = y_q[3:1];

    wire [7:0] bits;
    font8x8 u_font (
        .ch   (ch),
        .row  (grow),
        .bits (bits)
    );

    wire glyph = bits[7 - gcol] && (ch_byte != 8'h00);

    wire edge_px = (x_q < 12'd2) || (x_q >= (BW - 2)) ||
                   (y_q < 12'd2) || (y_q >= (BH - 2));

    wire [11:0] txt_col = (y_q[6:4] == 3'd0) ? C_HEAD :
                          (y_q[6:4] == 3'd1) ? C_STATE : C_INFO;

    //--------------------------------------------------------------------------
    // Composite (all signals already aligned at this point)
    //--------------------------------------------------------------------------
    assign de_o   = de_q;
    assign hs_n_o = hs_q;
    assign vs_n_o = vs_q;
    assign rgb_o  = (box_q && (show_q | FORCE_OVL))
                      ? (edge_px ? C_EDGE : (glyph ? txt_col : C_BACK))
                      : rgb_q;

endmodule
