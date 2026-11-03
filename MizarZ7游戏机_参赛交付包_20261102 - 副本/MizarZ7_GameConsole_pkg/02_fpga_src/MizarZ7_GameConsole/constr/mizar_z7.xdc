#=============================================================================
# mizar_z7.xdc  -  Mizar Z7 (XC7Z020-2CLG400) game console
#
#  Pin numbers are taken from the "Mizar Z7 用户手册 V1.1":
#    PL_CLK_50M  : H16   (Table 3-2, Bank35 MRCC)
#    PL_KEY1..4  : R19 T19 J15 B19  (Table 3-16, active low, pulled up)
#    PL_LED1..4  : G14 C20 B20 H17  (Table 3-17, active low)
#    HDMI1       : Table 3-12
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
# The keys are asynchronous inputs - they are re-synchronised inside
# btn_debounce, so no setup/hold relationship has to be met.
#-----------------------------------------------------------------------------
set_false_path -from [get_ports {btn_n[*]}]