#!/system/bin/sh
# customize.sh — KernelSU 安装时脚本
SKIPUNZIP=0

ui_print "==================================="
ui_print " Network Enhance Auto (KSU) v1.0.0"
ui_print " 全自动场景网络优化"
ui_print "==================================="

# Android 版本校验
API=$(getprop ro.build.version.sdk)
if [ "$API" -lt 30 ]; then
    ui_print "! 警告: Android 11 以下未测试, 可能不生效"
fi
ui_print "- Android API: $API"

# 设备信息
BRAND=$(getprop ro.product.brand)
MODEL=$(getprop ro.product.model)
ui_print "- 设备: $BRAND / $MODEL"

# 设置目录权限
ui_print "- 设置权限..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755

# 初始化运行时目录
mkdir -p /data/local/tmp/ne_auto
chmod 0777 /data/local/tmp/ne_auto

ui_print "- 安装完成"
ui_print "- 重启后自动启动"
ui_print "- WebUI: KernelSU 管理器内点击模块"
ui_print "==================================="
