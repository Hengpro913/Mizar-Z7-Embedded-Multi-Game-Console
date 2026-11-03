# Mizar Z7 嵌入式游戏机 —— 参赛交付包

- 打包日期：2026-11-02
- 目标器件：AMD Zynq-7020（xc7z020clg400-2）/ Mizar Z7 7020 开发板
- 赛题：大学生 FPGA 创新设计大赛 AMD 3.3 初级自选赛题

---

## 1. 目录说明

| 目录 | 内容 | 用途 |
|---|---|---|
| `01_boot_runtime/` | `mz7_boot_g4.tcl`、`ps7_init_usb.tcl`、`zImage`、`system_raw.dtb`、`rootfs_raw.cpio.gz`、`top_ps_g4.bit`、`BOOT.BIN`、`tools/` | **上电后直接用这一套启动**，不需要 Vivado 图形界面 |
| `02_fpga_src/` | `MizarZ7_PLPS/`（PS+PL 顶层工程源码、约束、xpr、最新 bit、xsa）、`MizarZ7_GameConsole/`（HDMI 游戏 RTL、约束、仿真、最新 bit） | 重新综合 / 修改 RTL 时使用 |
| `03_docs/` | 功能实现说明、下载教程、升级方案、PetaLinux 安装教程、Mizar Z7 用户手册 | 报告与答辩材料 |

`01_boot_runtime/tools/` 里的 5 个文件是“PC 键盘 → 板载按键注入”链路：

| 文件 | 作用 |
|---|---|
| `jtkey_daemon.tcl` | xsdb 守护，轮询 `jtkey.cmd` 并把按键写进 AXI GPIO `0x41200000` |
| `jtkey_daemon_run.cmd` | 启动守护（会生成 `jtkey_daemon.log`） |
| `jtkey_pc.ps1` | PC 键盘抓取 → 写 `jtkey.cmd` 邮箱 |
| `jtkey_pc.cmd` | 双击启动上面的 ps1 |
| `jtkey.cmd` | 邮箱文件，内容是一个 0~15 的数字（0 表示无按键） |

---

## 2. 断电后上电的固定流程（4 步，顺序不能乱）

> 硬规则：**同一根 JTAG 同时只能有一方占用**。守护和下载脚本同时跑，`ps7_init` 会读 `0xF8007080` 报 `AHB AP transaction error`，PS 会被锁死，只能断电重来。

1. **关掉所有黑色命令行窗口**（`xsdb` / `hw_server` / 键盘窗口全关）。
2. **下载并启动**：双击或命令行运行
   ```
   xsdb 01_boot_runtime\mz7_boot_g4.tcl
   ```
   看到 `BOOT_STARTED` 且 HDMI 出现画面，说明成功。
   关键判据（脚本会打印）：`halt OK (0)` → `CTRL=0x00000100` → `APER_AFTER_PSINIT=0x01FC040D` → `DOWN_OK` → `BOOT_STARTED`
3. **等画面稳定**后，再开守护：
   ```
   01_boot_runtime\tools\jtkey_daemon_run.cmd
   ```
   日志里出现 `JTKEY_READY` 才算就绪（第一次启动需十几秒）。
4. **最后**双击 `01_boot_runtime\tools\jtkey_pc.cmd`，让键盘窗口获得焦点。窗口标题旁按 **F12** 退出。

掉电即清空：重新上电必须从第 1 步重来（当前没有固化到 QSPI/SD 的 BOOT.BIN 流程）。

---

## 3. 键位表

### 板载物理按键（永久兜底，低有效）

| 按键 | 功能 |
|---|---|
| K4 | 左 / 返回上一项 |
| K5 | 右 / 确认（长按 ≥0.9 s 触发 ok_p） |
| K6 | 上 / 拍翅（Flappy） |
| K7 | 下 / 返回菜单（长按） |

### PC 键盘注入（`jtkey_pc.ps1`）

| PC 键 | 映射 |
|---|---|
| ← / A | K4 左（**按住即持续**，适合 Breakout 挡板） |
| → / D | K5 右 |
| ↑ / W | K6 上 |
| ↓ / S | K7 下 |
| Enter / Space | K5 长按 0.9 s = 确认 / Tetris 落地 / Flappy 拍翅 |
| Q / Esc | K7 长按 0.9 s = 返回菜单 / Flappy 重开 |
| F12 | 退出键盘窗口 |

注意：注入键只能给出**脉冲**（`up_p/down_p/ok_p/...`），**不会产生 held 电平**；`up_held/down_held` 只来自 PS/2 键盘。因此注入方式无法靠“按住上键”去临时关闭视觉跟随。

---

## 4. OpenMV 视觉联调

### 硬件接线

```
OpenMV UART3 TX (P4) ──> Mizar Z7 JP2 pin 1 (J18)   (LVCMOS33, 输入)
OpenMV GND           ──> JP2 GND (pin 12 或 30)     ← 必须共地，否则 J18 悬空收不到
```

约束与实际布线已核对：`constr/mizar_z7_plps.xdc` 中 `J18 → openmv_rx`，`impl_1/system_wrapper_io_placed.rpt` 显示 `J18 | openmv_rx | LVCMOS33 | INPUT`，网络连到 `system_i/gc_v3/inst/u_openmv`。

### 协议（6 字节）

```
0xAA  X  Y  CONF  SEQ  XOR(前5字节)
```

- `X/Y`：0~255 归一化坐标
- `CONF = 0` → 视为无效目标（`target_valid = 0`）
- `SEQ` bit7 为事件标志
- 帧率 20 Hz（每 50 ms 一帧，`UPDATE_PERIOD_MS = 50`）
- FPGA 侧 **0.5 s 收不到合法帧** 就清 `target_valid`（`top_console_ps.v`：`TIMEOUT_CLKS = 12_600_000` @ 25.2 MHz）

### 板端可视判据（不需要 PC）

- **FLAPPY** 右上角 12×12 小方块（x 460~471 / y 8~19）：绿 `#0F0` = `target_valid=1`；暗红 `#700` = 无效
- **BREAKOUT** 同位置的灯（x 452~467 / y 8~23），且 `ST_READY / ST_PLAY` 下挡板会自动跟随视觉目标（每帧 8 px）

### 摄像头端程序（main.py）

> **本压缩包未包含 `main.py`**：打包时摄像头盘 `E:` 未挂载。请从 OpenMV 的 `/flash/main.py` 拷贝一份补进 `01_boot_runtime/`。

已知关键参数（用于排查）：

```python
UART_PORT = 3; BAUD_RATE = 115200; UPDATE_PERIOD_MS = 50
RED_THRESHOLD = (30, 80, 12, 127, -5, 70)   # LAB 阈值
MIN_PIXELS = 180                            # QQVGA 160x120 中约 13x13
ACQUIRE_TIME_MS = 2000                      # 连续锁定 2 s 才算
# 未锁定 → send_frame(127, 127, 0, False)   # CONF=0 → target_valid=0
```

实测经验：偏暗的红块会因 `L < 30` 或 `B > -5` 被整块排除（实测同一画面 `STRICT 0` 个块，放宽到 `(15,90,25,127,-40,80)` 得 1833 像素）。现场光照不足时优先**照亮红块**，其次再改阈值。

---

## 5. 已知限制

1. **P/R 无 PC 通路**：PL 侧未接 PS/2，需要 4.7 kΩ 上拉才能用 PS/2 键盘；目前用 PC 注入替代。
2. **文字面板与菜单标题重叠**：`text_overlay` 的坐标与 `scene_menu` 标题有重叠，属视觉瑕疵，不影响功能。
3. **蓝牙** `hci0: BCM: Reset failed (-110)`：固件缺失，未启用。
4. **无固化启动**：当前只能 JTAG 直启，掉电即清空；`01_boot_runtime/BOOT.BIN` 为早期尝试产物，**未验证**，不要直接当量产方案。
5. **视觉跟随优先级**：`vision_follow_enabled` 要求 `state == ST_PLAY` 且 `!flap_now && !dive_now`，手动拍翅会覆盖视觉一帧，属设计行为。

---

## 6. 重新综合要点

- PS+PL 工程：`02_fpga_src/MizarZ7_PLPS/plps_prj/MizarZ7_PLPS.xpr`
  - 顶层 `top_system.v` → `top_console_ps.v`（含 `gc_v3` 游戏机实例 + AXI GPIO + openmv_rx）
  - 约束 `constr/mizar_z7_plps.xdc`
  - 综合后导出 bit，覆盖 `01_boot_runtime/top_ps_g4.bit` 即可继续用同一套启动脚本
- 纯 PL 游戏工程：`02_fpga_src/MizarZ7_GameConsole/`（`create_project.tcl` 可一键建工程）
  - 顶层 `top_game_console.v`，约束 `constr/mizar_z7.xdc`
  - 仿真：`sim/tb_tmds_encoder.v`、`sim/tb_video_timing.v`
