#!/bin/bash
# FragmentTime - build + serve script
# 1) flutter build web (HTML renderer, release)
# 2) 清理 build 残留的 canvaskit/skwasm 目录
# 3) patch 掉 service worker（HTTP 下注册会失败）
# 4) 重启 python http server 在 9090

set -e

PROJECT_DIR="/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good"
FLUTTER="/opt/flutter/bin/flutter"
LOG="/tmp/ft_http.log"

cd "$PROJECT_DIR"

# 1) build
echo "=== flutter build web --release --web-renderer html ==="
# 默认走本地 Ollama（无需 key）；如需外部 LLM，set LLM_API_KEY + LLM_ENDPOINT 环境变量
DART_DEFINES="--dart-define=BUILD_MODE=domestic"
# 6/10 加: 每次 build 注入 BUILD_VERSION = 时间戳短码（让你看 Settings → 版本信息验证拿到最新 build）
BUILD_TS=$(date +%y%m%d-%H%M)
DART_DEFINES="$DART_DEFINES --dart-define=BUILD_VERSION=$BUILD_TS"
if [ -n "$LLM_API_KEY" ] && [ -n "$LLM_ENDPOINT" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=LLM_API_KEY=$LLM_API_KEY --dart-define=LLM_ENDPOINT=$LLM_ENDPOINT"
fi
"$FLUTTER" build web --release --web-renderer html $DART_DEFINES

# 2) 清 canvaskit/skwasm（HTML renderer 用不到）
rm -rf build/web/canvaskit build/web/skwasm

# 2.5) 复制干净 SW 到 build/web (6/25 PWA: HTTPS 下生效, HTTP 下 index.html 跳过注册)
cp -f /volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/web/service-worker.js \
      /volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/build/web/service-worker.js 2>/dev/null
if [ -f /volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/build/web/service-worker.js ]; then
  echo "  service-worker.js copied to build/web"
else
  echo "  WARNING: service-worker.js copy failed"
fi

# 3) patch service worker (HTTP-only context: SW registration fails)
python3 - <<'PYEOF'
import re
p = "/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/build/web/flutter_bootstrap.js"
with open(p) as f:
    s = f.read()
DISABLED_MARK = "// SW disabled (HTTP-only context)"
if DISABLED_MARK in s:
    print("  service worker already patched")
else:
    # 匹配 _flutter.loader.load({<anything>}); 其中含 serviceWorkerSettings
    pattern = re.compile(r"_flutter\.loader\.load\([^;]*?serviceWorkerSettings[^;]*?\);", re.DOTALL)
    new, n = pattern.subn(
        "// SW disabled (HTTP-only context); service worker would fail to register\n_flutter.loader.load({});",
        s,
    )
    if n > 0:
        with open(p, "w") as f:
            f.write(new)
        print(f"  patched service worker ({n} replacement)")
    else:
        print("  WARNING: service worker block not found - may already be disabled or build format changed")
PYEOF

# 3.5) patch index.html cache 头（6/8 修：避免浏览器 client 端 cache 到旧 build）
# 22 个旧 build 重叠之后，用户硬刷也拿不到新版。加 no-cache meta
python3 - <<'PYEOF'
p = "/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/build/web/index.html"
with open(p) as f:
    s = f.read()
CACHE_MARK = "<!-- 6/8: no-cache meta added -->"
if CACHE_MARK in s:
    print("  index.html cache meta already patched")
else:
    # 在 <head> 里第一行加 cache meta
    cache_meta = (
        '<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">\n'
        '<meta http-equiv="Pragma" content="no-cache">\n'
        '<meta http-equiv="Expires" content="0">\n'
        + CACHE_MARK + '\n'
        # 6/12 加: viewport + iOS meta（手机不设 viewport 会用 980px layout，Tab 错位）
        + '<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">\n'
        + '<meta name="theme-color" content="#6750A4">\n'
        + '<meta name="format-detection" content="telephone=no">\n'
    )
    if "<head>" in s:
        new = s.replace("<head>", "<head>\n" + cache_meta, 1)
    elif "<head " in s:
        # 非常罕见但严谨
        import re
        new = re.sub(r"(<head[^>]*>)", r"\1\n" + cache_meta, s, count=1)
    else:
        print("  WARNING: <head> not found, skipping cache meta patch")
        new = s
    if new != s:
        with open(p, "w") as f:
            f.write(new)
        print("  patched index.html with no-cache meta")
PYEOF

# 3.6) patch manifest.json 标题 + 背景色 + 主题色（6/8 PWA）
# Flutter 默认 manifest name='fragment_time'，颜色='#0175C2'，不是主 app 紫色
python3 - <<'PYEOF'
import json
p = "/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/build/web/manifest.json"
with open(p) as f:
    m = json.load(f)
PATCHED_KEY = "_ft_patched"
if m.get(PATCHED_KEY):
    print("  manifest.json already patched")
else:
    m['name'] = '\u788e\u7247\u65f6\u95f4 / Fragment Time'
    m['short_name'] = '\u788e\u7247\u65f6\u95f4'
    m['description'] = '\u788e\u7247\u65f6\u95f4\uff0c5 \u5206\u949f\u8bfb\u5b8c\u3002'
    m['background_color'] = '#6750A4'
    m['theme_color'] = '#6750A4'
    m['start_url'] = '.'
    m['display'] = 'standalone'
    m['orientation'] = 'portrait'
    m[PATCHED_KEY] = True
    with open(p, 'w') as f:
        json.dump(m, f, ensure_ascii=False, indent=4)
    print("  patched manifest.json (\u788e\u7247\u65f6\u95f4 + \u7d2b\u8272)")
PYEOF

# 3.7) patch main.dart.js 版本号 (6/10 修: 避免浏览器 client 端 cache 到旧 build)
# flutter_bootstrap.js 里 4 处 'main.dart.js' 改成 'main.dart.js?v=<时间戳>'
python3 - <<'PYEOF'
import re, time
p = "/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/build/web/flutter_bootstrap.js"
with open(p) as f:
    s = f.read()
VER = str(int(time.time()))
# 只改裸 "main.dart.js" (没跟 ?v=)
pattern = re.compile(r'"main\.dart\.js(?!\?v=)"')
new, n = pattern.subn(f'"main.dart.js?v={VER}"', s)
if n > 0:
    with open(p, "w") as f:
        f.write(new)
    print(f"  patched main.dart.js version -> ?v={VER} ({n} replacements)")
else:
    print(f"  main.dart.js version already at ?v={VER} or no match")
PYEOF

# 4) 重启 server
echo "=== restart http server on 9090 ==="
ps aux | grep "http.server 9090" | grep -v grep | awk '{print $2}' | xargs -r kill 2>/dev/null
sleep 1
cd build/web
nohup python3 -m http.server 9090 --bind 0.0.0.0 > "$LOG" 2>&1 &
disown
sleep 2

# 5) 报告
echo ""
echo "=== done ==="
echo "URL: http://192.168.1.20:9090/"
echo "Log: $LOG"
ss -tlnp 2>/dev/null | grep ":9090" | head -1
