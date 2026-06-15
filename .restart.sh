#!/bin/bash
# FragmentTime dev server restart - 2026-06-04
pkill -f "flutter.*web-server" 2>/dev/null
sleep 2
cd /volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time
nohup flutter run -d web-server --web-port 9090 --web-hostname 0.0.0.0 --dart-define=BUILD_MODE=domestic > /tmp/flutter_run.log 2>&1 &
disown
echo "启动指令已发出，编译约需 50 秒"
