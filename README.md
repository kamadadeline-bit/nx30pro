# H3C Magic NX30 Pro — LEDE/OpenWrt 独立构建

本仓库仅面向 H3C Magic NX30 Pro（MT7981 / MediaTek Filogic），不复用 AX3000T、CR660X 等其他机型的 target 或镜像布局。

## 本次固件功能

- 源码：`https://github.com/coolsnowwolf/lede`，默认分支 `master`
- 设备 profile：`h3c_magic-nx30-pro`
- UA3F：使用 TPROXY，保留指定的完整 QQBrowser UA；默认关闭可能因无合适 TC 上行接口而启动失败的 BPF TC offload
- UA3F 依赖：`kmod-nft-queue`、`kmod-nft-tproxy`、`kmod-sched-bpf`、`libubox-lua`，并校验相关 netfilter 依赖在 Kconfig 后仍存在
- PassWall：从 Openwrt-Passwall 官方维护的 luci 与 packages feeds 构建，使用 nftables 透明代理；显式禁用独立 SSR-Plus 页面，并关闭 PassWall 内部可选的 ShadowsocksR-libev client/server
- 主题：加入 Jerrykuku 的 Argon 稳定版 v3.1.0，默认深色/浅色可切换并设置为默认主题，附带 Argon 配置页与 LuCI 简体中文基础语言包；主题包官方介绍包括响应式布局和亮暗模式切换
- MentoHUST：集成锐捷客户端守护进程 `mentohust` 和 `luci-app-mentohust` 管理页面；校园网账号、密码、网卡和认证参数需在刷机后自行填写
- Wi-Fi 中继恢复：附带 `wifi-bridge-guard`，每 60 秒检查已配置的 STA 上行，连续 3 次未连接后尝试恢复对应 radio；每个 radio 至多每 10 分钟恢复一次
- 无线中继协议：加入 `relayd` 与 `luci-proto-relay`，用于需要 relayd 的非 WDS 中继组网
- 保留现有 OpenClash 包并预置经过 SHA-256 校验的 ARM64 Mihomo 核心；UA3F 与 OpenClash 首次启动均保持禁用，避免在确认规则前自动接管流量

## 管理界面主题

首次启动默认进入 Argon 主题。可在系统菜单的 Argon 配置中切换深浅色模式与强调色；主题只改变管理界面的显示方式，不会改变无线协商速率或桥接链路。

## 无线 5 GHz 说明

自动恢复能处理部分 STA 接口掉线或无线接口未重新关联的情况，但不能保证修复上游 AP 关闭 5 GHz、SSID/密码改变、信号过弱、国家码不一致或 DFS 雷达检测导致的换信道。为了稳定测试，优先把上游 5 GHz 设为当地法规允许的非 DFS 信道（例如常见的 36–48 区间，具体取决于国家/地区及 AP），并确保桥接 STA 和本机 AP 的信道跟随关系没有被手动固定配置破坏。

默认看门狗会在无线桥接 STA 长时间掉线后重新拉起对应 radio，过程中该 radio 的无线客户端可能短暂断开。可用以下命令关闭：

```sh
uci set wifi-bridge-guard.main.enabled='0'
uci commit wifi-bridge-guard
/etc/init.d/wifi-bridge-guard restart
```

## 代理栈使用注意

PassWall 和 OpenClash 同时装入镜像，但不要在未验证规则的情况下同时启用它们并让同一 LAN 流量经过两套透明代理。UA3F 默认使用 TPROXY 配置，但服务本身首次启动仍保持禁用。逐项测试 DNS、IPv4/IPv6、旁路由/中继以及认证流量后再启用所需服务。

## 自动构建

向 `main` 提交 `configs/**`、`scripts/**`、`files/**` 等文件会触发 GitHub Actions。构建成功后会上传 `NX30Pro-LEDE-UA3F-OpenClash` artifact，包括设备镜像、`build.config`、`BUILD-INFO.txt` 与 `SHA256SUMS`。

构建日志会记录 LEDE、UA3F、OpenClash、PassWall 两个 feed、MentoHUST 与 Argon 主题的 commit。构建成功只表示编译器生成了镜像，**不等于已在 NX30 Pro 实机验证可刷或可运行**。刷机前必须检查 `BUILD-INFO.txt`、校验 `SHA256SUMS`，并确认所选文件是适用的 sysupgrade 镜像；不要覆盖 U-Boot、BL2 或 FIP 分区。

详见 [docs/FLASHING.md](docs/FLASHING.md)。
