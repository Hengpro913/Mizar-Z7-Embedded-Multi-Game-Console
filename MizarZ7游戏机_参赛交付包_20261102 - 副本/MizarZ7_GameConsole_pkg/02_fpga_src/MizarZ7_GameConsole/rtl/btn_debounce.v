`timescale 1ns / 1ps
//=============================================================================
// btn_debounce.v
//   Two-flop synchroniser + counter based debouncer for a mechanical key.
//
//   The board keys are pulled up and shorted to GND when pressed, so the
//   caller must invert the pin first (see top_game_console).
//
//   CNT_MAX = 252000 -> 10 ms at a 25.2 MHz clock (2^18 = 262144).
//=============================================================================
module btn_debounce #(
    parameter integer CNT_MAX = 252_000,
    parameter integer CNT_W   = 18
)(
    input  wire clk,
    input  wire rst,        // asynchronous, active high
    input  wire btn_in,     // raw, already inverted to active high
    output reg  btn_out     // debounced, active high
);

    //--------------------------------------------------------------------------
    // 2-flop synchroniser (the pin is asynchronous to clk)
    //--------------------------------------------------------------------------
    reg [1:0] sync_q;
    always @(posedge clk or posedge rst) begin
        if (rst) sync_q <= 2'b00;
        else     sync_q <= {sync_q[0], btn_in};
    end

    wire btn_s = sync_q[1];

    //--------------------------------------------------------------------------
    // The state only changes after btn_s has been stable for CNT_MAX clocks
    //--------------------------------------------------------------------------
    reg [CNT_W-1:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt     <= {CNT_W{1'b0}};
            btn_out <= 1'b0;
        end else if (btn_s != btn_out) begin
            if (cnt == CNT_MAX - 1) begin
                cnt     <= {CNT_W{1'b0}};
                btn_out <= btn_s;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end else begin
            cnt <= {CNT_W{1'b0}};
        end
    end

endmodule
