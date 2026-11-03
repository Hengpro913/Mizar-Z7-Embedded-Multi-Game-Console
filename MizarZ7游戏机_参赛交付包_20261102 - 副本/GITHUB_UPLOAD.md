# GitHub 上传说明

这是一个面向源码复现的 GitHub 副本。原始交付包未被修改，仍然保留了可直接运行的完整文件。

为避开 GitHub 仓库的大文件限制，本副本未包含以下可重建或体积较大的文件：

- `rootfs_raw.cpio.gz`
- `zImage`
- `BOOT.BIN`
- 各工程的 `.bit` 位流
- `system_raw.dtb`
- Vivado 自动生成的 `.bak` 文件
- 第三方《Mizar Z7 用户手册》PDF

需要直接运行演示时，可从原始交付包中取用这些文件。若希望 GitHub 用户直接下载运行包，请将经过确认的镜像和位流上传到仓库的 **Releases**，不要提交进 Git 仓库。

源码、Vivado 工程、Block Design、XCI、约束、Tcl、仿真和 Markdown 文档均已保留。工程可继续通过 Vivado/PetaLinux 流程重新构建。
