#!/system/bin/sh
# service.sh — KernelSU 开机后启动 (late_start 服务)
MODDIR=${0%/*}

# 等待系统就绪
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 10

# 启动自动场景引擎
nohup sh "$MODDIR/scripts/auto_engine.sh" _daemon >/dev/null 2>&1 &
echo "$(date) NE-Auto 引擎已由 service.sh 拉起, PID=$!" >> /data/local/tmp/ne_auto/boot.log
