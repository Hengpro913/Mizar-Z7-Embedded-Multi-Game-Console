#=============================================================================
# mizar_z7_plps.xdc  -  Mizar Z7 (XC7Z020-2CLG400) PS+PL 工程约束
#
#   与纯 PL 工程 mizar_z7.xdc 保持完全一致（HDMI/按键/LED/时钟），
#   额外增加蓝牙模块三根控制线的引脚约束（BD rev2 引出）。
#
#   引脚来源：Mizar Z7 用户手册 V1.1
#     PL_CLK_50M  : H16
#     PL_KEY1..4  : R19 T19 J15 B19（低有效，上拉）
#     PL_LED1..4  : G14 C20 B20 H17（低有效）
#     HDMI1       : Table 3-12
#     BT_nRESET   : E18   BT_HOST_WAKE : M17   BT_WAKE : M18
#=============================================================================

#-----------------------------------------------------------------------------
# Configuration (7-series)
#-----------------------------------------------------------------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#-----------------------------------------------------------------------------
# 50 MHz PL oscillator
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

#-----------------------------------------------------------------------------
# PL user keys K4..K7  (btn_n[0]=K4 ... btn_n[3]=K7)
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports {btn_n[0]}]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports {btn_n[1]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {btn_n[2]}]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports {btn_n[3]}]

#-----------------------------------------------------------------------------
# PL user LEDs D6..D9
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {led_n[0]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {led_n[1]}]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {led_n[2]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {led_n[3]}]

#-----------------------------------------------------------------------------
# HDMI1
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports hdmi_out_en]

set_property -dict {PACKAGE_PIN K17 IOSTANDARD TMDS_33} [get_ports hdmi_clk_p]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD TMDS_33} [get_ports hdmi_clk_n]

set_property -dict {PACKAGE_PIN G19 IOSTANDARD TMDS_33} [get_ports hdmi_d0_p]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD TMDS_33} [get_ports hdmi_d0_n]

set_property -dict {PACKAGE_PIN F19 IOSTANDARD TMDS_33} [get_ports hdmi_d1_p]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD TMDS_33} [get_ports hdmi_d1_n]

set_property -dict {PACKAGE_PIN D19 IOSTANDARD TMDS_33} [get_ports hdmi_d2_p]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD TMDS_33} [get_ports hdmi_d2_n]

#-----------------------------------------------------------------------------
# Bluetooth module control (BD rev2)
#   bt_nreset_n : 输出，低有效；复位后默认 0（模块保持复位），Linux 起来后置 1
#   bt_wake     : 输出，高有效
#   bt_host_wake: 输入，模块唤醒主机的握手信号
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports bt_nreset_n]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports bt_wake]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports bt_host_wake]

#-----------------------------------------------------------------------------
# Bluetooth HCI UART  = PS UART0 经 EMIO 引出（BD 端口 UART_0_txd / UART_0_rxd）
#   手册 p24-25：
#     BT_FM_UART_TXD  D18  PL 侧，BT UART 发送信号（模块 -> FPGA）=> UART_0_rxd
#     BT_FM_UART_RXD  E19  PL 侧，BT UART 接受信号（FPGA -> 模块）=> UART_0_txd
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports UART_0_txd]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports UART_0_rxd]

#-----------------------------------------------------------------------------
# 异步输入：按键与蓝牙唤醒线在内部重新同步，无 setup/hold 关系
#-----------------------------------------------------------------------------
set_false_path -from [get_ports {btn_n[*]}]
set_false_path -from [get_ports bt_host_wake]

#-----------------------------------------------------------------------------
# ps_ctrl（axi_gpio 输出寄存器，100 MHz AXI 域）为准静态控制字，
# 仅在软件更新时变化；进入 25.2 MHz 像素域后由 btn_debounce 连续稳定采样，
# 与物理按键同等对待，故按异步路径处理（该跨域仅这 4 个端点）。
#-----------------------------------------------------------------------------
set_false_path -from [get_clocks clk_fpga_0] -to [get_clocks clkout1]

#-----------------------------------------------------------------------------
# JP2 40-pin header（2026-10-26 新增，与最终交付包的引脚完全一致）
#   JP2 pin 3  = G17 : PS/2 CLK
#   JP2 pin 4  = G18 : PS/2 DATA
#   JP2 pin 1  = J18 : OpenMV UART TX -> Zynq RX
#   三路均为板外异步输入，与像素时钟域无时序关系
#-----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports ps2_clk]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports ps2_data]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports openmv_rx]

set_false_path -from [get_ports {ps2_clk ps2_data openmv_rx}]
