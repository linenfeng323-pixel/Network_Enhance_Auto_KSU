#!/system/bin/sh
# customize.sh — Network Enhance Auto 安装脚本 (会被 source, 不能用 exit, 用 abort)
SKIPUNZIP=0

ui_print "***************************************"
ui_print "  Network Enhance Auto (KSU)"
ui_print "  全自动场景网络优化"
ui_print "  高铁/地铁/飞机/游戏/弱网 等场景自动切换"
ui_print "***************************************"
ui_print ""

# MODPATH 健壮性校验
if [ -z "${MODPATH:-}" ] || [ ! -d "$MODPATH" ]; then
    if [ -n "${0:-}" ] && echo "$0" | grep -q '/' 2>/dev/null; then
        _candidate="${0%/*}"
        [ -f "$_candidate/module.prop" ] 2>/dev/null && MODPATH="$_candidate"
    fi
    [ -z "${MODPATH:-}" ] && [ -f "/data/adb/modules/network_enhance_auto/module.prop" ] 2>/dev/null && MODPATH="/data/adb/modules/network_enhance_auto"
    if [ -z "${MODPATH:-}" ] || [ ! -d "$MODPATH" ]; then
        abort "MODPATH 解析失败"
    fi
fi

ui_print "  作者 : NE-Auto"
ui_print "  协议 : MIT"
ui_print ""
ui_print "---------------------------------------"
ui_print "  运行环境与厂商探测"
ui_print "---------------------------------------"
if [ -d "/data/adb/ksu" ] 2>/dev/null; then
    ui_print "  -> 引擎   : KernelSU (Root)"
elif [ -d "/data/adb/magisk" ] 2>/dev/null; then
    ui_print "  -> 引擎   : Magisk (Root)"
elif [ -d "/data/adb/ap" ] 2>/dev/null; then
    ui_print "  -> 引擎   : APatch (Root)"
else
    ui_print "  -> 引擎   : 未知 (需 Root 框架)"
fi
ui_print "  -> 设备   : $(getprop ro.product.model)"
ui_print "  -> 厂商   : $(getprop ro.product.brand)"
ui_print "  -> Android: $(getprop ro.build.version.release) (API ${API:-?})"
ui_print "  -> 架构   : ${ARCH:-?}"
ui_print ""

ui_print "---------------------------------------"
ui_print "  关键特性"
ui_print "---------------------------------------"
ui_print "  [多维] 前台App/运动/充电/息屏/基站/时间/信号"
ui_print "  [场景] 高铁 地铁 飞机 游戏 通话 视频 弱网 省电 默认"
ui_print "  [自愈] WiFi假连接重连 + 高丢包切DNS"
ui_print "  [防抖] 连续命中2次 + 60秒最小切换间隔"
ui_print "  [WebUI] 深色科技风可视化"
ui_print ""

ui_print "---------------------------------------"
ui_print "  设置文件权限"
ui_print "---------------------------------------"
if [ -d "$MODPATH/scripts" ]; then
    set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
    ui_print "  [OK] scripts/ 权限已设置"
fi
if [ -d "$MODPATH/webroot" ]; then
    set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
    ui_print "  [OK] webroot/ 权限已设置"
fi
for _f in post-fs-data.sh service.sh uninstall.sh action.sh customize.sh; do
    [ -f "$MODPATH/$_f" ] && set_perm "$MODPATH/$_f" 0 0 0755
done
for _f in config.sh module.prop; do
    [ -f "$MODPATH/$_f" ] && set_perm "$MODPATH/$_f" 0 0 0644
done

# 初始化运行时目录
mkdir -p /data/local/tmp/ne_auto 2>/dev/null
chmod 0777 /data/local/tmp/ne_auto 2>/dev/null

ui_print ""
ui_print "***************************************"
ui_print "  安装成功 (Network Enhance Auto)"
ui_print "***************************************"
ui_print ""
ui_print "  日志: /data/local/tmp/ne_auto/engine.log"
ui_print "  配置: \$MODPATH/config.sh"
ui_print "  规则: \$MODPATH/scripts/auto_rules.conf"
ui_print "  WebUI: KSU 管理器内点击模块"
ui_print ""
ui_print "  重启后自动启动"
