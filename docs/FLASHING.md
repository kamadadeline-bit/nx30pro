# H3C Magic NX30 Pro — 刷写前核对清单

本仓库的 GitHub Actions 只负责构建与上传构建产物，不会自动刷写路由器。

1. 下载并解压 Actions artifact。
2. 检查 `BUILD-INFO.txt`，确认 `DEVICE_PROFILE=h3c_magic-nx30-pro` 并记录 LEDE 源码 commit。
3. 根据 `SHA256SUMS` 对镜像校验。
4. 区分 U-Boot 恢复镜像与运行 OpenWrt 后的 sysupgrade 镜像。不能仅凭文件名判断 U-Boot 页面支持的镜像格式。
5. 不要将 `sysupgrade.bin` 上传给 U-Boot，除非当前 U-Boot 的文档明确说明支持该格式。
6. 不要覆盖 U-Boot、BL2、FIP 等引导分区。
7. 首次构建成功也不代表已经通过 NX30 Pro 实机验证；请先核对镜像列表、大小和当前 U-Boot 版本。

## 首次启动服务策略

首次启动脚本会把 UA3F 的服务保持禁用，设定 TPROXY、端口 1080、UA 为 `Mozilla/5.0`；OpenClash 同样保持禁用。先分别启动并验证，再规划分流，避免同时对相同流量创建冲突的透明代理规则。

预置 Mihomo 核心不会自动启用 OpenClash，也不会自动解决内存压力。此前设备日志记录过内核 OOM killer 杀掉 Clash 进程，需在实机上继续测试核心内存、Geo 数据和订阅配置。
