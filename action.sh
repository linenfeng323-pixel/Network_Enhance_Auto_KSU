#!/system/bin/sh
# action.sh — KernelSU 模块菜单入口 (点击模块时执行)
MODDIR=${0%/*}

echo "==================================="
echo " Network Enhance Auto"
echo "==================================="
echo ""
echo "当前模式: $(cat /data/local/tmp/ne_auto/current_mode 2>/dev/null || echo 未启动)"
echo "运动状态: $(sh "$MODDIR/scripts/auto_engine.sh" _motion 2>/dev/null || echo 未知)"
echo ""
echo "[1] 启动引擎"
echo "[2] 停止引擎"
echo "[3] 单次评估"
echo "[4] 测速"
echo "[5] 查看状态"
echo "[6] 记录家位置"
echo "[7] 记录公司位置"
echo "[0] 退出"
echo ""
printf "选择: "
read -r choice
case "$choice" in
    1) sh "$MODDIR/scripts/auto_engine.sh" start ;;
    2) sh "$MODDIR/scripts/auto_engine.sh" stop ;;
    3) sh "$MODDIR/scripts/auto_engine.sh" once ;;
    4) sh "$MODDIR/scripts/auto_engine.sh" speedtest ;;
    5) sh "$MODDIR/scripts/auto_engine.sh" status ;;
    6) sh "$MODDIR/scripts/auto_engine.sh" record home ;;
    7) sh "$MODDIR/scripts/auto_engine.sh" record work ;;
    0) exit 0 ;;
    *) echo "无效选择" ;;
esac
