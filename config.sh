#!/system/bin/sh
# config.sh — Network Enhance Auto 用户配置中心
#
# 所有用户可调参数集中在此文件, 修改后重启模块生效
# ===============================
# 1. 自动引擎总开关
# ===============================
ENABLE_AUTO_ENGINE=true

# 检测间隔 (秒)
AUTO_INTERVAL_SEC=20

# 模式切换最小间隔 (秒, 防抖)
AUTO_MIN_SWITCH_SEC=60

# 连续命中多少次才真正切换
AUTO_CONFIRM_COUNT=2

# ===============================
# 2. 自愈
# ===============================
# WiFi 假连接重连 + 高丢包切 DNS
AUTO_HEAL_ENABLE=true

# ===============================
# 3. 高速移动判定
# ===============================
# 单位时间(秒)内基站 CID 变化次数 >= 此值 → 判定高速移动
MOTION_DETECT_WINDOW=120
MOTION_CID_CHANGE_THRESHOLD=3
# 速度估算 >= 此值 km/h → 判定高铁
MOTION_HIGH_SPEED_KMH=150

# ===============================
# 4. 每日报告
# ===============================
# 报告时间 (HH:MM, 留空则不推送)
AUTO_REPORT_TIME="21:00"

# ===============================
# 5. 场景规则文件
# ===============================
# 规则配置文件路径 (默认 scripts/auto_rules.conf)
AUTO_RULES_FILE="scripts/auto_rules.conf"
