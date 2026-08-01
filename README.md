# Network Enhance Auto (KSU)

> KernelSU 模块 · 全自动场景网络优化 · 多维感知 · WebUI 可视化

## 功能

**多维感知**(自动判定当前场景):
- 前台 App
- 运动状态(🚄 高铁 / 🚇 地铁 / ✈️ 飞行 / 📍 静止)—— 通过 GPS 速度 + 基站切换频率自动识别
- 充电状态
- 息屏/亮屏
- 基站位置(用 CID 当指纹,不耗 GPS)
- 时间段
- 信号(WiFi RSSI / 蜂窝 RSRP / SINR / Ping / 丢包)

**九大场景自动切换**:
| 场景 | 触发 | 优化策略 |
|---|---|---|
| 高铁 | GPS>150km/h 或基站频繁切换 | 锁 LTE + 关 5G + 关 WiFi 扫描 + DNS 切腾讯 |
| 地铁 | 基站频繁切换 + WiFi 断 | 锁 LTE + WiFi 弱信号快速断开 + 双 DNS |
| 飞机 | 飞行模式开启 | 关闭所有扫描省电 |
| 游戏 | 前台为游戏 App | 关 WiFi 省电 + TCP 低延迟 |
| 通话 | 前台为通话 App | 增大 socket buffer 抗抖动 |
| 视频 | 前台为视频 App | 大带宽优化 |
| 弱网 | 信号差/丢包高 | 锁 LTE + DNS 优选 |
| 省电 | 息屏/低电量 | 关 5G + 关扫描 |
| 默认 | 平衡 | 标准 WiFi + DNS + 5G 自动 |

**自愈机制**:
- WiFi 假连接(已连但网关不通)→ 自动重连
- 高丢包 → 自动切备用 DNS

**WebUI**:KernelSU 管理器内打开,深色科技风,实时显示所有指标 + 手动切换场景 + 测速。

## 安装

1. 在 KernelSU 管理器中刷入 zip
2. 重启
3. 引擎自动启动
4. KernelSU 管理器 → 模块 → 点击本模块 → 打开 WebUI

## 手动命令

```sh
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh start    # 启动
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh stop     # 停止
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh status   # 状态
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh once     # 单次评估
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh record home   # 记录"家"位置
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh record work   # 记录"公司"位置
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh apply highspeed   # 手动切场景
sh /data/adb/modules/network_enhance_auto/scripts/auto_engine.sh speedtest   # 测速
```

## 自定义规则

编辑 `/data/adb/modules/network_enhance_auto/scripts/auto_rules.conf`,修改后引擎自动生效。

## 文件结构

```
network_enhance_auto/
├── module.prop
├── customize.sh          # 安装时
├── service.sh            # 开机自启
├── scripts/
│   ├── auto_engine.sh    # 主引擎
│   ├── auto_rules.conf   # 规则配置
│   └── scenes/
│       ├── common.sh     # 公共函数 + 状态采集
│       └── apply.sh      # 各场景优化策略
└── webroot/
    └── index.html        # WebUI
```

## 要求

- KernelSU
- Android 11+(API 30+)
- VoLTE 支持(高铁/地铁场景锁 LTE 不会漏接电话的前提)

## 协议

MIT
