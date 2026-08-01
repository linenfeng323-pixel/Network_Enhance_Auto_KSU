#!/system/bin/sh
# post-fs-data.sh — KernelSU post-fs-data 阶段 (极早, 仅做轻量准备)
# 此阶段网络/属性尚未就绪, 不做网络操作, 仅初始化运行时目录
MODDIR=${0%/*}
mkdir -p /data/local/tmp/ne_auto 2>/dev/null
chmod 0777 /data/local/tmp/ne_auto 2>/dev/null
exit 0
