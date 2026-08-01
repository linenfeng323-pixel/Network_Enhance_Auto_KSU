#!/system/bin/sh
# apply.sh — 各场景优化策略应用 (root 版, 仅做真实生效的优化)
# 用法: sh apply.sh <mode>

MODE="${1:-normal}"

case "$MODE" in
    # ============================================================
    # 高铁场景: 高速移动, 频繁切换基站
    # 策略: 网络重选优化 + LTE 锁定 + 禁用 WiFi 扫描 + DNS 切低延迟
    # ============================================================
    highspeed)
        # 锁定 LTE (高铁场景 5G 切换频繁反而卡, 4G LTE 连续覆盖更稳)
        # 注意: VoLTE 已普及, 锁 LTE 不会漏接电话
        settings put global preferred_network_mode 11  # LTE Only
        # 禁用 WiFi 扫描 (省电 + 避免频繁尝试连不上)
        settings put global wifi_scan_throttle_enabled 1
        settings put global wifi_suspend_optimizations_enabled 1
        # 关闭载波聚合跳频 (减少切换)
        settings put global lte_endc_available 0 2>/dev/null
        # DNS 切腾讯 (高铁覆盖通常电信/联通, 腾讯 DNSPod 解析快)
        settings put global dns1 119.29.29.29
        settings put global dns2 119.28.28.28
        # 关闭 5G (高铁上 5G 频繁 nSA 切换耗电且不稳)
        settings put global nr_state 0 2>/dev/null
        ;;
    # ============================================================
    # 地铁场景: 地下, 信号频繁跳变, WiFi 难连
    # 策略: 弱网优化 + 锁 LTE + 智能重连
    # ============================================================
    subway)
        settings put global preferred_network_mode 11  # LTE Only
        settings put global wifi_scan_throttle_enabled 1
        settings put global wifi_suspend_optimizations_enabled 1
        # WiFi 弱信号快速断开 (地铁里残留 WiFi 连接反而拖慢切换)
        settings put global wifi_bad_rssi_threshold -75
        settings put global wifi_bad_rssi_threshold_2g -75
        settings put global wifi_bad_rssi_threshold_5g -75
        # DNS 双备份
        settings put global dns1 223.5.5.5
        settings put global dns2 119.29.29.29
        # 降低切换延迟
        settings put global mobile_data_always_on 0 2>/dev/null
        ;;
    # ============================================================
    # 飞机场景: 飞行模式, 优化关闭一切蜂窝/WiFi 扫描省电
    # ============================================================
    flight)
        # 飞行模式已开, 只需关闭后台扫描省电
        settings put global wifi_scan_throttle_enabled 1
        settings put global wifi_suspend_optimizations_enabled 1
        # 关闭蓝牙扫描省电 (除非有蓝牙耳机连接)
        settings put global ble_scan_always_enabled 0 2>/dev/null
        ;;
    # ============================================================
    # 游戏: 低延迟优先
    # ============================================================
    game)
        # WiFi 优化 (关省电 + 关扫描节流)
        settings put global wifi_suspend_optimizations_enabled 0
        settings put global wifi_scan_throttle_enabled 0
        settings put global wifi_idle_ms 7200000
        # DNS 切低延迟
        settings put global dns1 223.5.5.5
        settings put global dns2 119.29.29.29
        # TCP 缓冲优化 (root 可写)
        echo 1 > /proc/sys/net/ipv4/tcp_low_latency 2>/dev/null
        echo 1 > /proc/sys/net/ipv4/tcp_no_metrics_save 2>/dev/null
        ;;
    # ============================================================
    # 视频通话: 抗抖动
    # ============================================================
    voip)
        settings put global wifi_suspend_optimizations_enabled 0
        settings put global wifi_scan_throttle_enabled 0
        # 增大 socket buffer (root)
        echo 262144 > /proc/sys/net/core/rmem_max 2>/dev/null
        echo 262144 > /proc/sys/net/core/wmem_max 2>/dev/null
        ;;
    # ============================================================
    # 视频流: 大带宽
    # ============================================================
    video)
        settings put global wifi_suspend_optimizations_enabled 0
        settings put global wifi_scan_throttle_enabled 0
        settings put global dns1 223.5.5.5
        settings put global dns2 119.29.29.29
        ;;
    # ============================================================
    # 弱网: 信号差
    # ============================================================
    weaknet)
        settings put global preferred_network_mode 11  # LTE Only
        settings put global wifi_scan_throttle_enabled 1
        settings put global wifi_suspend_optimizations_enabled 0
        settings put global dns1 223.5.5.5
        settings put global dns2 119.29.29.29
        ;;
    # ============================================================
    # 省电: 息屏/睡眠/低电量
    # ============================================================
    powersave)
        settings put global wifi_suspend_optimizations_enabled 1
        settings put global wifi_scan_throttle_enabled 1
        settings put global ble_scan_always_enabled 0 2>/dev/null
        # 恢复网络制式自动
        settings put global preferred_network_mode 0 2>/dev/null
        # 关闭 5G 省电 (5G 基带耗电)
        settings put global nr_state 0 2>/dev/null
        ;;
    # ============================================================
    # 默认/正常: 平衡
    # ============================================================
    normal|*)
        settings put global wifi_suspend_optimizations_enabled 0
        settings put global wifi_scan_throttle_enabled 0
        settings put global wifi_idle_ms 7200000
        settings put global dns1 223.5.5.5
        settings put global dns2 119.29.29.29
        # 恢复网络制式自动
        settings put global preferred_network_mode 0 2>/dev/null
        # 开启 5G
        settings put global nr_state 1 2>/dev/null
        ;;
esac

echo "$MODE" > /data/local/tmp/ne_auto/current_mode
date +%s > /data/local/tmp/ne_auto/last_switch
echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) SWITCH -> $MODE" >> /data/local/tmp/ne_auto/events.log
exit 0
