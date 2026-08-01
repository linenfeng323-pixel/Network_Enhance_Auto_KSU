#!/system/bin/sh
# auto_common.sh — Network Enhance Auto 公共函数库 (KSU root 版)
# ----------------------------------------------------------------------
NE_AUTO_DIR="/data/local/tmp/ne_auto"
NE_AUTO_STATE="$NE_AUTO_DIR/state"
NE_AUTO_EVENT="$NE_AUTO_DIR/events.log"
NE_AUTO_LOG="$NE_AUTO_DIR/engine.log"
NE_AUTO_PID="$NE_AUTO_DIR/engine.pid"
NE_AUTO_CURRENT="$NE_AUTO_DIR/current_mode"
NE_AUTO_LASTSWITCH="$NE_AUTO_DIR/last_switch"
NE_AUTO_PENDING="$NE_AUTO_DIR/pending"
NE_AUTO_RULES="${MODDIR:-$(dirname "$(readlink -f "$0" 2>/dev/null)" 2>/dev/null)}/scripts/auto_rules.conf"
[ -f "$NE_AUTO_RULES" ] || NE_AUTO_RULES="$(dirname "$0" 2>/dev/null)/auto_rules.conf"

mkdir -p "$NE_AUTO_DIR" 2>/dev/null

# 日志
ne_log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "?")
    echo "$ts $1" >> "$NE_AUTO_LOG" 2>/dev/null
}

# 事件日志
ne_event() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "?")
    echo "$ts $1" >> "$NE_AUTO_EVENT" 2>/dev/null
}

# 通知栏 (root 可直接调 cmd notification)
ne_notify() {
    local title="${1:-Network Enhance}"
    local text="${2:-}"
    cmd notification post -t "$title" --text "$text" ne_auto 2>/dev/null
    return 0
}

# ---------------- 状态采集 ----------------

# 前台 App
ne_get_topapp() {
    local pkg
    pkg=$(cmd activity get-top-resumedActivity 2>/dev/null | grep -oE 'u0 [a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1 | cut -d' ' -f2 | cut -d'/' -f1)
    [ -n "$pkg" ] && { echo "$pkg"; return 0; }
    pkg=$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | head -1 | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1 | cut -d'/' -f1)
    [ -n "$pkg" ] && { echo "$pkg"; return 0; }
    pkg=$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -1 | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1 | cut -d'/' -f1)
    echo "$pkg"
}

# 主服务小区 CID
ne_get_cellid() {
    local cid
    cid=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'mCellIdentity[^ ]* [^ ]* ci=[0-9]+' | head -1 | grep -oE 'ci=[0-9]+' | cut -d= -f2)
    [ -n "$cid" ] && { echo "$cid"; return 0; }
    cid=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'cid[: =]+[0-9]+' | head -1 | grep -oE '[0-9]+')
    echo "$cid"
}

# 蜂窝 RSRP
ne_get_cell_rsrp() {
    local rsrp
    rsrp=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'ssRsrp[: =]*-?[0-9]+' | head -1 | grep -oE '-?[0-9]+' | head -1)
    [ -n "$rsrp" ] || rsrp=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'rsrp[: =]*-?[0-9]+' | head -1 | grep -oE '-?[0-9]+' | head -1)
    echo "$rsrp"
}

# 蜂窝 SINR
ne_get_cell_sinr() {
    local sinr
    sinr=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'ssSinr[: =]*-?[0-9]+' | head -1 | grep -oE '-?[0-9]+' | head -1)
    [ -n "$sinr" ] || sinr=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'sinr[: =]*-?[0-9]+' | head -1 | grep -oE '-?[0-9]+' | head -1)
    echo "$sinr"
}

# WiFi RSSI
ne_get_wifi_rssi() {
    local rssi
    rssi=$(cmd wifi status 2>/dev/null | grep -oE 'RSSI[: =]*-?[0-9]+' | grep -oE '-?[0-9]+' | head -1)
    [ -n "$rssi" ] || rssi=$(dumpsys wifi 2>/dev/null | grep -oE 'rssi[: =]*-?[0-9]+' | head -1 | grep -oE '-?[0-9]+' | head -1)
    echo "$rssi"
}

# Ping 测试 (2 包 1s, 阻塞 <= 2s)
ne_ping_test() {
    local target="${1:-223.5.5.5}"
    local out rtt loss
    out=$(ping -c 2 -W 1 "$target" 2>/dev/null)
    if [ -z "$out" ]; then
        echo "? 100"
        return 0
    fi
    rtt=$(echo "$out" | grep -oE 'rtt min/avg/max[^=]*= [0-9.]+/[0-9.]+/[0-9.]+' | grep -oE '/[0-9.]+' | head -1 | tr -d '/')
    [ -z "$rtt" ] && rtt=$(echo "$out" | grep -oE 'time[= ][0-9.]+' | tail -1 | grep -oE '[0-9.]+')
    loss=$(echo "$out" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+' | head -1)
    [ -z "$rtt" ] && rtt="?"
    [ -z "$loss" ] && loss="?"
    echo "$rtt $loss"
}

# 网关连通性
ne_gateway_ok() {
    local gw
    gw=$(ip route 2>/dev/null | grep -oE 'default via [0-9.]+' | head -1 | grep -oE '[0-9.]+')
    [ -z "$gw" ] && { echo "0"; return 0; }
    ping -c 1 -W 1 "$gw" >/dev/null 2>&1 && echo "1" || echo "0"
}

# WiFi 是否已连接
ne_wifi_connected() {
    cmd wifi status 2>/dev/null | grep -q 'Wi-Fi is connected' && echo "1" || echo "0"
}

# 充电状态: 1=充电中 0=未充电
ne_charging() {
    dumpsys battery 2>/dev/null | grep -q 'AC powered: true' && { echo "1"; return 0; }
    dumpsys battery 2>/dev/null | grep -q 'USB powered: true' && { echo "1"; return 0; }
    dumpsys battery 2>/dev/null | grep -q 'Wireless powered: true' && { echo "1"; return 0; }
    echo "0"
}

# 电池电量 (0-100)
ne_battery_level() {
    dumpsys battery 2>/dev/null | grep -oE 'level: [0-9]+' | grep -oE '[0-9]+' | head -1
}

# 息屏状态: 1=亮屏 0=息屏
ne_screen_on() {
    dumpsys display 2>/dev/null | grep -q 'mScreenState=ON' && { echo "1"; return 0; }
    dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake' && { echo "1"; return 0; }
    echo "0"
}

# 蓝牙是否连接 (A2DP/HFP)
ne_bt_connected() {
    dumpsys bluetooth_manager 2>/dev/null | grep -q 'connected: true' && { echo "1"; return 0; }
    dumpsys bluetooth_manager 2>/dev/null | grep -q 'state:12' && { echo "1"; return 0; }
    echo "0"
}

# GPS 速度估算 (m/s, 需位置权限, 失败返回空)
ne_gps_speed_ms() {
    local out
    out=$(dumpsys location 2>/dev/null | grep -oE 'speed[: =]+[0-9.]+' | head -1 | grep -oE '[0-9.]+' | head -1)
    echo "$out"
}

# 运营商
ne_carrier() {
    local op
    op=$(getprop gsm.operator.alpha 2>/dev/null)
    [ -z "$op" ] && op=$(getprop gsm.sim.operator.alpha 2>/dev/null)
    echo "$op"
}

# 飞行模式状态
ne_airplane_on() {
    settings get global airplane_mode_on 2>/dev/null | grep -q 1 && echo "1" || echo "0"
}

# ---------------- 综合采集 ----------------
ne_collect_state() {
    local topapp cellid rssi rsrp sinr ping_out ping_rtt ping_loss gw_ok wifi_conn
    local charging bat screen_on bt speed carrier airpl
    topapp=$(ne_get_topapp)
    cellid=$(ne_get_cellid)
    rssi=$(ne_get_wifi_rssi)
    rsrp=$(ne_get_cell_rsrp)
    sinr=$(ne_get_cell_sinr)
    ping_out=$(ne_ping_test)
    ping_rtt=$(echo "$ping_out" | cut -d' ' -f1)
    ping_loss=$(echo "$ping_out" | cut -d' ' -f2)
    gw_ok=$(ne_gateway_ok)
    wifi_conn=$(ne_wifi_connected)
    charging=$(ne_charging)
    bat=$(ne_battery_level)
    screen_on=$(ne_screen_on)
    bt=$(ne_bt_connected)
    speed=$(ne_gps_speed_ms)
    carrier=$(ne_carrier)
    airpl=$(ne_airplane_on)

    cat > "$NE_AUTO_STATE" <<EOF
ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
epoch=$(date +%s 2>/dev/null)
weekday=$(date +%w 2>/dev/null)
hhmm=$(date '+%H:%M' 2>/dev/null)
topapp=$topapp
cellid=$cellid
wifi_rssi=$rssi
cell_rsrp=$rsrp
cell_sinr=$sinr
ping_ms=$ping_rtt
packet_loss=$ping_loss
gateway_ok=$gw_ok
wifi_connected=$wifi_conn
charging=$charging
battery=$bat
screen_on=$screen_on
bt_connected=$bt
gps_speed_ms=$speed
carrier=$carrier
airplane=$airpl
EOF

    # 更新基站切换历史 (用于高速移动判定)
    [ -n "$cellid" ] && [ "$cellid" != "" ] && {
        echo "$cellid $(date +%s 2>/dev/null)" >> "$NE_AUTO_DIR/cid_history"
        # 只保留最近窗口内
        local cutoff
        cutoff=$(( $(date +%s 2>/dev/null) - ${MOTION_DETECT_WINDOW:-120} ))
        awk -v c="$cutoff" '$2 > c' "$NE_AUTO_DIR/cid_history" 2>/dev/null > "$NE_AUTO_DIR/cid_history.tmp"
        mv "$NE_AUTO_DIR/cid_history.tmp" "$NE_AUTO_DIR/cid_history" 2>/dev/null
    }
}

ne_state_get() {
    [ -f "$NE_AUTO_STATE" ] || return 1
    grep -E "^$1=" "$NE_AUTO_STATE" | head -1 | cut -d= -f2-
}

# ---------------- 高速移动识别 ----------------
# 返回: highspeed / subway / flight / static
ne_detect_motion() {
    local speed cid_changes airpl
    airpl=$(ne_state_get airplane)

    # 飞行模式开启中 → flight
    if [ "$airpl" = "1" ]; then
        echo "flight"
        return 0
    fi

    # GPS 速度优先 (如果有)
    speed=$(ne_state_get gps_speed_ms)
    if [ -n "$speed" ] && [ "$speed" != "" ]; then
        # m/s → km/h
        local kmh=$(( speed * 36 / 10 ))
        if [ "$kmh" -ge "${MOTION_HIGH_SPEED_KMH:-150}" ] 2>/dev/null; then
            echo "highspeed"
            return 0
        fi
    fi

    # 基站切换频率 (无 GPS 时的兜底)
    if [ -f "$NE_AUTO_DIR/cid_history" ]; then
        cid_changes=$(awk '{print $1}' "$NE_AUTO_DIR/cid_history" 2>/dev/null | sort -u | wc -l)
        if [ "$cid_changes" -ge "${MOTION_CID_CHANGE_THRESHOLD:-3}" ] 2>/dev/null; then
            # 区分高铁/地铁: 地铁通常 WiFi 已断, 信号频繁跳; 高铁速度更快
            local wifi_conn
            wifi_conn=$(ne_state_get wifi_connected)
            if [ "$wifi_conn" = "0" ] && [ "$cid_changes" -ge 5 ]; then
                echo "subway"
                return 0
            fi
            echo "highspeed"
            return 0
        fi
    fi

    echo "static"
}

# ---------------- 当前模式 ----------------
ne_current_mode() {
    [ -f "$NE_AUTO_CURRENT" ] && cat "$NE_AUTO_CURRENT" || echo "none"
}

ne_last_switch() {
    [ -f "$NE_AUTO_LASTSWITCH" ] && cat "$NE_AUTO_LASTSWITCH" || echo "0"
}
