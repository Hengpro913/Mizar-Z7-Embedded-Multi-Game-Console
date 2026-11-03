# PetaLinux 2026.1 下载与安装教程

> 配套：《升级方案.md》2.4 节（PS+PL 协同方案）、《下载教程.md》（比特流 / BOOT.bin 下载）
> 分工：**第一部分（下载）你做；第二部分（安装）我做**，你只需把文件放进 `D:\FPGAproject\` 并告诉我路径。

---

## 第一部分 · 下载（你做）

### 1. 入口

用你**上次装 Vivado 2026.1 的同一个 AMD 下载页**（需登录授权账号）：
`amd.com` → **Support / Downloads** → 搜索或筛选到 **PetaLinux**，版本选 **2026.1**。

### 2. 下哪个文件（关键，别拿错）

| 要下的 | 文件名特征 | 大小 | 说明 |
| --- | --- | --- | --- |
| ✅ **PetaLinux Installer** | `petalinux-v2026.1-<日期>-installer.run` | **7~10 GB** | **只这一个就够** |
| ⬜ PetaLinux sstate（可选） | `sstate_aarch64_*.tar.gz`、`sstate_arm_*.tar.gz` | 各数 GB | 预编译缓存，**可不下**，下了能加快首次构建 |
| ❌ AMD Unified Installer | `AMD_Unified_*.exe` | 几十~上百 GB | 含 Vivado+Vitis，**我们已装过 Vivado 2026.1，不要下** |
| ❌ 任何 BSP | `*-bsp-*.tar.gz` | 数 GB | 是给别的开发板用的，**本工程用不到** |

> 下载页会要求勾选用户协议（Export Compliance / Terms），勾了才能出现链接。

### 3. 放哪里

放到 **`D:\FPGAproject\`** 即可（放好后**不用解压、不用改名**）。
建议单独放一层目录更清爽，例如 `D:\FPGAproject\petalinux_installer\`。

### 4. 校验（可顺手做，非必须）

```powershell
Get-FileHash 'D:\FPGAproject\petalinux_installer\petalinux-v2026.1-xxxx-installer.run' -Algorithm SHA256
```

拿结果和下载页给出的 SHA256 对一下即可。**对不上就重下** —— 解压到一半失败通常是下载不完整。

---

## 第二部分 · 安装（我做）

### 0. 当前环境现状（已就绪，无需你操作）

| 项 | 状态 |
| --- | --- |
| WSL2 | 已启用；WSL 3.0.1.0 / 内核 6.18.40.1-microsoft-standard-WSL2 |
| 发行版 | `petalinux`（Ubuntu **24.04.5 LTS**），根目录 `D:\WSL\` |
| 资源 | `.wslconfig` → **内存 12 GB / Swap 16 GB / 16 核** |
| 主机依赖 | 已装齐（gcc/make/flex/bison/gawk/chrpath/socat/diffstat/cpio/rsync/`dtc`/gcc-multilib/libsdl1.2-dev/xterm + python3-pexpect/jinja2/git/subunit/pip 等） |
| apt 源 | 直连 `archive.ubuntu.com`，实测 ≈ 4.7 MB/s，无需换源 |

### 1. 先建一个**非 root 用户**（重要，必做）

**Yocto/bitbake 拒绝以 root 运行**（`ERROR: Do not use Bitbake as root.`），所以整套必须跑在普通用户下。
`wsl --import` 进来的发行版默认用户是 root，需要新建一个普通用户并设为 WSL 默认登录用户：

```bash
# 我将在 WSL 内执行
useradd -m -s /bin/bash -G sudo plnx
echo 'plnx ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/plnx
chmod 440 /etc/sudoers.d/plnx
# 再把 /etc/wsl.conf 的 [user] default 设为 plnx，然后 wsl --shutdown 重启
```

### 2. 把安装包拷进 WSL 的 ext4 家目录

**不要直接在 `/mnt/d`（NTFS）上解压/安装** —— 会非常慢，而且 Yocto 在 NTFS 上常出诡异错误（符号链接、权限位丢失）。

```bash
mkdir -p ~/petalinux_install
cp /mnt/d/FPGAproject/petalinux_installer/petalinux-v2026.1-*-installer.run ~/petalinux_install/
chmod +x ~/petalinux_install/*.run
```

### 3. 安装到 `/opt/petalinux`

```bash
sudo mkdir -p /opt/petalinux && sudo chown -R plnx:plnx /opt/petalinux
~/petalinux_install/petalinux-v2026.1-*-installer.run -d /opt/petalinux
```

过程中会要求**接受许可协议**（输入 `y`）。解压安装约需 8~10 GB 空间，耗时视磁盘而定。

### 4. 每次使用前激活环境

```bash
source /opt/petalinux/settings.sh
echo $PETALINUX          # 应输出 /opt/petalinux
```

建议把这一行加进 `~/.bashrc`，省得每次手输。

### 5. 核对宿主 OS 支持矩阵（我做）

安装脚本 / release notes 会写明支持的 Ubuntu 版本（AMD 历来只认特定 LTS）。
- 若是 **24.04** → 直接用现有环境
- 若是 **22.04** → 我重装一版 22.04 的 WSL rootfs（流程同上，我从 `cdimages.ubuntu.com` 拉 jammy 镜像），你无需操作

---

## 第三部分 · 下一步（M1 里程碑，我做）

1. 用现有 PL 位流先建一个 xc7z020 工程，编 `petalinux-image-minimal`（**先验工具链，不追功能**）
2. 再进 Vivado 做 PS Block Design（DDR3 = `MT41J256M16 RE-125`、SD、UART0→EMIO 接 BLE）
3. 出首个 `BOOT.bin` → SD 卡启动 → 跑通"PS 读键 → AXI 写 PL → 游戏动"的闭环

---

## 第四部分 · 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 下载页看不到下载链接 | 没登录 AMD 账号，或没勾选协议 |
| 下载到 99% 失败 / 断流 | 换浏览器或断点续传；**务必核对 SHA256**，不完整会在解压阶段报奇怪的错 |
| 安装报 `Permission denied` | `.run` 没加执行位（`chmod +x`）；或试图以 root 装到非 `$HOME` 目录而未 `chown` |
| 构建报 `Do not use Bitbake as root` | 用第 1 步建的 `plnx` 普通用户，不要用 root |
| 构建到一半卡死 / 内存不足 | 构建期间**关掉 Vivado**；必要时把 Yocto 并发压到 `BB_NUMBER_THREADS=4`（在 `petalinux-config` 里改） |
| WSL 输出乱码 | 只是 PowerShell 解码问题，**看 exit code 与 `wsl -l -q` 即可** |
| `systemd-binfmt.service failed` | WSL 常见无害现象，忽略 |
| D 盘空间不够 | 目前空闲约 180 GB，够用；构建中间产物可用 `bitbake -c clean` 回收 |
