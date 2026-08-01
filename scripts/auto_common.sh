#!/system/bin/sh
# ======================================================================
# auto_common.sh — Network Enhance Auto 公共函数库 (KSU root 版) v2.0
# 重写: 修复路径/采集/JSON 等所有 bug
# ======================================================================

# ---------------- 路径与全局 ----------------
NE_AUTO_DIR="/data/local/tmp/ne_auto"
NE_AUTO_STATE="$NE_AUTO_DIR/state"
NE_AUTO_EVENT="$NE_AUTO_DIR/events.log"
NE_AUTO_LOG="$NE_AUTO_DIR/engine.log"
NE_AUTO_PID="$NE_AUTO_DIR/engine.pid"
NE_AUTO_CURRENT="$NE_AUTO_DIR/current_mode"
NE_AUTO_LASTSWITCH="$NE_AUTO_DIR/last_switch"
NE_AUTO_PENDING="$NE_AUTO_DIR/pending"
NE_AUTO_CID_HIST="$NE_AUTO_DIR/cid_history"

# 推算 MODDIR (兼容 service.sh / 手动 / daemon 多种调用方式)
_ne_find_moddir() {
    # 1. 环境变量
    [ -n "${MODDIR:-}" ] && [ -d "$MODDIR/scripts" ] && { echo "$MODDIR"; return 0; }
    # 2. 脚本所在目录的上一级 (scripts/ 的父)
    local d
    d=$(dirname "${0:-.}" 2>/dev/null)
    [ -f "$d/auto_common.sh" ] && d=$(dirname "$d")
    [ -f "$d/scripts/auto_common.sh" ] && { echo "$d"; return 0; }
    # 3. 已知 KSU 模块路径
    for _p in /data/adb/modules/network_enhance_auto /data/adb/modules/network_enhance; do
        [ -f "$_p/scripts/auto_common.sh" ] && { echo "$_p"; return 0; }
    done
    return 1
}
MODDIR="${MODDIR:-$(_ne_find_moddir)}"
NE_SCRIPTS="$MODDIR/scripts"
NE_AUTO_RULES="$NE_SCRIPTS/auto_rules.conf"
NE_AUTO_APPLY="$NE_SCRIPTS/auto_apply.sh"

mkdir -p "$NE_AUTO_DIR" 2>/dev/null

# ---------------- 默认配置 (config.sh / rules.conf 未加载时用) ----------------
AUTO_ENGINE_ENABLE=true
AUTO_INTERVAL_SEC=20
AUTO_MIN_SWITCH_SEC=60
AUTO_CONFIRM_COUNT=2
AUTO_HEAL_ENABLE=true
MOTION_DETECT_WINDOW=120
MOTION_CID_CHANGE_THRESHOLD=3
MOTION_HIGH_SPEED_KMH=150
AUTO_REPORT_TIME="21:00"

# ---------------- 日志 ----------------
ne_log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')" "$1" >> "$NE_AUTO_LOG" 2>/dev/null
}
ne_event() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')" "$1" >> "$NE_AUTO_EVENT" 2>/dev/null
}
ne_notify() {
    cmd notification post -t "${1:-Network Enhance}" --text "${2:-}" ne_auto 2>/dev/null
    return 0
}

# ---------------- 配置加载 ----------------
# 从 config.sh 加载 (优先)
ne_load_config_sh() {
    [ -f "$MODDIR/config.sh" ] || return 0
    . "$MODDIR/config.sh" 2>/dev/null
}
# 从 auto_rules.conf 加载 AUTO_* / MOTION_* 变量
ne_load_rules_conf() {
    [ -f "$NE_AUTO_RULES" ] || return 1
    local line key val
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        case "$line" in
            AUTO_*|MOTION_*)
                key=${line%%=*}
                val=${line#*=}
                # 去引号和首尾空格
                val=${val#\"}; val=${val%\"}
                val=${val#' '}; val=${val%' '}
                eval "$key=\$val"
                ;;
        esac
    done < "$NE_AUTO_RULES"
    return 0
}
ne_load_all_conf() {
    ne_load_config_sh
    ne_load_rules_conf
}

# ---------------- 状态采集 (每个都返回纯值, 失败返回空) ----------------

# 前台 App 包名
ne_get_topapp() {
    local pkg
    # Android 10+ 推荐
    pkg=$(cmd activity get-top-resumedActivity 2>/dev/null | awk 'NR==1{print $NF}' | cut -d/ -f1)
    [ -n "$pkg" ] && { echo "$pkg"; return 0; }
    # 兜底: dumpsys
    pkg=$(dumpsys activity activities 2>/dev/null | grep -E 'topResumedActivity|mResumedActivity' | head -1 | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1 | cut -d/ -f1)
    [ -n "$pkg" ] && { echo "$pkg"; return 0; }
    pkg=$(dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -1 | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1 | cut -d/ -f1)
    echo "$pkg"
}

# 主服务小区 CID (数字)
ne_get_cellid() {
    local cid
    # 优先 NR/LTE 主服务小区
    cid=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'ci=[0-9]+' | head -1 | cut -d= -f2)
    [ -n "$cid" ] && { echo "$cid"; return 0; }
    cid=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'mCi=[0-9]+' | head -1 | cut -d= -f2)
    [ -n "$cid" ] && { echo "$cid"; return 0; }
    # service_state 兜底
    cid=$(dumpsys telephony.registry 2>/dev/null | grep -oE '[cC]id[ :?=]+[0-9]+' | head -1 | grep -oE '[0-9]+')
    echo "$cid"
}

# 蜂窝 RSRP (负值 dBm)
ne_get_cell_rsrp() {
    local v
    v=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'ssRsrp[ :?=]+-?[0-9]+' | head -1 | grep -oE '-?[0-9]+')
    [ -n "$v" ] && { echo "$v"; return 0; }
    v=$(dumpsys telephony.registry 2>/dev/null | grep -oE '[Rr]srp[ :?=]+-?[0-9]+' | head -1 | grep -oE '-?[0-9]+')
    echo "$v"
}

# 蜂窝 SINR
ne_get_cell_sinr() {
    local v
    v=$(dumpsys telephony.registry 2>/dev/null | grep -oE 'ssSinr[ :?=]+-?[0-9]+' | head -1 | grep -oE '-?[0-9]+')
    [ -n "$v" ] && { echo "$v"; return 0; }
    v=$(dumpsys telephony.registry 2>/dev/null | grep -oE '[Ss]inr[ :?=]+-?[0-9]+' | head -1 | grep -oE '-?[0-9]+')
    echo "$v"
}

# WiFi RSSI (负值 dBm)
ne_get_wifi_rssi() {
    local v
    v=$(cmd wifi status 2>/dev/null | grep -oE 'RSSI[ :?=]+-?[0-9]+' | head -1 | grep -oE '-?[0-9]+')
    [ -n "$v" ] && { echo "$v"; return 0; }
    v=$(dumpsys wifi 2>/dev/null | grep -oE 'rssi[ :?=]+-?[0-9]+' | head -1 | grep -oE '-?[0-9]+')
    echo "$v"
}

# Ping: 输出 "rtt loss" (rtt=avg ms, loss=百分比数字, 失败 "0 100")
ne_ping_test() {
    local target="${1:-223.5.5.5}" out rtt loss
    out=$(ping -c 2 -W 1 "$target" 2>/dev/null)
    if [ -z "$out" ]; then echo "0 100"; return 0; fi
    # 统计行: "2 packets transmitted, 2 received, 0% packet loss"
    loss=$(echo "$out" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+' | head -1)
    [ -z "$loss" ] && loss=100
    # rtt 行: "rtt min/avg/max/mdev = 5.123/8.456/12.789/3.012 ms"
    rtt=$(echo "$out" | grep -oE '=[ ]*[0-9.]+/[0-9.]+/[0-9.]+/[0-9.]+' | head -1 | cut -d/ -f2)
    [ -z "$rtt" ] && rtt=0
    echo "$rtt $loss"
}

# 网关连通 1/0
ne_gateway_ok() {
    local gw
    gw=$(ip route 2>/dev/null | grep -oE 'default via [0-9.]+' | head -1 | grep -oE '[0-9.]+')
    [ -z "$gw" ] && { echo "0"; return 0; }
    ping -c 1 -W 1 "$gw" >/dev/null 2>&1 && echo "1" || echo "0"
}

# WiFi 已连接 1/0
ne_wifi_connected() {
    cmd wifi status 2>/dev/null | grep -qE 'Wi-Fi is connected|state: CONNECTED' && echo "1" || echo "0"
}

# 充电中 1/0
ne_charging() {
    dumpsys battery 2>/dev/null | grep -qE 'powered: true' && echo "1" || echo "0"
}

# 电池电量 0-100
ne_battery_level() {
    dumpsys battery 2>/dev/null | grep -oE 'level: [0-9]+' | grep -oE '[0-9]+' | head -1
}

# 亮屏 1/0
ne_screen_on() {
    dumpsys display 2>/dev/null | grep -qE 'mScreenState=ON|state=ON' && { echo "1"; return 0; }
    dumpsys power 2>/dev/null | grep -qE 'mWakefulness=Awake|Display Power' && echo "1" || echo "0"
}

# 蓝牙已连接 1/0
ne_bt_connected() {
    dumpsys bluetooth_manager 2>/dev/null | grep -qE 'connected: true|state:12' && echo "1" || echo "0"
}

# GPS 速度 m/s (空=无)
ne_gps_speed_ms() {
    dumpsys location 2>/dev/null | grep -oE 'speed[ :?=]+[0-9.]+' | head -1 | grep -oE '[0-9.]+' | head -1
}

# 运营商名
ne_carrier() {
    getprop gsm.operator.alpha 2>/dev/null
}

# 飞行模式 1/0
ne_airplane_on() {
    [ "$(settings get global airplane_mode_on 2>/dev/null | tr -d ' \r\n')" = "1" ] && echo "1" || echo "0"
}

# 网络制式 (preferred_network_mode 当前值)
ne_get_netmode() {
    settings get global preferred_network_mode 2>/dev/null | tr -d ' \r\n'
}

# 当前默认网络类型 wifi / cell / none
ne_get_active_network() {
    local n
    n=$(dumpsys connectivity 2>/dev/null | grep -oE 'Active default network: [a-zA-Z]+' | head -1 | grep -oE '[a-zA-Z]+$')
    [ -z "$n" ] && n=$(cmd connectivity get-network-id 2>/dev/null)
    if ne_wifi_connected | grep -q 1; then echo "wifi"; return 0; fi
    if [ -n "$(ne_get_cellid)" ]; then echo "cell"; return 0; fi
    echo "none"
}

# ---------------- 综合采集 (写状态文件) ----------------
ne_collect_state() {
    local topapp cellid rssi rsrp sinr ping_out ping_rtt ping_loss gw_ok wifi_conn
    local charging bat screen_on bt speed carrier airpl netmode actnet
    topapp=$(ne_get_topapp)
    cellid=$(ne_get_cellid)
    rssi=$(ne_get_wifi_rssi)
    rsrp=$(ne_get_cell_rsrp)
    sinr=$(ne_get_cell_sinr)
    ping_out=$(ne_ping_test)
    ping_rtt=$(echo "$ping_out" | awk '{print $1}')
    ping_loss=$(echo "$ping_out" | awk '{print $2}')
    gw_ok=$(ne_gateway_ok)
    wifi_conn=$(ne_wifi_connected)
    charging=$(ne_charging)
    bat=$(ne_battery_level)
    screen_on=$(ne_screen_on)
    bt=$(ne_bt_connected)
    speed=$(ne_gps_speed_ms)
    carrier=$(ne_carrier)
    airpl=$(ne_airplane_on)
    netmode=$(ne_get_netmode)
    actnet=$(ne_get_active_network)

    # 安全写状态文件 (值里的特殊字符做转义)
    {
        echo "ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
        echo "epoch=$(date +%s 2>/dev/null)"
        echo "weekday=$(date +%w 2>/dev/null)"
        echo "hhmm=$(date '+%H:%M' 2>/dev/null)"
        echo "topapp=$topapp"
        echo "cellid=$cellid"
        echo "wifi_rssi=$rssi"
        echo "cell_rsrp=$rsrp"
        echo "cell_sinr=$sinr"
        echo "ping_ms=$ping_rtt"
        echo "packet_loss=$ping_loss"
        echo "gateway_ok=$gw_ok"
        echo "wifi_connected=$wifi_conn"
        echo "charging=$charging"
        echo "battery=$bat"
        echo "screen_on=$screen_on"
        echo "bt_connected=$bt"
        echo "gps_speed_ms=$speed"
        echo "carrier=$carrier"
        echo "airplane=$airpl"
        echo "netmode=$netmode"
        echo "active_network=$actnet"
    } > "$NE_AUTO_STATE.tmp"
    mv "$NE_AUTO_STATE.tmp" "$NE_AUTO_STATE" 2>/dev/null

    # 更新基站切换历史 (只保留窗口内)
    if [ -n "$cellid" ]; then
        local now cutoff
        now=$(date +%s 2>/dev/null || echo 0)
        echo "$cellid $now" >> "$NE_AUTO_CID_HIST"
        cutoff=$((now - ${MOTION_DETECT_WINDOW:-120}))
        awk -v c="$cutoff" '$2 > c' "$NE_AUTO_CID_HIST" 2>/dev/null > "$NE_AUTO_CID_HIST.tmp"
        mv "$NE_AUTO_CID_HIST.tmp" "$NE_AUTO_CID_HIST" 2>/dev/null
    fi
}

# 读状态字段
ne_state_get() {
    [ -f "$NE_AUTO_STATE" ] || return 1
    # 精确匹配 key= (避免 wifi_ 匹配到 wifi_rssi)
    awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$NE_AUTO_STATE" 2>/dev/null
}

# ---------------- 运动识别 ----------------
# 返回: highspeed / subway / flight / static
ne_detect_motion() {
    local airpl speed kmh cid_changes wifi_conn
    airpl=$(ne_state_get airplane)
    [ "$airpl" = "1" ] && { echo "flight"; return 0; }

    # GPS 速度
    speed=$(ne_state_get gps_speed_ms)
    if [ -n "$speed" ]; then
        kmh=$(( speed * 36 / 10 ))
        [ "$kmh" -ge "${MOTION_HIGH_SPEED_KMH:-150}" ] 2>/dev/null && { echo "highspeed"; return 0; }
    fi

    # 基站切换频率
    if [ -f "$NE_AUTO_CID_HIST" ]; then
        cid_changes=$(awk '{print $1}' "$NE_AUTO_CID_HIST" 2>/dev/null | sort -u | wc -l)
        if [ "$cid_changes" -ge "${MOTION_CID_CHANGE_THRESHOLD:-3}" ] 2>/dev/null; then
            wifi_conn=$(ne_state_get wifi_connected)
            if [ "$wifi_conn" = "0" ] && [ "$cid_changes" -ge 5 ]; then
                echo "subway"; return 0
            fi
            echo "highspeed"; return 0
        fi
    fi
    echo "static"
}

# ---------------- 模式状态 ----------------
ne_current_mode() {
    [ -f "$NE_AUTO_CURRENT" ] && cat "$NE_AUTO_CURRENT" 2>/dev/null || echo "none"
}
ne_last_switch() {
    [ -f "$NE_AUTO_LASTSWITCH" ] && cat "$NE_AUTO_LASTSWITCH" 2>/dev/null || echo "0"
}

# ---------------- 工具: 数值比较 ----------------
# ne_num_cmp "actual" "op" "val" → return 0=成立 1=不成立
ne_num_cmp() {
    local a="$1" op="$2" v="$3"
    # 净化成纯数字 (允许负号小数点)
    a=$(printf '%s' "$a" | tr -dc '0-9.-')
    v=$(printf '%s' "$v" | tr -dc '0-9.-')
    [ -z "$a" ] && a=0
    [ -z "$v" ] && v=0
    # 用 awk 比较 (支持小数)
    awk -v a="$a" -v v="$v" -v op="$op" 'BEGIN{
        r=0
        if(op=="<")  r=(a<v)?1:0
        else if(op=="<=") r=(a<=v)?1:0
        else if(op==">")  r=(a>v)?1:0
        else if(op==">=") r=(a>=v)?1:0
        else if(op=="==" || op=="=") r=(a==v)?1:0
        exit (r?0:1)
    }'
}

# ---------------- 规则匹配 ----------------
# 时间段匹配: ne_match_time "23:00-07:00" "1,2,3,4,5"
# 用 awk 比较, 避免 POSIX [ ] 不支持字符串 < 的 bug
ne_match_time() {
    local range="$1" days="${2:-*}" now_hhmm now_wday start end
    now_hhmm=$(date '+%H:%M' 2>/dev/null)
    now_wday=$(date +%w 2>/dev/null)
    if [ "$days" != "*" ]; then
        echo "$days" | grep -qE "(^|,)$now_wday(,|$)" || return 1
    fi
    start=${range%%-*}
    end=${range##*-}
    # awk 返回 1=匹配 0=不匹配, exit 控制返回码
    awk -v s="$start" -v e="$end" -v n="$now_hhmm" 'BEGIN{
        if(s < e){
            exit ((n>=s && n<e)?0:1)
        } else {
            exit ((n>=s || n<e)?0:1)
        }
    }'
}

# 信号条件匹配: ne_match_signal "wifi_rssi < -80 && ping_ms > 150"
ne_match_signal() {
    local cond="$1" oldIFS part field op val actual
    oldIFS="$IFS"; IFS='&'; set -- $cond; IFS="$oldIFS"
    for part in "$@"; do
        part=$(echo "$part" | sed 's/^[ ]*//;s/[ ]*$//')
        [ -z "$part" ] && continue
        field=$(echo "$part" | awk '{print $1}')
        op=$(echo "$part" | awk '{print $2}')
        val=$(echo "$part" | awk '{print $3}')
        actual=$(ne_state_get "$field")
        ne_num_cmp "$actual" "$op" "$val" || { return 1; }
    done
    return 0
}
