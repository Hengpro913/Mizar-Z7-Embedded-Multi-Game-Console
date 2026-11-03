`timescale 1ns / 1ps
//=============================================================================
// tmds_encoder.v
//   TMDS 8b/10b encoder for DVI 1.0 / HDMI source.
//   Implements the DVI 1.0 "Figure 3-5" flow as a 3-stage pipeline on PixelClk:
//     stage1 : register inputs, count ones
//     stage2 : minimise transitions (XOR / XNOR), register
//     stage3 : DC balance (running disparity), registered output
//   NOTE: the 3-cycle latency is identical on every channel, so RGB / DE / HS /
//         VS stay mutually aligned at the serializer inputs.
//=============================================================================
module tmds_encoder (
    input  wire       PixelClk,   // pixel clock = TMDS clock x1
    input  wire       aRst,       // asynchronous, active high
    input  wire [7:0] din,        // pixel data  (blue / green / red)
    input  wire       c0,         // control bit 0
    input  wire       c1,         // control bit 1
    input  wire       de,         // data enable
    output reg  [9:0] dout        // encoded 10-bit symbol, LSB sent first
);

    // DVI 1.0 control tokens (== HDMI control tokens)
    localparam [9:0] KCTL0 = 10'b1101010100; // c1=0,c0=0
    localparam [9:0] KCTL1 = 10'b0010101011; // c1=0,c0=1
    localparam [9:0] KCTL2 = 10'b0101010100; // c1=1,c0=0
    localparam [9:0] KCTL3 = 10'b1010101011; // c1=1,c0=1

    //--------------------------------------------------------------------------
    // Stage 1 : register inputs and count the number of ones
    //--------------------------------------------------------------------------
    reg  [7:0] din_1;
    reg        c0_1, c1_1, de_1;
    reg  [3:0] n1d_1;

    always @(posedge PixelClk or posedge aRst) begin
        if (aRst) begin
            din_1 <= 8'h00;
            c0_1  <= 1'b0;
            c1_1  <= 1'b0;
            de_1  <= 1'b0;
            n1d_1 <= 4'd0;
        end else begin
            din_1 <= din;
            c0_1  <= c0;
            c1_1  <= c1;
            de_1  <= de;
            n1d_1 <= din[0] + din[1] + din[2] + din[3] +
                     din[4] + din[5] + din[6] + din[7];
        end
    end

    //--------------------------------------------------------------------------
    // Minimise transitions: build both the XOR and the XNOR variant
    //--------------------------------------------------------------------------
    wire [8:0] q_m_xor;
    wire [8:0] q_m_xnor;

    assign q_m_xor [0] = din_1[0];
    assign q_m_xnor[0] = din_1[0];

    genvar gi;
    generate
        for (gi = 1; gi < 8; gi = gi + 1) begin : g_encode
            assign q_m_xor [gi] =   q_m_xor [gi-1] ^ din_1[gi];
            assign q_m_xnor[gi] = ~(q_m_xnor[gi-1] ^ din_1[gi]);
        end
    endgenerate

    assign q_m_xor [8] = 1'b1;   // flag: XOR  encoding used
    assign q_m_xnor[8] = 1'b0;   // flag: XNOR encoding used

    wire [8:0] q_m_1   = (n1d_1 > 4 || (n1d_1 == 4 && din_1[0] == 1'b0)) ? q_m_xnor : q_m_xor;
    wire [3:0] n1q_m_1 = q_m_1[0] + q_m_1[1] + q_m_1[2] + q_m_1[3] +
                         q_m_1[4] + q_m_1[5] + q_m_1[6] + q_m_1[7];

    //--------------------------------------------------------------------------
    // Stage 2 : register the DC-balance operands
    //--------------------------------------------------------------------------
    reg  [8:0] q_m_2;
    reg  [3:0] n1q_m_2, n0q_m_2;
    reg        c0_2, c1_2, de_2;
    reg  signed [4:0] cnt_t_3;          // running disparity, range -8..+8

    always @(posedge PixelClk or posedge aRst) begin
        if (aRst) begin
            q_m_2   <= 9'd0;
            n1q_m_2 <= 4'd0;
            n0q_m_2 <= 4'd0;
            c0_2    <= 1'b0;
            c1_2    <= 1'b0;
            de_2    <= 1'b0;
        end else begin
            q_m_2   <= q_m_1;
            n1q_m_2 <= n1q_m_1;
            n0q_m_2 <= 4'd8 - n1q_m_1;
            c0_2    <= c0_1;
            c1_2    <= c1_1;
            de_2    <= de_1;
        end
    end

    //--------------------------------------------------------------------------
    // DC balance decision (combinational)
    //--------------------------------------------------------------------------
    wire cond_balanced     = (cnt_t_3 == 5'sd0) || (n1q_m_2 == 4'd4);
    wire cond_not_balanced = ((cnt_t_3 >  5'sd0) && (n1q_m_2 > 4)) ||
                             ((cnt_t_3 <  5'sd0) && (n1q_m_2 < 4));

    wire [9:0] control_token = (c1_2 == 1'b0 && c0_2 == 1'b0) ? KCTL0 :
                               (c1_2 == 1'b0 && c0_2 == 1'b1) ? KCTL1 :
                               (c1_2 == 1'b1 && c0_2 == 1'b0) ? KCTL2 : KCTL3;

    wire [9:0] q_out_2 = (de_2 == 1'b0)                      ? control_token :
                         (cond_balanced     && q_m_2[8] == 1'b0) ? {~q_m_2[8], q_m_2[8], ~q_m_2[7:0]} :
                         (cond_balanced     && q_m_2[8] == 1'b1) ? {~q_m_2[8], q_m_2[8],  q_m_2[7:0]} :
                         (cond_not_balanced)                     ? {1'b1,      q_m_2[8], ~q_m_2[7:0]} :
                                                                   {1'b0,      q_m_2[8],  q_m_2[7:0]};

    wire signed [4:0] dc_bias_2 = $signed({1'b0, n0q_m_2}) - $signed({1'b0, n1q_m_2});

    wire signed [4:0] cnt_t_2 = (de_2 == 1'b0)                                     ? 5'sd0 :
                                (cond_balanced     && q_m_2[8] == 1'b0)            ? cnt_t_3 + dc_bias_2 :
                                (cond_balanced     && q_m_2[8] == 1'b1)            ? cnt_t_3 - dc_bias_2 :
                                (cond_not_balanced)                                ? cnt_t_3 + $signed({1'b0,  q_m_2[8], 1'b0}) + dc_bias_2 :
                                                                                     cnt_t_3 - $signed({1'b0, ~q_m_2[8], 1'b0}) - dc_bias_2;

    //--------------------------------------------------------------------------
    // Stage 3 : registered symbol output
    //--------------------------------------------------------------------------
    always @(posedge PixelClk or posedge aRst) begin
        if (aRst) begin
            cnt_t_3 <= 5'sd0;
            dout    <= 10'd0;
        end else begin
            cnt_t_3 <= cnt_t_2;
            dout    <= q_out_2;
        end
    end

endmodule