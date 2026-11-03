`timescale 1ps / 1ps
//=============================================================================
// top_system.v   (rev6 : BT UART loopback test wrapper)
//
//   在系统自动生成的 system_wrapper 外面包一层，唯一新增逻辑是：
//     bt_wake = 1 时，把 PS UART0 的 TXD 直接环回给 RXD（PL 内部回环）
//     bt_wake = 0 时，RXD 仍然来自模块 TX（D18），即正常工作模式
//
//   这样可以用 `mz7tool btwake 1` 在 Linux 里验证 PS UART0 + EMIO + PL 通路，
//   不需要改 BD、不需要改任何已有 RTL，也不影响正常蓝牙工作模式。
//
//   端口名与 system_wrapper 完全一致，因此原有 XDC 约束一行不用改。
//=============================================================================
module top_system (
    inout  [14:0] DDR_addr,
    inout  [2:0]  DDR_ba,
    inout         DDR_cas_n,
    inout         DDR_ck_n,
    inout         DDR_ck_p,
    inout         DDR_cke,
    inout         DDR_cs_n,
    inout  [3:0]  DDR_dm,
    inout  [31:0] DDR_dq,
    inout  [3:0]  DDR_dqs_n,
    inout  [3:0]  DDR_dqs_p,
    inout         DDR_odt,
    inout         DDR_ras_n,
    inout         DDR_reset_n,
    inout         DDR_we_n,

    inout         FIXED_IO_ddr_vrn,
    inout         FIXED_IO_ddr_vrp,
    inout  [53:0] FIXED_IO_mio,
    inout         FIXED_IO_ps_clk,
    inout         FIXED_IO_ps_porb,
    inout         FIXED_IO_ps_srstb,

    input         UART_0_rxd,      // D18 : 模块 TX -> PS
    output        UART_0_txd,      // E19 : PS   -> 模块 RX

    input         bt_host_wake,    // M17
    output        bt_nreset_n,     // E18
    output        bt_wake,         // M18 : 同时作为回环测试开关

    input  [3:0]  btn_n,
    input         ps2_clk,         // G17 : JP2 pin 3 (PS/2 clock)
    input         ps2_data,        // G18 : JP2 pin 4 (PS/2 data)
    input         openmv_rx,       // J18 : JP2 pin 1 (OpenMV UART TX)
    output        hdmi_clk_n,
    output        hdmi_clk_p,
    output        hdmi_d0_n,
    output        hdmi_d0_p,
    output        hdmi_d1_n,
    output        hdmi_d1_p,
    output        hdmi_d2_n,
    output        hdmi_d2_p,
    output        hdmi_out_en,
    output [3:0]  led_n,
    input         sys_clk
);

    // bt_wake = 1 : 内部回环（诊断）；= 0 : 走模块 TX
    wire uart_rxd_to_ps = bt_wake ? UART_0_txd : UART_0_rxd;

    system_wrapper u_sys (
        .DDR_addr        (DDR_addr),
        .DDR_ba          (DDR_ba),
        .DDR_cas_n       (DDR_cas_n),
        .DDR_ck_n        (DDR_ck_n),
        .DDR_ck_p        (DDR_ck_p),
        .DDR_cke         (DDR_cke),
        .DDR_cs_n        (DDR_cs_n),
        .DDR_dm          (DDR_dm),
        .DDR_dq          (DDR_dq),
        .DDR_dqs_n       (DDR_dqs_n),
        .DDR_dqs_p       (DDR_dqs_p),
        .DDR_odt         (DDR_odt),
        .DDR_ras_n       (DDR_ras_n),
        .DDR_reset_n     (DDR_reset_n),
        .DDR_we_n        (DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio    (FIXED_IO_mio),
        .FIXED_IO_ps_clk (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .UART_0_rxd      (uart_rxd_to_ps),
        .UART_0_txd      (UART_0_txd),
        .bt_host_wake    (bt_host_wake),
        .bt_nreset_n     (bt_nreset_n),
        .bt_wake         (bt_wake),
        .btn_n           (btn_n),
        .ps2_clk         (ps2_clk),
        .ps2_data        (ps2_data),
        .openmv_rx       (openmv_rx),
        .hdmi_clk_n      (hdmi_clk_n),
        .hdmi_clk_p      (hdmi_clk_p),
        .hdmi_d0_n       (hdmi_d0_n),
        .hdmi_d0_p       (hdmi_d0_p),
        .hdmi_d1_n       (hdmi_d1_n),
        .hdmi_d1_p       (hdmi_d1_p),
        .hdmi_d2_n       (hdmi_d2_n),
        .hdmi_d2_p       (hdmi_d2_p),
        .hdmi_out_en     (hdmi_out_en),
        .led_n           (led_n),
        .sys_clk         (sys_clk)
    );

endmodule
