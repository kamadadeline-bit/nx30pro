# H3C Magic NX30 Pro — LEDE/OpenWrt 独立构建

本仓库仅面向 H3C Magic NX30 Pro（MT7981 / MediaTek Filogic）。不复用 AX3000T、CR660X 等其他型号的 target 或镜像布局。

## 当前构建目标

- 源码：`https://github.com/coolsnowwolf/lede`，默认分支 `master`
- 设备 profile：`h3c_magic-nx30-pro`
- UA3F：默认锁定正式标签 `v3.7.0`
- OpenClash：源码来自官方仓库 `vernesong/OpenClash`
- UA3F 指定组件：`kmod-nft-queue`、`kmod-nft-tproxy`、`kmod-sched-bpf`、`libubox-lua`，以及 Kconfig/包 Makefile 所需依赖
- Mihomo Meta 核心：由 GitHub Actions 从最新稳定 Release 取 Linux ARM64 压缩资产，校验 GitHub 提供的 SHA-256 digest 后可选预置进镜像
- 安全默认值：UA3F 使用 TPROXY、端口 1080、UA 为 `Mozilla/5.0`；UA3F 和 OpenClash 首次启动均保持禁用，手动验证后再开启

> 预置 Mihomo 核心仅减少首次下载和缺核心问题，不会修复此前 OOM 导致 Clash 进程被内核杀死的问题。需要另行测试内存占用、规则量和 DNS 配置。首次使用时不要让 UA3F 与 OpenClash 同时对同一流量路径重复接管。

## 自动构建

此仓库的 `.github/workflows/build.yml` 在向 `main` 分支提交构建配置时触发，并保留手动 `workflow_dispatch` 入口。成功后会上传 `NX30Pro-LEDE-UA3F-OpenClash` artifact，里面包括设备镜像、`build.config`、`BUILD-INFO.txt` 和 `SHA256SUMS`。

可手动调整以下输入：
- `include_mihomo_core`：是否把经过 SHA-256 校验的 ARM64 Mihomo 核心预置进 rootfs。首次自动构建默认启用；手动构建可关闭。
- `lede_ref`：LEDE 分支或 tag。
- `ua3f_ref`：UA3F 分支或 tag。
- `openclash_ref`：OpenClash 分支或 tag。

构建成功只表示编译器成功生成镜像，**不等于已经在实机验证可刷或可运行**。

## 刷机安全

1. 下载并解压 Actions artifact。
2. 检查 `BUILD-INFO.txt` 中的源码、设备 profile、commit。
3. 校验 `SHA256SUMS`。
4. 区分 U-Boot 恢复镜像与在 OpenWrt 中升级的 sysupgrade 镜像；不要仅凭文件名就上传。
5. 不要覆盖 U-Boot、BL2、FIP 等引导分区。
6. 首次构建后请先把完整文件列表和当前 U-Boot 页面发来，确认准确镜像后再刷。

详见 [docs/FLASHING.md](docs/FLASHING.md)。
