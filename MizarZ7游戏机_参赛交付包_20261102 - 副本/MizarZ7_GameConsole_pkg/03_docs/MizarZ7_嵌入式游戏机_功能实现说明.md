# Mizar Z7 7020 嵌入式游戏机 —— 功能实现说明

| 项目 | 内容 |
|---|---|
| 器件 | Xilinx Zynq-7020 `xc7z020clg400-2`（Mizar Z7 7020 开发板） |
| 工具 | Vivado 2026.1 |
| 工程 | `D:\FPGAproject\MizarZ7_PLPS\plps_prj\MizarZ7_PLPS.xpr`（顶层 `system_wrapper`） |
| 显示 | 480×320 @ 60 Hz，HDMI/DVI 直出 |
| 输入 | 板载 K4~K7、PC 键盘（JTAG 注入）、PS/2 键盘（预留）、OpenMV 视觉 |
| 玩法 | 菜单 + 4 个游戏：SNAKE / TETRIS / FLAPPY BIRD / BREAKOUT |

---

## 1. 系统总体架构

系统是 **PS + PL 协同**：PL 负责所有实时图形与按键时序，PS 只负责“跨域搬运”（把 PC 键盘的键码搬进 PL、把文字面板内容搬进 BRAM）。

```text
                ┌──────────────────────── PS (ARM Cortex-A9) ────────────────────────┐
   PC 键盘 ──►  │ xsdb 守护进程 ──mwr──► AXI GPIO 0x41200000 通道1 (输出)             │
  (全局抓键)    │                              │ ps_ctrl[31:0]                       │
                │ Linux / 应用程序 ──► BRAM 控制器 ──► 文本帧缓冲 BRAM             │
                └──────────────────────────────┬──────────────────────────────────────┘
                                               │ AXI
   ┌───────────────────────────────────────────┴──────────────────────────────────────┐
   │                                    PL                                             │
   │  btn_n(K4~K7) ─► top_key_merge ─► 10 ms 消抖 ─► key_ctrl ─┐                       │
   │  ps_ctrl[7:4], [8]                    ▲                    │ 逻辑按键事件           │
   │                                       │                    ├─► scene_render         │
   │  ps2_clk/data ─► ps2_keyboard ─────────┘                    │    ├─ scene_menu       │
   │                                                             │    ├─ game_snake       │
   │  openmv_rx ─► openmv_uart_rx ─► target_x/y/valid ──────────┘    ├─ game_tetris      │
   │                                                                  ├─ game_flappy      │
   │  50 MHz ─► MMCM ─► 25.2 MHz ─► video_timing ─► x/y/de/HS/VS      └─ game_breakout    │
   │                           └──► 126 MHz ─┐                          │ rgb 12-bit      │
   │  BRAM(文本) ─► text_overlay ◄───────────┼── scene rgb ────────────┘                 │
   │                                          └─► hdmi_tx (TMDS) ─► HDMI 差分对            │
   └────────────────────────────────────────────────────────────────────────────────────┘
```

| 侧 | 职责 | 关键点 |
|---|---|---|
| PS | 键盘注入控制字、文字面板帧缓冲 | 只写准静态寄存器与 BRAM，不参与时序 |
| PL | 视频时序、TMDS 编码、消抖/长短按、4 个游戏、UART 解析 | 全部单时钟（25.2 MHz 像素时钟）同步设计 |

---

## 2. 时钟与视频链路

### 2.1 时钟生成 `clk_hdmi.v`

50 MHz 板载晶振（`sys_clk`，引脚 H16）经 `MMCME2_BASE` 生成两路：

| 项目 | 参数 | 结果 |
|---|---|---|
| 输入 | `CLKIN1_PERIOD = 20.000` | 50 MHz（实测 `sys_clk` 周期 20.000 ns） |
| 预分频 | `DIVCLK_DIVIDE = 5` | PFD = 10 MHz |
| 倍频 | `CLKFBOUT_MULT_F = 63.000` | **VCO = 630 MHz** |
| CLKOUT0 | `CLKOUT0_DIVIDE_F = 5.000` | **126.0 MHz**（TMDS 串行时钟，DDR 10:1 → 252 Mb/s/通道） |
| CLKOUT1 | `CLKOUT1_DIVIDE = 25` | **25.2 MHz**（像素时钟，全 PL 的唯一工作时钟） |

以上频率已在实现后的时序报告 `Clock Summary` 中得到实测确认：`clkfb 10.000 MHz / clkout0 126.000 MHz / clkout1 25.200 MHz`。

复位：`aRst` 在 MMCM 未锁定时一直保持，锁定后再保持 **255 个像素时钟**才释放：

```verilog
always @(posedge pixel_clk or negedge mmcm_locked)
    if (!mmcm_locked)          begin rst_cnt <= 8'd0; aRst <= 1'b1; end
    else if (rst_cnt != 8'hFF) begin rst_cnt <= rst_cnt + 8'd1; aRst <= 1'b1; end
    else                             aRst <= 1'b0;
```

### 2.2 时序发生器 `video_timing.v`

| 参数 | 值 | 说明 |
|---|---|---|
| H_ACTIVE / H_FP / H_SYNC / H_BP | 480 / 16 / 96 / 208 | H_TOTAL = **800** |
| V_ACTIVE / V_FP / V_SYNC / V_BP | 320 / 10 / 2 / 193 | V_TOTAL = **525** |
| 行频 HS | 25.2 MHz / 800 = **31.5 kHz** | 与 640×480@60 完全一致 |
| 场频 VS | 31.5 kHz / 525 = **60.0 Hz** | 显示器兼容性最好 |
| `de` | `(x<480) && (y<320)` | 有效像素 |
| `frame_tick` | 每帧最后一个像素宽 1 拍 | 所有游戏的“帧节拍”来源 |

`x / y` 是寄存器输出，`de / hsync_n / vsync_n / frame_tick` 由同一组 `x / y` 组合得到，所以**每一级流水看到的是同一像素**，不存在错位。

### 2.3 TMDS 发送 `hdmi_tx.v`

```text
D0 / 蓝 : din = B, c1 = VSYNC, c0 = HSYNC     ← 行场同步藏在蓝通道控制位
D1 / 绿 : din = G, c1 = 0,     c0 = 0
D2 / 红 : din = R, c1 = 0,     c0 = 0
CLK     : 固定串行图形 10'b1111100000 → 50% 占空比方波，OSERDES 延迟与数据通道一致
```

- 3 个 `tmds_encoder`（8b/10b，含 DC 平衡与异或/同或选择）
- 4 个 `serializer_10to1`（OSERDESE2，DDR 模式 5 个时钟出 10 bit）
- 引脚：`hdmi_out_en` = M20（**低有效使能**），数据对 G19/G20、F19/F20、D19/D20，时钟对 K17/K18

### 2.4 HDMI 上电使能延时

MPI3508 转接板需要先上电稳定，所以 `hdmi_out_en` 延迟 **2.66 s** 才拉低（有效）：

```verilog
// 2^26 / 25.2 MHz = 2.66 s
reg [26:0] hdmi_en_cnt;
always @(posedge pixel_clk or negedge mmcm_locked)
    if (!mmcm_locked)              hdmi_en_cnt <= 27'd0;
    else if (!hdmi_en_cnt[26])     hdmi_en_cnt <= hdmi_en_cnt + 27'd1;
wire hdmi_en_ok   = hdmi_en_cnt[26];
assign hdmi_out_en = ~hdmi_en_ok;        // 低有效
```

这段时间屏幕全黑，是**正常现象**，不是没下载成功。

---

## 3. 输入子系统（三路输入汇聚成一套逻辑按键）

### 3.1 板载按键链

```text
btn_n[3:0] (低有效)
   └─► 反相 btn_raw = ~btn_n
        └─► btn_debounce ×4   CNT_MAX = 252_000  @25.2 MHz = 10 ms
             └─► btn[3:0] (高有效、已消抖)
                  ├─► key_ctrl  ──► 逻辑事件（下表）
                  └─► move_left_held / move_right_held（电平直通）
```

`btn_debounce` 用计数器做“连续 10 ms 稳定才认”，抗机械抖动与注入时的毛刺。

### 3.2 长短按语义 `key_ctrl.v`（全系统的“按键协议”）

| 输出 | 触发时刻 | 典型用途 |
|---|---|---|
| `left_p`  | K4 **按下沿** | 左移一格 / 菜单无 |
| `right_p` | K5 **短按（<0.4 s）释放沿** | 右移一格 |
| `up_p`    | K6 **按下沿** | 上移 / 旋转 / 拍翅 |
| `down_p`  | K7 **短按释放沿** | 下移 / 软降 |
| `ok_p`    | K5 **按住满 0.4 s 的瞬间** | 确认进入 / 硬降 / 拍翅 |
| `back_p`  | K7 **按住满 0.4 s 的瞬间** | 返回菜单 |
| `right_held` | K5 **电平** | TETRIS 硬降连发 |

`LONG_CNT = 10_080_000` → 0.4 s。长按会**先报 `ok_p` 再不会补发 `right_p`**（`r_long` 标志），所以“按住 K5”不会误判成“右移”。

### 3.3 PC 键盘注入（本系统的核心改动）

**目标**：PC 键盘能用，但游戏 RTL 一行不改、板载 K4~K7 永远可用。

**做法**：在**消抖之前**做按位与合并。

```verilog
// top_key_merge.v
wire       inj_en = ps_ctrl[8];        // 注入使能：0 = PC 键盘完全失效
wire [3:0] inj    = ps_ctrl[7:4];      // [4]=K4 左 [5]=K5 右 [6]=K6 上 [7]=K7 下
assign btn_eff = btn_n & ~(inj & {4{inj_en}});
```

- 注入位是**高有效**，物理键是**低有效**，所以用“把对应位拉低”的方式合并
- `inj_en = 0` 时 `~(0) = 1111`，`btn_eff = btn_n`，物理键行为完全不变 ➜ **兜底安全**
- 合并点选在消抖之前，于是注入的键**自动复用** 10 ms 消抖、长短按判定、上电延时，逻辑一致、无第二套按键代码

**端到端链路**：

```text
PC 物理按键
  └─► jtkey_pc.ps1   GetAsyncKeyState 每 8 ms 扫一次
       └─► 写邮箱文件 tools\jtkey.cmd（内容 "0"~"15"，4 位键码）
            └─► jtkey_daemon.tcl（xsdb）每 20 ms 读邮箱，值变化才写寄存器
                 └─► mwr 0x41200000 = (旧值 & ~0x1F0) | 0x100 | (键码 << 4)
                      └─► AXI GPIO 通道1 → ps_ctrl → top_key_merge → btn_eff
                           └─► 原地复用整条按键链 → 游戏
```

守护只改 `bit[8:4]`，其余位保持，所以不会踩坏蓝牙复位脚；另外每 2 s 自动重写一次 `bit8`，**重新下位流后无需重启守护**也能恢复按键。

### 3.4 PS/2 键盘 `ps2_keyboard.v`（已实现，本机不使用）

- 纯采样接收：`ps2_clk` 下降沿采样，3 级同步防亚稳态
- Set-2 协议：`E0` 扩展前缀、`F0` 释放前缀、奇校验 + 停止位校验
- 映射：`0x1D`=W、`0x1B`=S、`0x1C`=A、`0x23`=D、`0x6B/0x74/0x75/0x72`=方向键、`0x29`=空格、`0x5A`=回车、`0x4D`=P、`0x2D`=R、`0x76`=Esc
- 引脚：`ps2_clk`=G17、`ps2_data`=G18，**必须外接 4.7 kΩ 上拉到 3.3 V**

### 3.5 统一事件总线

`top_console_ps.v` 把三路输入合成一套 `ui_*`，所有游戏只认这一套：

| 事件 | 来源 |
|---|---|
| `ui_left_p` / `ui_right_p` / `ui_up_p` / `ui_down_p` | key_ctrl ∪ PS/2 对应键的**按下沿**（电平转脉冲） |
| `ui_ok_p` | `ok_p` ∪ 空格 ∪ 回车 |
| `ui_back_p` | `back_p` ∪ Esc |
| `ui_pause_p` / `ui_restart_p` | 仅 PS/2 的 P / R（PC 键盘暂无通路） |
| `move_left_held` / `move_right_held` | `btn[0/1]` ∪ PS/2 的 A/←、D/→ **电平** |
| `up_held` / `down_held` | PS/2 的 W/↑、S/↓ 电平（FLAPPY 微调） |

> 注意：PC 键盘注入的键走的是 `btn_n`，所以它在 `ui_left_p` 里的贡献来自 `key_ctrl`，与板载键**同源同语义**。

---

## 4. 菜单与场景调度 `scene_render.v`

### 4.1 主状态机

| 状态 | 编码 | 进入条件 | 退出条件 |
|---|---|---|---|
| `ST_MENU` | 0 | 复位 | `ok_p \|\| right_p` → 按 `sel` 进入 |
| `ST_SNAKE` | 1 | sel=0 | `back_p`，或游戏结束后 `left_p/down_p` |
| `ST_TETRIS` | 2 | sel=1 | 同上 |
| `ST_FLAPPY` | 3 | sel=2 | 同上 |
| `ST_BREAKOUT` | 4 | sel=3 | 同上 |

### 4.2 菜单选择

```verilog
if (up_p)   sel <= (sel == 0) ? 3 : sel - 1;   // 循环上移
if (down_p) sel <= (sel == 3) ? 0 : sel + 1;   // 循环下移
if (ok_p || right_p) state <= (按 sel 展开);
```

### 4.3 每局独立

每个游戏都接 `rst | (state != ST_本游戏)`，**不在自己的状态就一直保持复位**，所以每次进入都是全新一局，不需要“开始/重开”逻辑。

### 4.4 画面输出

状态机与游戏核都由**像素时钟驱动**，各游戏产生 `rgb` 是 `(de, x, y)` 的组合函数，输出级用 `case(state)` 选通，保证当前像素与当前状态严格对齐。

---

## 5. 四个游戏的实现

### 5.1 SNAKE（贪吃蛇）`game_snake.v`

| 项 | 参数/做法 |
|---|---|
| 场地 | 28 × 18 格，`CELL = 16 px`，原点 (16, 24)，画面 448×288 |
| 速度 | `SPEED = 8` 帧/格 → 7.5 格/s（`frame_tick` 八分频） |
| 身体存储 | 64 深移位寄存器 `bx[0..63] / by[0..63]`，**index 0 = 头**；`len <= 63`，初始 3 |
| 方向 | 请求先锁存，到下一格步进才生效，**禁止 180° 反向** |
| 食物 | 16 位 LFSR（种子 `0xACE1`，抽头 15/13/12/10），`[4:0]`=x、`[9:5]`=y，再夹到场地内 |
| 碰撞 | 出界或撞身体（**尾格豁免**，因为本步尾巴会让出）→ `alive = 0` |
| 结束 | `game_over = !alive`，画面叠“GAME OVER”框，按 K4/K7 回菜单 |
| 渲染 | 每格 16 px 用双色渐变棋盘，头黄、身绿、食物红色脉冲、吃到时头部闪白 |

### 5.2 TETRIS `game_tetris.v`

| 项 | 参数/做法 |
|---|---|
| 场地 | 10 列 × 20 行，`CELL = 16 px`，X0 = 40，画面 160×320 |
| 方块表示 | 每种方块 4×4 = 16 bit 掩码，**4 个旋转观感由预计算表 `mask_of(pidx, rot)` 给出** |
| 旋转 | 直接查表，**没有旋转硬件、也没有踢墙逻辑**：转不动就不转 |
| 随机 | 16 位 LFSR（种子 `0xACE1`）取低 3 位选方块，`3'd7` 回绕到 0 |
| 预览 | 单独维护 `npidx`，右侧 NEXT 框绘制下一块 |
| 重力 | 周期随等级缩短（`level = lines / 10`，`case(level)` 给出下落帧间隔） |
| 操作 | `left_p/right_p` 平移、`up_p` 顺时针转、`down_p` 软降、`ok_p + right_held` 硬降 |
| 消行 | 一次扫描 `nclr` 行，1/2/3/4 行分别得 100/300/500/800 分，行数累加，闪白 18 帧 |
| 计分板 | 右侧 SCORE / LINES / LEVEL 用 8×8 字库 2 倍放大实时绘制 4/4/2 位数 |
| 结束 | 新块生成位置就被占用 → `game_over` |

### 5.3 FLAPPY BIRD（**保留原压缩包的视觉玩法**）`game_flappy.v`

**状态机**：`ST_READY`（等待开始）→ `ST_PLAY` → `ST_PAUSE` → `ST_OVER`。

**物理**：垂直位置用 4 位小数的定点数 `by_q4`（即 1/16 px 精度），速度 `vy_q4`：

| 事件 | 速度变化 |
|---|---|
| 拍翅 `flap_now` | `vy = -56`（向上冲） |
| 下压 `dive_now` | `vy = +40` |
| 无输入 | `vy += 2`（重力） |
| 上/下键按住 | `vy ∓ 8`（微调） |
| 限幅 | `-56 ≤ vy ≤ +48` |

位置再夹到 `BY_MIN = 16 / BY_MAX = 262 px`，于是“按一下会飘、不按会掉”。

**拍翅事件**：`manual_flap_event = ok_p | right_p | up_p`；`restart_game = restart_p | ((state==ST_OVER) && manual_flap_event)`，所以死了按确认键直接重开。

**管道**：间隙 140 px、间距 220 px、横向 1 px / 2 帧（30 px/s），每个新管道的间隙位置由 16 位 LFSR 生成，管道 x 越界后回绕到右侧。

**视觉跟随（核心玩法）**：

```verilog
// target_y(0..255) → 翼顶目标（36..262 px）
wire [15:0] vision_y_scaled    = target_y * 16'd226;
wire [8:0]  vision_top_target = 9'd36 + vision_y_scaled[15:8];
// 每帧最多移动 4 px，避免摄像头抖动导致小鸟瞬移
if      (vision_target_q4 > by_q4 + 64) vision_next_by = by_q4 + 64;
else if (vision_target_q4 + 64 < by_q4) vision_next_by = by_q4 - 64;
else                                    vision_next_by = vision_target_q4;

wire vision_follow_enabled = (state == ST_PLAY) && target_valid
                          && !up_held && !down_held && !flap_now && !dive_now;
```

即：**只有在游戏进行中、OpenMV 给出有效目标、且没有手动按键时**，小鸟才被红块“吸”过去；任何手动操作立刻抢回控制权。没有摄像头/没锁定 → 自动退化为手动拍翅版，游戏照样能玩。

**状态灯**：右上角 12×12 小方块（x 460~472），`target_valid` 时绿色、否则暗红 —— 现场一眼看出 OpenMV 数据是否在进。

### 5.4 BREAKOUT（敲砖块）`game_breakout.v`

| 项 | 参数/做法 |
|---|---|
| 砖块 | 12 列 × 6 行 = **72 块**，每块 32×16 px，原点 (48, 48)，用 72 bit 寄存器做“存活位图” |
| 挡板 | 宽 72 px，y = 286，活动范围 16~464 |
| 手动移动 | 短按 `left_p/right_p` → ±16 px；`move_left_held/move_right_held` **按住连续** → ±4 px/帧 |
| 视觉跟随 | `target_x` 映射到挡板行程：`goal = 16 + (target_x * 376) >> 8`，每帧 ±8 px 收敛 |
| 优先级 | **有手动按键时手动优先**，无按键才让视觉接管 |
| 球 | 8×8，速度 `vx/vy` 各 ±5，反弹：左右墙反 `vx`，顶反 `vy`，底部未接住则掉命 |
| 击球角度 | 按击中挡板位置分 4 段改 `vx`，实现“打边上斜、打中间直” |
| 计分 | 破一块 +10，`score/lives` 用 8×8 字库实时显示；初始 3 命 |
| 结束 | 命耗尽 → `ST_OVER`；砖块清零 → `ST_WIN`；两者 `up_p/ok_p` 重开 |

---

## 6. OpenMV 视觉通道

### 6.1 协议（115200 8N1，无流控，6 字节/帧，50 ms 一帧）

| 字节 | 字段 | 含义 |
|---|---|---|
| 0 | `0xAA` | 帧头 |
| 1 | X | 红块中心 x，0..255 |
| 2 | Y | 红块中心 y，0..255 |
| 3 | CONF | 0 = 无效，非 0 = 有效（也用数值大小表示置信度） |
| 4 | SEQ | 0..127 循环序号 |
| 5 | CHECKSUM | `X ^ Y ^ CONF ^ SEQ` |

### 6.2 PL 侧解析 `openmv_uart_rx.v`

- `BIT_CLKS = (25.2 MHz / 115200) ≈ 219`，`HALF_CLKS` 半位对齐采样（抗相位偏差）
- 状态机 `IDLE → START → DATA → STOP`，**停止位必须为高**才接收一个字节
- 6 字节包状态机，最后字节校验：正确 → `good_frames++`；错误 → `bad_frames++` 且 `target_valid = 0`
- 有效帧 `CONF != 0` → 更新 `target_x/target_y`、`target_valid = 1`、`target_update` 单拍脉冲
- `CONF == 0` 或 **超过 12.6 M 时钟（0.5 s）没收到字节** → `target_valid = 0`（掉线自动失效）

### 6.3 摄像头侧 `openmv/main.py`（**内容未改动**）

- QQVGA 160×120，50 ms 更新，只做红色色块（LAB 阈值 `(30,80,12,127,-5,70)`）
- 启动后需红块稳定约 **2 s** 才进入 `LOCKED`；锁定后只跟随这一目标，短暂丢失沿用最后坐标
- 两个自检脚本：`uart_link_test.py`（只发 Y，用来验证接线/波特率）与主程序

### 6.4 接线

| OpenMV | Mizar Z7 JP2 | FPGA |
|---|---|---|
| UART TX / P4 | pin 1 | **J18** |
| GND | pin 12 / 30 | GND（必须共地） |
| UART RX | pin 2 | H18（本设计不用） |

---

## 7. 文字面板（PS 写、PL 叠加）

| 项 | 做法 |
|---|---|
| 几何 | 30 列 × 6 行字符（`NCOL=30 / NROW=6`），8×8 字库 **2 倍放大**（16 px/字符）→ **480×96** 面板，贴左上角 |
| 存储 | PL 侧 BRAM 真双口：port A 由 PS 通过 BRAM 控制器写 32 位字（**1 字 = 4 个 ASCII**），port B 由像素时钟读 |
| 时钟 | `assign txt_clk = pixel_clk;` —— PL 把像素时钟送给 BD 的 BRAM port B，保证叠加与像素同域 |
| 地址 | `bram_addr = row*32 + (col>>2)`；一行按 32 字（128 字符容量）编址，实际只用前 8 字（30 列） |
| 叠加 | `text_overlay` 夹在 `scene_render` 与 `hdmi_tx` 之间，**只增加 1 个像素时钟延迟** |
| 配色 | 底 `0x013`、边框 `0x0DF`、标题青 `0x0EF`、状态琥珀 `0xFD0`、正文白 `0xFFF` |
| 开关 | `ps_ctrl[9]`（`show_ovl`）。**默认 0（关闭）**，因为面板会盖住菜单标题与第一项绿条 |

---

## 8. PS 侧寄存器映射

### 8.1 `axi_gpio_0` @ `0x41200000`

| 偏移 | 通道 | 配置 | 读回值 | 含义 |
|---|---|---|---|---|
| `+0x00` | 通道 1 | `C_ALL_OUTPUTS=1` | 写值 | `ps_ctrl[31:0]` |
| `+0x04` | 通道 1 | — | `0xFFFFFFFF` | **全输出模式下 GPIO_TRI 读回全 1 是正常值，不是故障** |
| `+0x08` | 通道 2 | 全输入 | `{bt_host_wake, btn_n[3:0]}` | 状态监视 |

### 8.2 `ps_ctrl` 位定义

| 位 | 名称 | 作用 |
|---|---|---|
| 0 | `bt_nreset_n` | 蓝牙 nRESET（低有效，1 = 释放复位） |
| 1 | `bt_wake` | 主机唤醒蓝牙 |
| 4 | 注入 K4 | 左 |
| 5 | 注入 K5 | 右 / 确认（长短按由 `key_ctrl` 判） |
| 6 | 注入 K6 | 上 / 旋转 |
| 7 | 注入 K7 | 下 / 返回 |
| 8 | `inj_en` | 注入总使能（**1 = PC 键盘有效**） |
| 9 | `show_ovl` | 文字面板显示 |

启动脚本写 `0x00000100`：注入使能开、面板关、蓝牙复位释放由 Linux 侧决定。

---

## 9. 工程结构与构建结果

### 9.1 源码组织

| 文件 | 位置 | 作用 |
|---|---|---|
| `top_console_ps.v` | `MizarZ7_PLPS\rtl` | PS+PL 顶层：视频链、按键链、OpenMV、场景、叠加 |
| `top_key_merge.v` | `MizarZ7_PLPS\rtl` | 物理键与注入键合并、蓝牙脚、状态上报 |
| `text_overlay.v` / `font8x8.v` | `MizarZ7_PLPS\rtl` | 文字面板与字库 |
| `clk_hdmi.v` / `video_timing.v` / `hdmi_tx.v` | `MizarZ7_GameConsole\rtl` | MMCM、时序、TMDS |
| `tmds_encoder.v` / `serializer_10to1.v` | 同上 | 8b/10b 与并串转换 |
| `btn_debounce.v` / `key_ctrl.v` | 同上 | 消抖与长短按 |
| `scene_render.v` / `scene_menu.v` | 同上 | 状态机与菜单 |
| `game_snake.v` / `game_tetris.v` / `game_flappy.v` / `game_breakout.v` | 同上 | 四个游戏 |
| `openmv_uart_rx.v` / `ps2_keyboard.v` | 同上 | UART 解析、PS/2 接收 |

顶层 `system_wrapper`（BD 名 `system`）：PS7 + `axi_gpio_0` + BRAM（文本缓冲）+ `gc_v3`（RTL 封装）。

> 另有 `scene_test.v` / `scene_diag.v` / `top_diag.v` / `text_line.v` / `top_game_console.v` 属于早期联调与自检模块，**未参与本次综合**，仅保留备查。

### 9.2 实测资源与时序（2026-10-26 实现后）

| 资源 | 用量 | 占比 |
|---|---|---|
| Slice LUT | 28 156 | 52.92 % |
| Slice Register | 6 637 | 6.24 % |
| Slice | 7 880 | 59.25 % |
| Block RAM Tile | 1 | 0.71 % |
| MMCM | 1 | 25 % |
| Bonded IOB | 26 | 20.80 % |
| DSP | 0 | 0 % |

时序：**WNS = +2.203 ns、WHS = +0.048 ns、失败端点 0 / 20 243**，报告结论 “All user specified timing constraints are met.”

---

## 10. 启动流程（JTAG 直启，不固化）

| 顺序 | 动作 | 说明 |
|---|---|---|
| 1 | 插 JTAG USB + 上电 | PL 未配置时屏幕无输出 |
| 2 | `xsdb mz7_boot_g4.tcl` | `rst -system` → `ps7_init` → `fpga -file top_ps_g4.bit` → 写 `ps_ctrl` → OCM remap → 下 `zImage/dtb/rootfs` → `rwr pc` |
| 3 | 判据 | `halt OK (0)` / `CTRL=0x00000100` / `DOWN_OK` / `BOOT_STARTED` |
| 4 | 起键盘守护 | 日志出现 `CLEAR reg=...` 与 `JTKEY_READY` |
| 5 | 起 PC 键盘窗口 | 方向键按住即按住，`F12` 退出 |

**为什么必须每次重下**：Linux 跑在 DDR、位流由 PC 灌入，掉电即全部丢失；键盘注入守护也在 PC 侧，所以离线演示只能退回板载 K4~K7。

---

## 11. 已验证项与已知限制

### 已实测通过

- 位流下载 + Linux 启动 + HDMI 480×320@60 出图
- PC 键盘 → AXI GPIO → 合并 → 消抖 → 长短按 → 进入游戏（端到端）
- 变位流后守护自动恢复 `bit8`（2 s 重写）
- 四个游戏画面与手动操作
- 综合实现 0 Error、时序全满足

### 已知限制（如实记录）

| 项 | 现状 | 影响 |
|---|---|---|
| P / R（暂停/重开） | 只有 PS/2 通路，PC 键盘无 | 影响很小：Flappy 死亡按确认键即重开，Breakout 按上键即重开 |
| PS/2 键盘 | 代码就绪但**未接**，需 4.7 kΩ 上拉 | 不使用，不影响 |
| 文字面板 vs 菜单 | 面板 480×96 与菜单标题区重叠 | 已默认关闭（`ps_ctrl[9]=0`） |
| OpenMV 联调 | 现场需校红色阈值与 2 s 锁定 | 未锁定时自动退化为手动拍翅，不影响演示 |
| BOOT.BIN 固化 | 有材料未做成 SD 启动方案 | 不能脱离 PC 的 JTAG 独立上电 |

---

## 12. 主要参数速查（便于现场改数值）

| 参数 | 位置 | 当前值 | 改它的效果 |
|---|---|---|---|
| `LONG_CNT` | `key_ctrl.v` | 10 080 000（0.4 s） | 长短按阈值，调大更不容易误触发确认 |
| `CNT_MAX` | `top_console_ps.v` | 252 000（10 ms） | 消抖时间 |
| `SPEED` | `game_snake.v` | 8 帧/格 | 蛇速，越小越快 |
| `PIPE_GAP` / `PIPE_SPACING` | `game_flappy.v` | 140 / 220 px | 难度 |
| `vy` 重力 / 拍翅 | `game_flappy.v` | +2 / -56（1/16 px 单位） | 手感 |
| `BRICK_ROWS × COLS` | `game_breakout.v` | 6 × 12 | 关卡规模 |
| `TIMEOUT_CLKS` | `top_console_ps.v` | 12 600 000（0.5 s） | OpenMV 掉线判定 |
| `H_ACTIVE / V_ACTIVE` | `top_console_ps.v` | 480 / 320 | 改成年 640×480 时窗口会变（时钟不变） |
