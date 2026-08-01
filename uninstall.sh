#!/system/bin/sh
# uninstall.sh — 模块卸载时清理
# 停止引擎 + 清理运行时文件
if [ -f /data/local/tmp/ne_auto/engine.pid ]; then
    kill "$(cat /data/local/tmp/ne_auto/engine.pid)" 2>/dev/null
fi
rm -rf /data/local/tmp/ne_auto 2>/dev/null
# 恢复网络设置为默认 (可选, 保守起见不强制改)
exit 0
