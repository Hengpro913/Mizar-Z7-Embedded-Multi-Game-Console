`timescale 1ns / 1ps
//=============================================================================
// tb_tmds_encoder.v
//   Checks the 4 DVI control tokens and 3 data symbols whose encoding is
//   deterministic because the running disparity is forced to 0 first
//   (de = 0 makes cnt_t_3 = 0).
//
//   Expected values (identical to the Digilent rgb2dvi reference):
//     de=0 c1c0=00 -> 1101010100
//     de=0 c1c0=01 -> 0010101011
//     de=0 c1c0=10 -> 0101010100
//     de=0 c1c0=11 -> 1010101011
//     de=1 din=0x00 -> 0100000000
//     de=1 din=0xFF -> 1000000000
//     de=1 din=0xAA -> 1000110011
//=============================================================================
module tb_tmds_encoder;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg  [7:0] din = 8'h00;
    reg        c0  = 1'b0;
    reg        c1  = 1'b0;
    reg        de  = 1'b0;
    wire [9:0] dout;

    integer errors = 0;

    always #10 clk = ~clk;      // 50 MHz for simulation speed

    tmds_encoder dut (
        .PixelClk (clk),
        .aRst     (rst),
        .din      (din),
        .c0       (c0),
        .c1       (c1),
        .de       (de),
        .dout     (dout)
    );

    //--------------------------------------------------------------------------
    // Control token check : de = 0, hold the inputs, the output is static
    //--------------------------------------------------------------------------
    task check_ctrl;
        input        c_in0;
        input        c_in1;
        input [9:0]  exp;
        begin
            de = 1'b0; c0 = c_in0; c1 = c_in1;
            repeat (5) @(posedge clk);
            #1;
            if (dout !== exp) begin
                errors = errors + 1;
                $display("[FAIL] ctrl c1c0=%b%b : got %010b exp %010b", c_in1, c_in0, dout, exp);
            end else begin
                $display("[ OK ] ctrl c1c0=%b%b : %010b", c_in1, c_in0, dout);
            end
            c0 = 1'b0; c1 = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Data symbol check : force disparity to 0 (>=5 cycles of de=0), then
    // apply ONE pixel of data and sample the output 3 cycles later.
    //--------------------------------------------------------------------------
    task check_data;
        input [7:0] v;
        input [9:0] exp;
        begin
            de = 1'b0; din = 8'h00; c0 = 1'b0; c1 = 1'b0;
            repeat (5) @(posedge clk);      // running disparity -> 0

            #1; din = v; de = 1'b1;         // sampled by the DUT at the next edge
            @(posedge clk);
            #1; de = 1'b0; din = 8'h00;     // one pixel wide data pulse

            repeat (2) @(posedge clk);      // pipeline delay (3 stages)
            #1;
            if (dout !== exp) begin
                errors = errors + 1;
                $display("[FAIL] data 0x%02X : got %010b exp %010b", v, dout, exp);
            end else begin
                $display("[ OK ] data 0x%02X : %010b", v, dout);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    initial begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        #1; rst = 1'b0;
        repeat (3) @(posedge clk);

        check_ctrl (1'b0, 1'b0, 10'b1101010100);
        check_ctrl (1'b1, 1'b0, 10'b0010101011);
        check_ctrl (1'b0, 1'b1, 10'b0101010100);
        check_ctrl (1'b1, 1'b1, 10'b1010101011);

        check_data (8'h00, 10'b0100000000);
        check_data (8'hFF, 10'b1000000000);
        check_data (8'hAA, 10'b1000110011);

        if (errors == 0) $display("*** TMDS encoder : ALL TESTS PASSED ***");
        else             $display("*** TMDS encoder : %0d FAILURE(S) ***", errors);

        $finish;
    end

endmodule