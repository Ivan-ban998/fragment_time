#!/bin/bash
# 6/13 9090 守护：30s 自检 + 死了自动拉起
# 由 crontab 每 30s 触发（* * * * * 加 sleep loop）

set -e
PORT=9090
PROJ_DIR="/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good"
LOG="/tmp/ft_http.log"

# 健康检查（127.0.0.1 永远快，tailscale 慢可能误判）
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:$PORT/ 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  # 健康，无需操作
  exit 0
fi

# 死了 → 拉起
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 9090 unhealthy (HTTP $HTTP_CODE), restarting..." >> "$LOG"
cd "$PROJ_DIR/build/web"
nohup python3 -m http.server $PORT >> "$LOG" 2>&1 &
sleep 1

# 验证
HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:$PORT/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE2" = "200" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 9090 restarted OK (pid $!)" >> "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 9090 restart FAILED (HTTP $HTTP_CODE2)" >> "$LOG"
fi
