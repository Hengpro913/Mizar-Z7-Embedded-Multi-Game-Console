//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2026.1 (win64) Build 6511674 Tue Jun 16 11:02:23 MDT 2026
//Date        : Mon Oct 26 19:47:17 2026
//Host        : liang running 64-bit major release  (build 9200)
//Command     : generate_target system_wrapper.bd
//Design      : system_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module system_wrapper
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    UART_0_rxd,
    UART_0_txd,
    bt_host_wake,
    bt_nreset_n,
    bt_wake,
    btn_n,
    hdmi_clk_n,
    hdmi_clk_p,
    hdmi_d0_n,
    hdmi_d0_p,
    hdmi_d1_n,
    hdmi_d1_p,
    hdmi_d2_n,
    hdmi_d2_p,
    hdmi_out_en,
    led_n,
    openmv_rx,
    ps2_clk,
    ps2_data,
    sys_clk);
  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  input UART_0_rxd;
  output UART_0_txd;
  input bt_host_wake;
  output bt_nreset_n;
  output bt_wake;
  input [3:0]btn_n;
  output hdmi_clk_n;
  output hdmi_clk_p;
  output hdmi_d0_n;
  output hdmi_d0_p;
  output hdmi_d1_n;
  output hdmi_d1_p;
  output hdmi_d2_n;
  output hdmi_d2_p;
  output hdmi_out_en;
  output [3:0]led_n;
  input openmv_rx;
  input ps2_clk;
  input ps2_data;
  input sys_clk;

  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire UART_0_rxd;
  wire UART_0_txd;
  wire bt_host_wake;
  wire bt_nreset_n;
  wire bt_wake;
  wire [3:0]btn_n;
  wire hdmi_clk_n;
  wire hdmi_clk_p;
  wire hdmi_d0_n;
  wire hdmi_d0_p;
  wire hdmi_d1_n;
  wire hdmi_d1_p;
  wire hdmi_d2_n;
  wire hdmi_d2_p;
  wire hdmi_out_en;
  wire [3:0]led_n;
  wire openmv_rx;
  wire ps2_clk;
  wire ps2_data;
  wire sys_clk;

  system system_i
       (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .UART_0_rxd(UART_0_rxd),
        .UART_0_txd(UART_0_txd),
        .bt_host_wake(bt_host_wake),
        .bt_nreset_n(bt_nreset_n),
        .bt_wake(bt_wake),
        .btn_n(btn_n),
        .hdmi_clk_n(hdmi_clk_n),
        .hdmi_clk_p(hdmi_clk_p),
        .hdmi_d0_n(hdmi_d0_n),
        .hdmi_d0_p(hdmi_d0_p),
        .hdmi_d1_n(hdmi_d1_n),
        .hdmi_d1_p(hdmi_d1_p),
        .hdmi_d2_n(hdmi_d2_n),
        .hdmi_d2_p(hdmi_d2_p),
        .hdmi_out_en(hdmi_out_en),
        .led_n(led_n),
        .openmv_rx(openmv_rx),
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .sys_clk(sys_clk));
endmodule
