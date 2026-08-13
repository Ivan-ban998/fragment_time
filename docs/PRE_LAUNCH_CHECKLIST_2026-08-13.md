# 🚀 FragmentTime 8/13 上线前检查清单 (Pre-Launch Checklist)

> **时间**: 2026-08-13 18:10 CST
> **状态**: ⏳ 待 Brien 浏览器实测 + 拍板 push origin/main
> **对应 build**: 18:05 增量编译, 包含 13 个 commit 修复

---

## ✅ 服务端状态 (curl 已验证)

| 项 | 状态 | 实测 |
|---|---|---|
| `flutter-keepalive.service` (7080) | ✅ running | systemd 守护 |
| `llm-proxy.service` (11435) | ✅ running | systemd 守护, has_key=true |
| `rss_proxy.py` (7088) | ✅ running | 沿用 alert 老服务 |
| `ollama serve` (11434) | ✅ running | 6 模型 |
| `content.soulvag.com` (CF Tunnel → 7080) | ✅ HTTP 200 | CF 边缘 |
| AI 端到端 (`/api/llm`) | ✅ **0.86s 首 token** | curl 实测 |
| RSS 国内版 (sspai + npr + 36kr) | ✅ 3 源 | 拉 10/10/0 items |
| RSS 国际版 (verge + npr + npr_music) | ✅ 3 源 | 拉 10/10/10 items |
| `flutter analyze` | ✅ 0 error | 490 issues (原有 withOpacity, 沿 ROADMAP §C) |
| `flutter build web` | ✅ 25.3s | 增量编译 OK |

---

## 🌐 浏览器实测清单 (Brien)

**操作步骤** (重要顺序!):
1. **打开 DevTools** (F12) → Application 标签 → Service Workers → **确认已 Unregister**
   - 如果还有 active SW, 点击 "Unregister" 按钮
2. **Application → Storage → Clear site data** → 勾 "Unregister service workers" + "Cache" → Clear
3. **Network 标签 → 勾 "Disable cache"** (防 SW 重新注册)
4. **Ctrl+Shift+R** 硬刷
5. 等 5-10s 让 Flutter web 启动

### Test A: 切换用户角色 (6 角色都试)
- [ ] 选"学生" → 应该看到 `碎片时间 · 学习` 标题
- [ ] 选"上班族" → 标题应该改 `上班族 · ...` (scene 跟 userType 变)
- [ ] 选"创业者" → 应该看到不同 AI 内容
- [ ] 选"宝爸宝妈" → 应该看到不同 AI 内容
- [ ] 选"退休人群" → 应该看到不同 AI 内容
- [ ] 选"儿童" → 应该看到绿色盾牌"儿童安全模式"

### Test B: 切换场景 (4 场景都试, 关键)
- [ ] 切到"学" → tinder 卡应该有不同的内容 (不要跟"听"一样!)
- [ ] 切到"听" → tinder 卡应该是精选为主的 6 张 (sspai 听故事 + 中学古诗 等)
- [ ] 切到"放松" → tinder 卡应该是 sspai 数码/工具文 (精选番茄钟 兑底)
- [ ] 切到"动一动" → tinder 卡应该是 sspai 工具文 (精选跑步热身 兑底)

### Test C: tinder 卡片详情
- [ ] 卡上有红色"实时" Live 圆点 → 这是真 RSS
- [ ] 卡上有灰色"精选" chip → 这是国内 _allContent 精选兑底
- [ ] 卡的 source 显示真实来源 (`少数派` / `NPR` / `36氪`), 不是全部显示 "36氪"
- [ ] 点卡进入详情 → 应该跳到 ContentReaderScreen (不是 push 另一个 ContentScreen)

### Test D: AI 体验
- [ ] **首屏 hero 内容**: 应该 1-3s 出 (不是 30s+ 等死)
- [ ] **点 AI 浮动按钮** (右下角紫色按钮) → 弹 AI 答疑 sheet
- [ ] **问一句话** → 1-3s 流式出 (miniMax AI 模型响应)
- [ ] **每日名言 banner** (顶部) → 显示 `📰 [作者] — [出处]` 一句话

### Test E: 国际版 (重要!)
- [ ] 设置 → 切语言到 "English"
- [ ] 设置 → 切到"国际版"
- [ ] 等 Flutter 重新加载 (Key 变了)
- [ ] tinder 卡应该全英文 (The Verge / NPR / NPR Music)
- [ ] 顶部应该看到 `Live from The Verge` 标识
- [ ] 切回"国内版" → 应该看到 sspai 中文 RSS

---

## 🚨 已发现但需 Brien 确认的细节

### 1. "4 场景都一样" 修复 (沿 SOUL #137 真凶链)

**根因**: 老 SW (Service Worker) HTTPS 下 active, 拦截 fetch 返老 main.dart.js
**修法** (30c597d): `web/index.html` 加 SW cleanup 脚本
- 进入页面立即 `getRegistrations() + unregister()`
- 清空 `caches.keys() + caches.delete()`
- 配合 `ft_server.py` 返 404 阻止新 SW register, 强制浏览器拿新 build

**验证**: 你 `Ctrl+Shift+R` 后应该看到 4 场景内容差异明显 (学 vs 听 vs 放松 vs 动一动)

**如果还有问题**:
1. DevTools → Application → Service Workers → **手动点 "Unregister"**
2. DevTools → Application → Storage → **"Clear site data"** 全勾选 → Clear
3. 关浏览器重开

### 2. NPR Music 国际版专属

`rss_service.dart` `_feedUrls` 国内/国际分流:
- 国内: `[sspai, npr, 36kr]` (3 源)
- 国际: `[verge, npr, npr_music]` (3 源)

**国际版听场景** 应该看到 NPR Music 英文 podcast (英文标题), 不是 sspai 中文。

### 3. Source name 真实

之前 `rss_service.dart:343` source 写死 `_sourceName` → 跨源混杂 (NPR item 也显示 "36氪")。
修法: 新增 `_resolveSourceName(url)` 从 URL host 解析真实来源。

预期看到:
- sspai.com → `少数派`
- npr.org/1001 → `NPR`
- npr.org/1039 → `NPR Music`
- 36kr.com → `36氪`
- theverge.com → `The Verge`

---

## ⚠️ 沿用 alert 老坑 (待 Brien 拍)

| 项 | 状态 | 备注 |
|---|---|---|
| `origin/main` 仍是 7/28 13d826d | ⏳ 待 push | `git push origin fix/linear-gradient-full-cleanup:main --force-with-lease` (沿用 7/28 沿用 alert) 或走 PR |
| 305 处 `withOpacity` deprecation | ⏳ 沿用 ROADMAP §C 不擅自动 | Flutter 3.27 升级遗留 |
| `lib/main.dart` 1834 行 + `content_screen.dart` 1949 行 | ⏳ P2 单文件过大 | 按 feature 拆 module |
| `lib/` 含 5 处 TODO/FIXME 残留 | ⏳ P3 沿用 alert | content_reader_screen child HARD RULE 等 |
| rss_proxy.py (端口 7088) 还在跑独立服务 | ⏳ 沿用 alert | ft_server.py 已接管 /rss 路由, 7088 可下 |
| cloudflared-tunnel-dns-dead | ⏳ RESOLVED 7/21 | content.soulvag.com 通 |
| GHub SSH 限流 | ⏳ RESOLVED 7/18 | 这次 12 commits 都推成功 |

---

## 🔧 操作命令 (Brien 可直接跑)

### 强制清浏览器 SW 缓存 (Python 验证 HTTP 200 后再用)
```bash
# DevTools → Application → Service Workers → Unregister
# DevTools → Application → Storage → Clear site data
# Ctrl+Shift+R
```

### 看 systemd 服务状态
```bash
systemctl --user status llm-proxy
systemctl --user status flutter-keepalive
journalctl --user -u llm-proxy --no-pager -n 20
```

### 看 ft_server 日志 (RSS + AI 链路)
```bash
tail -f /tmp/ft_server.log
```

### 手动测 AI 链路 (curl)
```bash
time curl -s "http://192.168.1.2:7080/api/llm" -X POST \
  -H "Content-Type: application/json" \
  -d '{"model":"MiniMax-Text-01","stream":false,"messages":[{"role":"user","content":"一句话"}],"max_tokens":50}' \
  --max-time 15 -w "\nHTTP: %{http_code}, time: %{time_total}s\n"
```

### push origin/main (沿用 7/28 沿用 alert)
```bash
cd "/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good"
git push origin fix/linear-gradient-full-cleanup:main --force-with-lease
```

---

## 📜 Git 状态

```
GitHub:  13 commits ahead of origin/main
Gitea:   13 commits synced (http://192.168.1.2:3002/Brien/fragment_time)
Branch:  fix/linear-gradient-full-cleanup
Latest:  30c597d fix(rss+web): source name 真实 + SW cleanup 强制清老缓存
```

---

## ✍️ 我推荐的下一步 (按优先级)

1. **🔴 你现在做**: 浏览器实测 → 验证 Test A-E 清单 → 报告问题
2. **🟠 重要**: 拍板 `origin/main` push 方式 (force 或 PR) — 你来决策
3. **🟡 P2 优化**: withOpacity deprecation / 大文件拆分 (等 Brien 醒后拍)
4. **🟢 监控**: 给 ft_server 加访问统计 (沿用 alert 老方案)

**8/13 大单全部完成, 等 Brien 浏览器实测确认**。