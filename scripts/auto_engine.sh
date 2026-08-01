#!/system/bin/sh
# ======================================================================
# auto_engine.sh — Network Enhance Auto (KSU) 主引擎
# 多维感知: App/运动(高铁地铁飞机)/充电/息屏/基站/时间/信号
# ======================================================================
MODDIR="${MODDIR:-$(dirname "$(dirname "$0" 2>/dev/null)" 2>/dev/null)}"
NE_SCRIPTS="${MODDIR}/scripts"
[ -d "$NE_SCRIPTS" ] || NE_SCRIPTS="$(dirname "$0" 2>/dev/null)"
. "$NE_SCRIPTS/auto_common.sh"

# 加载配置
ne_load_conf() {
    [ -f "$NE_AUTO_RULES" ] || { ne_log "规则文件缺失: $NE_AUTO_RULES"; return 1; }
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        case "$line" in
            AUTO_*|MOTION_*)
                key=$(echo "$line" | cut -d= -f1 | tr -d ' ')
                val=$(echo "$line" | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e 's/^ *//' -e 's/ *$//')
                eval "$key=\$val"
                ;;
        esac
    done < "$NE_AUTO_RULES"
    return 0
}

# 规则匹配
ne_match_time() {
    local range="$1" days="$2" now_hhmm now_wday start end
    now_hhmm=$(date '+%H:%M' 2>/dev/null)
    now_wday=$(date +%w 2>/dev/null)
    [ "$days" != "*" ] && { echo "$days" | grep -qE "(^|,)$now_wday(,|$)" || return 1; }
    start=$(echo "$range" | cut -d- -f1)
    end=$(echo "$range" | cut -d- -f2)
    if [ "$start" \< "$end" ]; then
        [ "$now_hhmm" \>= "$start" ] && [ "$now_hhmm" \< "$end" ] && return 0
        return 1
    else
        [ "$now_hhmm" \>= "$start" ] || [ "$now_hhmm" \< "$end" ] && return 0
        return 1
    fi
}

ne_match_signal() {
    local cond="$1" part field op val actual oldIFS
    oldIFS="$IFS"; IFS='&'; set -- $cond; IFS="$oldIFS"
    for part in "$@"; do
        part=$(echo "$part" | sed 's/^ *//;s/ *$//')
        [ -z "$part" ] && continue
        field=$(echo "$part" | awk '{print $1}')
        op=$(echo "$part" | awk '{print $2}')
        val=$(echo "$part" | awk '{print $3}')
        actual=$(ne_state_get "$field")
        [ -z "$actual" ] && actual="-9999"
        case "$op" in
            '<')  [ "$actual" -lt "$val" ] 2>/dev/null || return 1 ;;
            '<=') [ "$actual" -le "$val" ] 2>/dev/null || return 1 ;;
            '>')  [ "$actual" -gt "$val" ] 2>/dev/null || return 1 ;;
            '>=') [ "$actual" -ge "$val" ] 2>/dev/null || return 1 ;;
            '==') [ "$actual" = "$val" ] 2>/dev/null || return 1 ;;
            *) return 1 ;;
        esac
    done
    return 0
}

# 主决策
ne_decide() {
    local line type mode args cur_motion
    [ -f "$NE_AUTO_RULES" ] || { echo "normal"; return 0; }

    # 先算运动状态 (motion 规则需要它)
    cur_motion=$(ne_detect_motion)

    while IFS= read -r line; do
        case "$line" in ''|\#*|AUTO_*|MOTION_*) continue ;; esac
        type=$(echo "$line" | awk '{print $1}')
        case "$type" in
            app)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                topapp=$(ne_state_get topapp)
                [ -n "$topapp" ] && echo ",$args," | grep -q ",$topapp," && { echo "$mode"; return 0; }
                ;;
            motion)
                # motion <mode> <类型>
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                [ "$args" = "$cur_motion" ] && { echo "$mode"; return 0; }
                ;;
            charging)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                local cur_chg; cur_chg=$(ne_state_get charging)
                # true → 1, false → 0
                [ "$args" = "true" ] && [ "$cur_chg" = "1" ] && { echo "$mode"; return 0; }
                [ "$args" = "false" ] && [ "$cur_chg" = "0" ] && { echo "$mode"; return 0; }
                ;;
            screen)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                local cur_scr; cur_scr=$(ne_state_get screen_on)
                [ "$args" = "on" ] && [ "$cur_scr" = "1" ] && { echo "$mode"; return 0; }
                [ "$args" = "off" ] && [ "$cur_scr" = "0" ] && { echo "$mode"; return 0; }
                ;;
            cellloc)
                mode=$(echo "$line" | awk '{print $2}')
                args=$(echo "$line" | awk '{print $3}')
                [ "$args" = "__HOME_CIDS__" ] && continue
                [ "$args" = "__WORK_CIDS__" ] && continue
                [ -n "$args" ] || continue
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
                local cond; cond=$(echo "$line" | cut -d' ' -f3-)
                ne_match_signal "$cond" && { echo "$mode"; return 0; }
                ;;
            default)
                echo "$(echo "$line" | awk '{print $2}')"; return 0
                ;;
        esac
    done < "$NE_AUTO_RULES"
    echo "normal"
}

# 自愈
ne_heal() {
    [ "$AUTO_HEAL_ENABLE" = "true" ] || return 0
    local wifi_conn gw_ok ping_loss
    wifi_conn=$(ne_state_get wifi_connected)
    gw_ok=$(ne_state_get gateway_ok)
    ping_loss=$(ne_state_get packet_loss)

    # WiFi 假连接重连
    if [ "$wifi_conn" = "1" ] && [ "$gw_ok" = "0" ]; then
        ne_log "自愈: WiFi 假连接, 重连"
        cmd wifi disable 2>/dev/null; sleep 2; cmd wifi enable 2>/dev/null
        ne_event "HEAL wifi_fake -> reconnect"
        return 0
    fi
    # 高丢包切 DNS
    if [ -n "$ping_loss" ] && [ "$ping_loss" != "?" ] && [ "$ping_loss" -gt 50 ] 2>/dev/null; then
        ne_log "自愈: 丢包 ${ping_loss}%, 切 DNS"
        settings put global dns1 119.29.29.29
        settings put global dns2 223.5.5.5
        ne_event "HEAL high_loss -> switch_dns"
        return 0
    fi
    return 0
}

# 应用模式
ne_apply() {
    local mode="$1"
    ne_log "应用场景: $mode (运动: $(ne_detect_motion))"
    sh "$NE_SCRIPTS/auto_apply.sh" "$mode" 2>/dev/null
    ne_notify "网络增强" "已切换: $mode"
}

# 单次评估
ne_eval_once() {
    [ "$AUTO_ENGINE_ENABLE" = "true" ] || return 0
    ne_collect_state
    ne_log "采集: app=$(ne_state_get topapp) motion=$(ne_detect_motion) chg=$(ne_state_get charging) scr=$(ne_state_get screen_on) rssi=$(ne_state_get wifi_rssi) rsrp=$(ne_state_get cell_rsrp)"

    ne_heal

    local target cur last_switch now elapsed pending
    target=$(ne_decide)
    cur=$(ne_current_mode)
    [ "$target" = "$cur" ] && { : > "$NE_AUTO_PENDING" 2>/dev/null; return 0; }

    now=$(date +%s 2>/dev/null || echo 0)
    last_switch=$(ne_last_switch)
    elapsed=$((now - last_switch))
    [ "$elapsed" -lt "$AUTO_MIN_SWITCH_SEC" ] && { ne_log "防抖: ${elapsed}s < ${AUTO_MIN_SWITCH_SEC}s 跳过"; return 0; }

    pending=$(cat "$NE_AUTO_PENDING" 2>/dev/null || echo 0)
    pending=$((pending + 1))
    echo "$pending" > "$NE_AUTO_PENDING"
    ne_log "目标=$target 命中 $pending/$AUTO_CONFIRM_COUNT"
    [ "$pending" -ge "$AUTO_CONFIRM_COUNT" ] && { ne_apply "$target"; : > "$NE_AUTO_PENDING" 2>/dev/null; }
}

# 主循环
ne_main_loop() {
    ne_load_conf
    ne_log "===== 引擎启动 (interval=${AUTO_INTERVAL_SEC}s) ====="
    echo $$ > "$NE_AUTO_PID"
    trap 'ne_log "引擎停止"; rm -f "$NE_AUTO_PID"; exit 0' INT TERM HUP
    while :; do
        ne_eval_once
        sleep "${AUTO_INTERVAL_SEC:-20}" 2>/dev/null || sleep 20
    done
}

# 状态 JSON (供 WebUI)
ne_status_json() {
    ne_collect_state
    local mode target motion
    mode=$(ne_current_mode)
    target=$(ne_decide)
    motion=$(ne_detect_motion)
    echo "{"
    echo "  \"mode\": \"$mode\","
    echo "  \"target\": \"$target\","
    echo "  \"motion\": \"$motion\","
    sed -e 's/^/  "/' -e 's/=/": "/' -e 's/$/",/' "$NE_AUTO_STATE" 2>/dev/null | sed '$ s/,$//'
    echo "}"
}

case "${1:-}" in
    start)
        [ -f "$NE_AUTO_PID" ] && kill -0 "$(cat "$NE_AUTO_PID")" 2>/dev/null && { echo "已运行 PID $(cat "$NE_AUTO_PID")"; exit 0; }
        ne_load_conf
        [ "$AUTO_ENGINE_ENABLE" != "true" ] && { echo "引擎已禁用"; exit 0; }
        nohup sh "$0" _daemon >/dev/null 2>&1 &
        sleep 1
        [ -f "$NE_AUTO_PID" ] && echo "已启动 PID $(cat "$NE_AUTO_PID")" || echo "启动失败"
        ;;
    _daemon) ne_main_loop ;;
    stop)
        [ -f "$NE_AUTO_PID" ] && { kill "$(cat "$NE_AUTO_PID")" 2>/dev/null; rm -f "$NE_AUTO_PID"; echo "已停止"; } || echo "未运行"
        ;;
    status)
        echo "===== NE Auto 状态 ====="
        [ -f "$NE_AUTO_PID" ] && kill -0 "$(cat "$NE_AUTO_PID")" 2>/dev/null && echo "运行中 PID $(cat "$NE_AUTO_PID")" || echo "未运行"
        echo "当前模式: $(ne_current_mode)"
        echo "运动状态: $(ne_detect_motion)"
        echo ""
        cat "$NE_AUTO_STATE" 2>/dev/null
        echo ""
        echo "[最近事件]"
        tail -10 "$NE_AUTO_EVENT" 2>/dev/null
        ;;
    once)
        ne_load_conf
        ne_collect_state
        echo "目标: $(ne_decide)  当前: $(ne_current_mode)  运动: $(ne_detect_motion)"
        cat "$NE_AUTO_STATE"
        ;;
    record)
        [ -z "$2" ] && { echo "用法: record home|work"; exit 1; }
        cid=$(ne_get_cellid)
        [ -z "$cid" ] && { echo "无法读取 CID"; exit 1; }
        placeholder="__$(echo "$2" | tr '[:lower:]' '[:upper:]')_CIDS__"
        sed -i "s|$placeholder|$cid|" "$NE_AUTO_RULES" 2>/dev/null && echo "已记录 $2: $cid" || echo "未找到占位符"
        ;;
    json) ne_status_json ;;
    _motion)
        ne_load_conf
        ne_collect_state
        ne_detect_motion
        ;;
    apply)
        [ -z "$2" ] && { echo "用法: apply <mode>"; exit 1; }
        sh "$NE_SCRIPTS/auto_apply.sh" "$2"
        echo "已应用: $2"
        ;;
    speedtest)
        echo "=== 延迟 ==="
        for t in 223.5.5.5 119.29.29.29; do
            out=$(ping -c 5 -W 2 "$t" 2>/dev/null)
            avg=$(echo "$out" | grep -oE '/[0-9.]+' | head -1 | tr -d '/')
            echo "  $t: ${avg:-?}ms"
        done
        echo "=== 下载 ==="
        for url in "https://speed.cloudflare.com/__down?bytes=1048576"; do
            t1=$(date +%s); bytes=$(curl -s -m 10 -o /dev/null -w '%{size_download}' "$url" 2>/dev/null); t2=$(date +%s)
            dur=$((t2-t1)); [ "$dur" -le 0 ] && dur=1
            echo "  Cloudflare: $((bytes*8/1024/1024/dur)) Mbps"
        done
        ;;
    *)
        cat <<EOF
Network Enhance Auto (KSU) v1.0.0

用法:
  sh auto_engine.sh start          启动
  sh auto_engine.sh stop           停止
  sh auto_engine.sh status         状态
  sh auto_engine.sh once           单次评估
  sh auto_engine.sh record home|work   记录位置
  sh auto_engine.sh apply <mode>   手动应用场景
  sh auto_engine.sh speedtest      测速
  sh auto_engine.sh json           输出 JSON (WebUI 用)
EOF
        ;;
esac
exit 0
