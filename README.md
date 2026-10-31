# 校园网 SY —— 多机型统一校园网专用固件

采用“统一公共功能 + 独立设备 profile”的方式。当前包含 **H3C Magic NX30 Pro（MT7981 / Filogic）** 和 **Redmi AX6（Qualcomm IPQ8074 / qualcommax-ipq807x）** 两个独立 profile。AX6 正在进行独立构建验证，不能把 NX30 Pro 镜像刷到 AX6，也不能把 AX6 镜像刷到其他设备。

## 精简功能白名单

- **UA3F**：TPROXY；保留 `kmod-nft-queue`、`kmod-nft-tproxy`、`kmod-sched-bpf`、`libubox-lua` 及必要 netfilter 依赖。BPF TC offload 默认关闭，避免此前无合适 TC 上行接口导致启动失败。
- **MentoHUST**：锐捷认证核心 + LuCI 管理。
- **Dogcom**：Dr.COM 认证核心 + LuCI 管理。
- **ESurfingClient C v2.2.1-r7**：天翼客户端 + LuCI 管理。上游说明主要针对广东校园网，其他地区流程不同，需要实测。
- **闪讯拨号环境**：明确包含 `ppp`、`ppp-mod-pppoe`、`kmod-ppp`、`kmod-pppoe` 四个 PPP/PPPoE 基础包；闪讯客户端自身仍需匹配实际学校的认证方式和拨号参数。
- **WPA-EAP**：完整 `wpad-openssl` supplicant/authenticator；不安装 MiniEAP。
- **UU 游戏加速器**：集成 `xiaodoudou/luci-app-uugamebooster` v2.2.2 和五种架构 view-filter shim。加速主程序由插件首次启用时从官方端下载并校验；此版本含 UA3F 协同规则。
- **PassWall**：nftables 模式，保留 Xray / sing-box；不加 OpenClash、SSR-Plus 或其他代理前端。
- **SQM**：使用系统 `sqm-scripts` + `luci-app-sqm`，合并你上传的 `sqm.zh-cn.lmo` 和各队列 help 文件。
- **5 GHz 桥接**：`iw`、`relayd`、`luci-proto-relay` + STA 掉线恢复服务。
- **主题**：Argon 中文界面。

未列出的插件不加入；删除 OpenClash、Mihomo、Turbo ACC、SSR-Plus、MiniEAP、Docker、下载器、广告过滤等无关组件。

## 默认设置

| 项目 | 默认值 |
|---|---|
| 系统显示名称 | 校园网 SY |
| 主机名 | `Campus-SY` |
| LAN | `192.168.5.1/24` |
| DHCP 池 | `192.168.5.100–192.168.5.249` |
| 2.4 GHz SSID | `SHAYU` |
| 5 GHz SSID | `SHAYU-5G` |
| Wi-Fi 初始密码 | `password` |
| root 初始密码 | `password` |
| DHCP rebind protection | 关闭 |
| 加速 / QoS | 删除 Turbo ACC；保留 SQM |

**安全提示：** 统一的 `password` 只适合作为初始测试密码。正式使用后应立即更改 root 和 Wi-Fi 密码，并限制管理后台只允许从 LAN 访问。

## 5 GHz 桥接策略

不将 `AX / 157 / 80 MHz` 写死为所有设备默认。不同无线芯片、驱动、国家码和上游 AP 的支持范围不同；同一 radio 同时做 STA 上行和 AP 时，下游 AP 要跟随上游信道。强制 157/80 可能导致某些设备 5 GHz 无法启动或 STA 关联失败。

桥接优先使用两端都支持的 WDS，不支持时使用 relayd。看门狗会检查 STA 连接状态，连续掉线后限频恢复；它不能解决错误密码、上游关闭 5 GHz、弱信号或 DFS 事件本身。AX、157、80 MHz 应在具体机型支持后单独测试。

## 通用编译结构

- `configs/packages.common.config`：共用功能包白名单。
- `configs/devices/h3c_magic-nx30-pro.config`：NX30 Pro 专属 target。
- 新设备新增独立 profile、分区容量和驱动配置。
- NX30 Pro 使用原有构建工作流；Redmi AX6 使用独立的 `build-ax6.yml` 工作流和 `redmi_ax6` profile。其他机型仍需新增独立设备配置，不承诺一份镜像刷全部路由器。

构建会检查所需软件包经 `make defconfig` 后是否仍被选中，并要求 NX30 Pro sysupgrade 内的 kernel + rootfs 不超过 60 MiB，为 64 MiB UBI 留出余量。编译成功不等于认证已在每个学校实测。MentoHUST、Dogcom、ESurfingClient 的账号和认证字段需要按学校实际环境配置。


## Redmi AX6

AX6 独立配置与 UBI 镜像校验说明见 [README-AX6.md](README-AX6.md)。AX6 原生 U-Boot 镜像以 `factory.ubi` 输出；工作流额外生成字节完全一致的 `redmi_ax6-campus-factory.bin` 便于按你的文件命名习惯识别，不进行格式转换。
