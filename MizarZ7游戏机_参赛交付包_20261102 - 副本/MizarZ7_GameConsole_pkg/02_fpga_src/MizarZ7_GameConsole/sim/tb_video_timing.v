`timescale 1ns / 1ps
//=============================================================================
// tb_video_timing.v
//   Measures one complete frame and checks:
//     * the number of active pixels  (H_ACTIVE * V_ACTIVE)
//     * the number of HSYNC low pixels (H_SYNC * V_TOTAL)
//     * the number of VSYNC low pixels (V_SYNC * H_TOTAL)
//     * the frame length in clocks     (H_TOTAL * V_TOTAL)
//=============================================================================
module tb_video_timing;

    localparam integer H_ACTIVE = 480, H_FP = 16, H_SYNC = 96, H_BP = 208;
    localparam integer V_ACTIVE = 320, V_FP = 10, V_SYNC = 2,  V_BP = 193;
    localparam integer H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP;   // 800
    localparam integer V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP;   // 525

    reg         clk = 1'b0;
    reg         rst = 1'b1;

    wire [11:0] x, y;
    wire        de, hs_n, vs_n, frame_tick;

    integer de_cnt   = 0;
    integer hs_cnt   = 0;
    integer vs_cnt   = 0;
    integer clk_cnt  = 0;
    integer frames   = 0;
    integer errors   = 0;

    always #10 clk = ~clk;      // 50 MHz for simulation speed

    video_timing #(
        .H_ACTIVE (H_ACTIVE), .H_FP (H_FP), .H_SYNC (H_SYNC), .H_BP (H_BP),
        .V_ACTIVE (V_ACTIVE), .V_FP (V_FP), .V_SYNC (V_SYNC), .V_BP (V_BP)
    ) dut (
        .pixel_clk  (clk),
        .rst        (rst),
        .x          (x),
        .y          (y),
        .de         (de),
        .hsync_n    (hs_n),
        .vsync_n    (vs_n),
        .frame_tick (frame_tick)
    );

    always @(posedge clk) begin
        if (!rst) begin
            clk_cnt = clk_cnt + 1;
            if (de)  de_cnt = de_cnt + 1;
            if (!hs_n) hs_cnt = hs_cnt + 1;
            if (!vs_n) vs_cnt = vs_cnt + 1;

            if (frame_tick) begin
                frames = frames + 1;
                if (frames > 1) begin      // skip the very first (reset) frame
                    $display("frame %0d : de=%0d hs_low=%0d vs_low=%0d clks=%0d",
                             frames, de_cnt, hs_cnt, vs_cnt, clk_cnt);
                    if (de_cnt  != H_ACTIVE*V_ACTIVE) begin
                        errors = errors + 1; $display("  [FAIL] de pixels"); end
                    if (hs_cnt  != H_SYNC*V_TOTAL) begin
                        errors = errors + 1; $display("  [FAIL] hsync width"); end
                    if (vs_cnt  != V_SYNC*H_TOTAL) begin
                        errors = errors + 1; $display("  [FAIL] vsync width"); end
                    if (clk_cnt != H_TOTAL*V_TOTAL) begin
                        errors = errors + 1; $display("  [FAIL] frame length"); end
                end
                de_cnt = 0; hs_cnt = 0; vs_cnt = 0; clk_cnt = 0;
            end
        end
    end

    initial begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        #1; rst = 1'b0;

        repeat (H_TOTAL * V_TOTAL * 3) @(posedge clk);   // ~3 frames

        if (errors == 0) $display("*** video_timing : ALL TESTS PASSED ***");
        else             $display("*** video_timing : %0d FAILURE(S) ***", errors);

        $finish;
    end

endmodule