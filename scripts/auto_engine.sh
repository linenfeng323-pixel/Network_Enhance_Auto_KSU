#!/system/bin/sh
# ======================================================================
# auto_engine.sh — Network Enhance Auto (KSU) 主引擎 v2.0
# 重写: 修复配置加载/规则匹配/daemon/JSON 所有 bug
# 新增: 一键网络自动优化 (autoopt)
# ======================================================================
. "$(dirname "$0")/auto_common.sh"

# 在 source common 后立即加载配置 (修复 v1 首次循环变量未加载的 bug)
ne_load_all_conf

# ======================================================================
# 主决策: 返回应切换到的模式名
# ======================================================================
ne_decide() {
    [ -f "$NE_AUTO_RULES" ] || { echo "normal"; return 0; }

    local cur_motion
    cur_motion=$(ne_detect_motion)

    local line type mode args
    while IFS= read -r line; do
        # 跳过空行/注释/配置变量
        case "$line" in ''|\#*|AUTO_*|MOTION_*) continue ;; esac
        type=$(echo "$line" | awk '{print $1}')
        case "$type" in
            app)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                local topapp; topapp=$(ne_state_get topapp)
                [ -n "$topapp" ] && [ -n "$args" ] && {
                    echo ",$args," | grep -q ",$topapp," && { echo "$mode"; return 0; }
                }
                ;;
            motion)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                [ "$args" = "$cur_motion" ] && { echo "$mode"; return 0; }
                ;;
            charging)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                local cur_chg; cur_chg=$(ne_state_get charging)
                { [ "$args" = "true" ] && [ "$cur_chg" = "1" ]; } && { echo "$mode"; return 0; }
                { [ "$args" = "false" ] && [ "$cur_chg" = "0" ]; } && { echo "$mode"; return 0; }
                ;;
            screen)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                local cur_scr; cur_scr=$(ne_state_get screen_on)
                { [ "$args" = "on" ] && [ "$cur_scr" = "1" ]; } && { echo "$mode"; return 0; }
                { [ "$args" = "off" ] && [ "$cur_scr" = "0" ]; } && { echo "$mode"; return 0; }
                ;;
            cellloc)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                # 未记录的位置跳过
                case "$args" in __*__) continue ;; esac
                [ -z "$args" ] && continue
                local cur_cid; cur_cid=$(ne_state_get cellid)
                [ -n "$cur_cid" ] && echo ",$args," | grep -q ",$cur_cid," && { echo "$mode"; return 0; }
                ;;
            time)
                mode=$(echo "$line" | awk '{print $2}')
                local range days
                range=$(echo "$line" | awk '{print $3}')
                days=$(echo "$line" | awk '{print $4}')
                ne_match_time "$range" "${days:-*}" && { echo "$mode"; return 0; }
                ;;
            signal)
                mode=$(echo "$line" | awk '{print $2}')
                local cond; cond=$(echo "$line" | awk '{$1="";$2="";print}' | sed 's/^  //')
                ne_match_signal "$cond" && { echo "$mode"; return 0; }
                ;;
            default)
                echo "$(echo "$line" | awk '{print $2}')"; return 0
                ;;
        esac
    done < "$NE_AUTO_RULES"
    echo "normal"
}

# ======================================================================
# 自愈
# ======================================================================
ne_heal() {
    [ "$AUTO_HEAL_ENABLE" = "true" ] || return 0
    local wifi_conn gw_ok ping_loss
    wifi_conn=$(ne_state_get wifi_connected)
    gw_ok=$(ne_state_get gateway_ok)
    ping_loss=$(ne_state_get packet_loss)

    # WiFi 假连接: 已连但网关不通
    if [ "$wifi_conn" = "1" ] && [ "$gw_ok" = "0" ]; then
        ne_log "自愈: WiFi 假连接, 重连"
        cmd wifi disable 2>/dev/null; sleep 2; cmd wifi enable 2>/dev/null
        ne_event "HEAL wifi_fake -> reconnect"
        return 0
    fi
    # 高丢包切 DNS
    if [ -n "$ping_loss" ] && ne_num_cmp "$ping_loss" ">" 50; then
        ne_log "自愈: 丢包 ${ping_loss}%, 切 DNS"
        settings put global dns1 119.29.29.29 2>/dev/null
        settings put global dns2 223.5.5.5 2>/dev/null
        ne_event "HEAL high_loss -> switch_dns"
        return 0
    fi
    return 0
}

# ======================================================================
# 应用模式
# ======================================================================
ne_apply() {
    local mode="$1"
    ne_log "应用场景: $mode (运动: $(ne_detect_motion))"
    if [ -f "$NE_AUTO_APPLY" ]; then
        sh "$NE_AUTO_APPLY" "$mode" 2>>"$NE_AUTO_LOG"
    else
        ne_log "错误: auto_apply.sh 不存在: $NE_AUTO_APPLY"
        return 1
    fi
    ne_event "SWITCH -> $mode"
    ne_notify "网络增强" "已切换: $mode"
    return 0
}

# ======================================================================
# 单次评估
# ======================================================================
ne_eval_once() {
    [ "$AUTO_ENGINE_ENABLE" = "true" ] || { ne_log "引擎已禁用, 跳过"; return 0; }
    ne_collect_state
    ne_log "采集: app=$(ne_state_get topapp) motion=$(ne_detect_motion) chg=$(ne_state_get charging) scr=$(ne_state_get screen_on) rssi=$(ne_state_get wifi_rssi) rsrp=$(ne_state_get cell_rsrp) net=$(ne_state_get active_network)"

    ne_heal

    local target cur now last_switch elapsed pending
    target=$(ne_decide)
    cur=$(ne_current_mode)
    if [ "$target" = "$cur" ]; then
        : > "$NE_AUTO_PENDING" 2>/dev/null
        return 0
    fi

    now=$(date +%s 2>/dev/null || echo 0)
    last_switch=$(ne_last_switch)
    elapsed=$((now - last_switch))
    if [ "$elapsed" -lt "${AUTO_MIN_SWITCH_SEC:-60}" ]; then
        ne_log "防抖: ${elapsed}s < ${AUTO_MIN_SWITCH_SEC}s, 目标=$target 跳过"
        return 0
    fi

    pending=$(cat "$NE_AUTO_PENDING" 2>/dev/null || echo 0)
    pending=$((pending + 1))
    echo "$pending" > "$NE_AUTO_PENDING" 2>/dev/null
    ne_log "目标=$target 命中 $pending/${AUTO_CONFIRM_COUNT:-2}"
    if [ "$pending" -ge "${AUTO_CONFIRM_COUNT:-2}" ]; then
        ne_apply "$target"
        : > "$NE_AUTO_PENDING" 2>/dev/null
    fi
}

# ======================================================================
# 主循环
# ======================================================================
ne_main_loop() {
    ne_load_all_conf
    ne_log "===== 引擎启动 v2.0 (interval=${AUTO_INTERVAL_SEC}s, moddir=$MODDIR) ====="
    echo $$ > "$NE_AUTO_PID"
    trap 'ne_log "引擎停止"; rm -f "$NE_AUTO_PID"; exit 0' INT TERM HUP
    # 首次立即评估
    ne_eval_once
    while :; do
        sleep "${AUTO_INTERVAL_SEC:-20}" 2>/dev/null || sleep 20
        ne_eval_once
    done
}

# ======================================================================
# 一键网络自动优化 (根据当前网络实况自动选最优设置)
# 这是用户要的"根据网络自动一键设置"
# ======================================================================
ne_auto_optimize() {
    echo "=========================================="
    echo " Network Enhance Auto — 一键网络自动优化"
    echo "=========================================="
    echo ""
    echo "[1/5] 采集当前网络状态..."
    ne_collect_state

    local rssi rsrp sinr ping_rtt ping_loss wifi_conn carrier actnet motion
    rssi=$(ne_state_get wifi_rssi)
    rsrp=$(ne_state_get cell_rsrp)
    sinr=$(ne_state_get cell_sinr)
    ping_rtt=$(ne_state_get ping_ms)
    ping_loss=$(ne_state_get packet_loss)
    wifi_conn=$(ne_state_get wifi_connected)
    carrier=$(ne_state_get carrier)
    actnet=$(ne_state_get active_network)
    motion=$(ne_detect_motion)

    echo "  WiFi RSSI : ${rssi:-?} dBm"
    echo "  蜂窝 RSRP : ${rsrp:-?} dBm"
    echo "  蜂窝 SINR : ${sinr:-?} dB"
    echo "  延迟      : ${ping_rtt:-?} ms"
    echo "  丢包率    : ${ping_loss:-?}%"
    echo "  WiFi      : $([ "$wifi_conn" = "1" ] && echo 已连接 || echo 未连接)"
    echo "  运营商    : ${carrier:-?}"
    echo "  活动网络  : ${actnet:-?}"
    echo "  运动状态  : ${motion:-?}"
    echo ""

    echo "[2/5] 分析最优策略..."
    local target="normal"
    # 决策树: 优先级 motion > signal > app > default
    case "$motion" in
        highspeed) target="highspeed" ;;
        subway)    target="subway" ;;
        flight)    target="flight" ;;
        *)
            # 信号判定
            if [ -n "$rssi" ] && ne_num_cmp "$rssi" "<" -80 && ne_num_cmp "$ping_rtt" ">" 150; then
                target="weaknet"
            elif [ -n "$rsrp" ] && ne_num_cmp "$rsrp" "<" -110; then
                target="weaknet"
            elif [ -n "$ping_loss" ] && ne_num_cmp "$ping_loss" ">" 30; then
                target="weaknet"
            else
                target="normal"
            fi
            ;;
    esac
    echo "  → 推荐场景: $target"
    echo ""

    echo "[3/5] 测试 DNS 延迟, 选最快的..."
    local best_dns best_rtt cur_rtt
    best_dns="223.5.5.5"
    best_rtt=9999
    for dns in 223.5.5.5 119.29.29.29 114.114.114.114 180.76.76.76; do
        cur_rtt=$(ping -c 2 -W 1 "$dns" 2>/dev/null | grep -oE '=[ ]*[0-9.]+/[0-9.]+/[0-9.]+/[0-9.]+' | head -1 | cut -d/ -f2)
        [ -z "$cur_rtt" ] && cur_rtt=9999
        echo "  $dns : ${cur_rtt} ms"
        if ne_num_cmp "$cur_rtt" "<" "$best_rtt"; then
            best_rtt=$cur_rtt
            best_dns=$dns
        fi
    done
    echo "  → 最快 DNS: $best_dns (${best_rtt} ms)"
    echo ""

    echo "[4/5] 应用优化..."
    # 应用场景策略
    ne_apply "$target"
    # 覆盖 DNS 为最快的
    settings put global dns1 "$best_dns" 2>/dev/null
    case "$best_dns" in
        223.5.5.5)   settings put global dns2 119.29.29.29 ;;
        119.29.29.29) settings put global dns2 223.5.5.5 ;;
        *)           settings put global dns2 223.5.5.5 ;;
    esac
    echo "  [OK] 场景 $target 已应用"
    echo "  [OK] DNS 已切到 $best_dns"
    echo ""

    echo "[5/5] 完成"
    echo "=========================================="
    echo " 当前模式: $(ne_current_mode)"
    echo " 如需保持, 启动引擎: sh auto_engine.sh start"
    echo "=========================================="
}

# ======================================================================
# 状态 JSON (WebUI 用, 严格转义)
# ======================================================================
ne_status_json() {
    ne_collect_state
    local mode target motion
    mode=$(ne_current_mode)
    target=$(ne_decide)
    motion=$(ne_detect_motion)
    local running="false"
    [ -f "$NE_AUTO_PID" ] && kill -0 "$(cat "$NE_AUTO_PID" 2>/dev/null)" 2>/dev/null && running="true"

    # 状态文件每行 key=value, value 做 JSON 转义
    local kv_json
    kv_json=$(awk -F= '{
        k=$1; sub(/^[^=]*=/,"",$0); v=$0
        gsub(/\\/,"\\\\",v)
        gsub(/"/,"\\\"",v)
        printf "  \"%s\": \"%s\",\n", k, v
    }' "$NE_AUTO_STATE" 2>/dev/null | sed '$ s/,$//')

    cat <<EOF
{
  "mode": "$mode",
  "target": "$target",
  "motion": "$motion",
  "running": $running,
$kv_json
}
EOF
}

# ======================================================================
# 命令分发
# ======================================================================
case "${1:-}" in
    start)
        [ -f "$NE_AUTO_PID" ] && kill -0 "$(cat "$NE_AUTO_PID" 2>/dev/null)" 2>/dev/null && { echo "已运行 PID $(cat "$NE_AUTO_PID")"; exit 0; }
        ne_load_all_conf
        [ "$AUTO_ENGINE_ENABLE" != "true" ] && { echo "引擎已禁用 (config.sh AUTO_ENGINE_ENABLE=false)"; exit 0; }
        # 用 setsid 完全脱离终端, 避免 nohup 在某些 sh 下失效
        setsid sh "$0" _daemon >>"$NE_AUTO_LOG" 2>&1 < /dev/null &
        sleep 1
        [ -f "$NE_AUTO_PID" ] && { echo "已启动 PID $(cat "$NE_AUTO_PID")"; ne_notify "网络增强" "引擎已启动"; }
        ;;
    _daemon) ne_main_loop ;;
    stop)
        if [ -f "$NE_AUTO_PID" ]; then
            kill "$(cat "$NE_AUTO_PID")" 2>/dev/null
            rm -f "$NE_AUTO_PID"
            echo "已停止"
            ne_notify "网络增强" "引擎已停止"
        else
            echo "未运行"
        fi
        ;;
    restart)
        sh "$0" stop 2>/dev/null
        sleep 1
        sh "$0" start
        ;;
    status)
        echo "===== NE Auto v2.0 状态 ====="
        if [ -f "$NE_AUTO_PID" ] && kill -0 "$(cat "$NE_AUTO_PID" 2>/dev/null)" 2>/dev/null; then
            echo "引擎: 运行中 PID $(cat "$NE_AUTO_PID")"
        else
            echo "引擎: 未运行"
        fi
        echo "当前模式: $(ne_current_mode)"
        echo "运动状态: $(ne_detect_motion)"
        echo ""
        echo "[网络状态]"
        cat "$NE_AUTO_STATE" 2>/dev/null
        echo ""
        echo "[最近事件]"
        tail -10 "$NE_AUTO_EVENT" 2>/dev/null
        ;;
    once)
        ne_load_all_conf
        ne_collect_state
        echo "目标: $(ne_decide)  当前: $(ne_current_mode)  运动: $(ne_detect_motion)"
        echo ""
        cat "$NE_AUTO_STATE" 2>/dev/null
        ;;
    record)
        [ -z "$2" ] && { echo "用法: record home|work"; exit 1; }
        cid=$(ne_get_cellid)
        [ -z "$cid" ] && { echo "无法读取 CID"; exit 1; }
        placeholder="__$(echo "$2" | tr '[:lower:]' '[:upper:]')_CIDS__"
        if grep -q "$placeholder" "$NE_AUTO_RULES" 2>/dev/null; then
            # 用 # 做分隔符避免和数字冲突
            sed -i "s#$placeholder#$cid#g" "$NE_AUTO_RULES"
            echo "已记录 $2 位置 (CID=$cid)"
        else
            # 追加一条
            echo "cellloc  powersave  $cid" >> "$NE_AUTO_RULES"
            echo "已记录 $2 位置 (CID=$cid), 追加到规则末尾"
        fi
        ;;
    apply)
        [ -z "$2" ] && { echo "用法: apply <mode>"; exit 1; }
        ne_apply "$2"
        echo "已应用: $2"
        ;;
    autoopt|optimize|oneclick)
        ne_auto_optimize
        ;;
    speedtest)
        echo "=== 延迟测试 ==="
        for t in 223.5.5.5 119.29.29.29 8.8.8.8; do
            out=$(ping -c 4 -W 2 "$t" 2>/dev/null)
            avg=$(echo "$out" | grep -oE '=[ ]*[0-9.]+/[0-9.]+/[0-9.]+/[0-9.]+' | head -1 | cut -d/ -f2)
            loss=$(echo "$out" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+' | head -1)
            echo "  $t: 延迟 ${avg:-?}ms  丢包 ${loss:-?}%"
        done
        echo ""
        echo "=== 下载测试 ==="
        for url in "https://speed.cloudflare.com/__down?bytes=2097152" "http://speedtest.tele2.net/1MB.zip"; do
            t1=$(date +%s)
            bytes=$(curl -s -m 10 -o /dev/null -w '%{size_download}' "$url" 2>/dev/null)
            t2=$(date +%s)
            dur=$((t2-t1)); [ "$dur" -le 0 ] && dur=1
            mbps=$((bytes*8/1024/1024/dur))
            echo "  $(echo $url | cut -d/ -f3): ${mbps} Mbps (${bytes}B / ${dur}s)"
        done
        ;;
    log)
        tail -50 "$NE_AUTO_LOG" 2>/dev/null
        ;;
    events)
        tail -30 "$NE_AUTO_EVENT" 2>/dev/null
        ;;
    json) ne_status_json ;;
    motion)
        ne_load_all_conf
        ne_collect_state
        ne_detect_motion
        ;;
    *)
        cat <<EOF
Network Enhance Auto (KSU) v2.0

用法:
  sh auto_engine.sh start          启动自动引擎
  sh auto_engine.sh stop           停止
  sh auto_engine.sh restart        重启
  sh auto_engine.sh status         查看状态
  sh auto_engine.sh autoopt        ★ 一键网络自动优化 (根据网络实况自动设置)
  sh auto_engine.sh once           单次评估 (不切换, 只看推荐)
  sh auto_engine.sh apply <mode>   手动应用场景 (highspeed/subway/flight/game/voip/video/weaknet/powersave/normal)
  sh auto_engine.sh record home|work   记录家/公司位置
  sh auto_engine.sh speedtest      测速
  sh auto_engine.sh json           输出 JSON (WebUI 用)
  sh auto_engine.sh motion         查看当前运动状态
  sh auto_engine.sh log            查看引擎日志
  sh auto_engine.sh events         查看事件日志
EOF
        ;;
esac
exit 0
