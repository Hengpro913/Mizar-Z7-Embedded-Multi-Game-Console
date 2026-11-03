//=============================================================================
// top_key_merge.v
//
// PS+PL 协同工程的“按键合并层 + 蓝牙控制引脚驱动”
//
//   * 物理按键 K4~K7（btn_n，低有效）与 PS 注入键码（ps_ctrl[7:4]）做与合并，
//     合并结果 btn_eff 送 top_console_ps 的 btn_n 输入，游戏 RTL 零改动。
//   * ps_ctrl[8] 为注入使能：为 0 时 PS 写入的键值完全不生效，物理按键照常可用。
//   * ps_ctrl[0]/[1] 分别驱动蓝牙 nRESET（低有效，1=释放复位）与 BT_WAKE。
//   * ps_ctrl[9] 为屏幕文字面板开关（show_ovl）。
//   * st_mon 把物理按键与蓝牙唤醒线上报给 PS（AXI GPIO 通道 2 输入），
//     PS 用它判断用户是否已经在用物理按键（用于自动隐藏文字面板）。
//
// ps_ctrl 来自 axi_gpio_0 的通道 1（32 位输出寄存器），软件写一次即整体生效。
// 该寄存器为准静态信号，跨时钟域无需同步：下游 btn_debounce 会重新采样消抖。
//
// 注入键位映射（与物理键一致）：[4]=K4 左 / [5]=K5 右 / [6]=K6 旋转 / [7]=K7 下
//=============================================================================
`timescale 1 ns / 1 ps

module top_key_merge (
    input  wire [3:0]  btn_n,        // 物理按键 K4~K7，低有效
    input  wire        bt_host_wake, // 蓝牙模块唤醒主机（只读上报）
    input  wire [31:0] ps_ctrl,      // PS 经 AXI GPIO 写入的控制字
    output wire [3:0]  btn_eff,      // 合并后的按键（低有效），送游戏核
    output wire        bt_nreset_n,  // 蓝牙 nRESET，低有效
    output wire        bt_wake,      // 主机唤醒蓝牙，高有效
    output wire        show_ovl,     // 文字面板显示开关
    output wire [4:0]  st_mon        // {bt_host_wake, btn_n[3:0]} 上报 PS
);

    wire       inj_en = ps_ctrl[8];
    wire [3:0] inj    = ps_ctrl[7:4];

    // 注入键为高有效、物理键为低有效：注入位为 1 时把对应按键位拉低
    assign btn_eff = btn_n & ~(inj & {4{inj_en}});

    assign bt_nreset_n = ps_ctrl[0];
    assign bt_wake     = ps_ctrl[1];
    assign show_ovl    = ps_ctrl[9];

    assign st_mon      = {bt_host_wake, btn_n};

endmodule
