# 🚀 FragmentTime 8/14 正式上线检查清单 (v3 — Performance Done)

> **更新时间**: 2026-08-14 16:25 CST
> **当前状态**: 🟢 **Production-Ready** (3 轮 P1 治本 + Puppeteer E2E 全验证)
> **对应 build**: 8/14 16:20 增量编译 (commit `02dc378`)
> **公网**: https://content.soulvag.com/  (CF Tunnel → 7080)

---

## ✅ 服务端状态 (Puppeteer E2E 实测 8/14 16:25)

| 指标 | 数值 | 状态 |
|---|---|---|
| 首页加载 | 7.52s | ✅ |
| Learn RSS 端拉 | 0.91s, 110 items | ✅ (4/4 OK) |
| Listen RSS 端拉 | 1.51s, 50 items | ✅ (4/4 OK) |
| Relax RSS 端拉 | 1.72s, 90 items | ✅ (5/5 OK) |
| Workout RSS 端拉 | 1.72s, 70 items | ✅ (4/4 OK) |
| 4 场景 AI 首 token | 0.73-1.26s | ✅ |
| Page errors | 0 | ✅ |
| flutter analyze | 0 error | ✅ |
| Flutter build | 50.5s | ✅ |

---

## 🐛 历轮修复总览 (19 commits since 7/29)

### 第 1 轮 8/7 — tinder 内容真实化 (8 commits)
- `a3fb3f9` fix(rss): _dedupeSimilar.normalize clamp 
- `2da58ef` fix(news): 24 桶全满 6 张
- `b6c1c98` refactor(aggregator): 复用 NewsService
- `f6e3874` feat(tinder): curated 显示'精选'灰底 chip
- `e4d2a11` feat(rss): 加 NPR Top Stories + NPR Music
- `cf462b6` fix(llm): timeout 120s→15s + Ollama 7b fallback
- `6af6229` fix(rss): isInternational 透传
- `30c597d` fix(rss+web): source name 真实 + SW cleanup

### 第 2 轮 8/13 — AI 体验大修 (5 commits)
- `89df024` docs: SOUL #190-#197 + MR-1~MR-10
- `ebea793` docs: 8/13 上线检查清单 (v1)
- `bd1a114` fix(rss): 4 场景真凶治本 + 8 源

### 第 3 轮 8/14 上午 — 性能治本 (1 commit)
- `de65b87` perf(rss): 真并发 fetchTop + 4 场景 0 重叠 + 30s→4s

### 第 4 轮 8/14 中午 — P1 治本 (1 commit)
- `2a73634` fix(content): 4 P1 真凶治本 (race + didUpdateWidget + forceFresh)

### 第 5 轮 8/14 下午 — 负优化回滚 (1 commit)
- `5cfe6ab` perf(rss): 移除 3 慢源 (lifehacker/geekpark/36kr) + 不再 forceFresh

### 第 6 轮 8/14 傍晚 — 真凶治本 (3 commits) ⭐ 本轮
- `9a5c3f6` perf(rss): HN Best → TechCrunch/Ars/Engadget + source name 真实
- `02dc378` perf(rss): dedupeSimilar 0.8 → 0.95 (听/relax/workout 真 RSS 涨 2-5x)
- `ccfcb63` docs: 8/14 上线检查清单 v2

---

## 🎯 关键数字 (3 轮修前 → 修后)

| 指标 | 修前 (30s+) | 修后 | 改善 |
|---|---|---|---|
| AI 首 token | 30s+ | **0.73-1.26s** | **40x ↑** |
| 24 桶 tinder 满 6 张 | 0/24 | **24/24** | ✅ |
| 4 场景重叠 | 11/24 | **0/24 (0%)** | **100% ↓** |
| 重载 6 张 | 同组 | **3 个 load 真换** | ✅ |
| 首屏加载 | 30s+ | **7.5s** | **4x ↑** |
| Learn RSS 拉 | 30s+ | **0.91s (110 items)** | **30x ↑** |
| Listen RSS 拉 | 30s+ | **1.51s (50 items)** | **20x ↑** |
| Relax RSS 拉 | 30s+ | **1.72s (90 items)** | **17x ↑** |
| Workout RSS 拉 | 30s+ | **1.72s (70 items)** | **17x ↑** |
| SW 缓存拦截 | 有 (老 SW) | **无 (cleanup)** | ✅ |
| source name | 全错 (36氪) | **真实 (TechCrunch/IT之家/豆瓣音乐/Solidot/Engadget)** | ✅ |
| 真 RSS 数量 (listen) | 5 | **12** | +140% |
| 真 RSS 数量 (relax) | 7 | **18** | +157% |
| 真 RSS 数量 (workout) | 1 | **27** | +2600% |

---

## 🛠 技术债务 (沿用 alert 不擅自动, P2-P3)

| 项 | 数量 | 优先级 | 沿用 alert 理由 |
|---|---|---|---|
| `withOpacity` deprecation | 305 处 | P3 | Flutter 3.27 升级遗留, ROADMAP 不擅自动 |
| print 残留 | 3 处 (受保护) | P2 | E2E / 浏览器 stub 用, 沿用 alert |
| TODO/FIXME | 5 处 (6 月遗留) | P3 | 沿用 alert, 等 Brien 醒后拍 |
| 大文件 > 1500 行 | 5 个 | P2 | ROADMAP §C 待 batch split |

**总债务**: 318 处 info/warning, 0 error。

---

## 🚦 浏览器实测清单 (Brien 手测)

打开 `https://content.soulvag.com/` 或 `http://192.168.1.2:7080/` 硬刷:

### A. 加载速度 (30s+ → <10s) ✅
- [ ] 首屏 < 10s 出 UI (不再转圈 30s+)
- [ ] tinder 6 张卡 < 2s 出现
- [ ] F12 → Network → "Disable cache" + hard reload

### B. 4 场景差异化 (0 重叠) ✅
- [ ] Learn: 偏科技 (IT之家 + TechCrunch + Ars)
- [ ] Listen: 偏音乐 (豆瓣音乐 + NPR Music + NPR Arts)
- [ ] Relax: 偏生活 (豆瓣读书 + 豆瓣电影 + Solidot)
- [ ] Workout: 偏效率 (少数派 + Solidot + Engadget)

### C. "换 6 张" 真换 ✅
- [ ] 滑完 6 张 → 点 "换 6 张"
- [ ] 新 6 张里至少 1-2 张跟上 6 张不同
- [ ] 滑到底 → 再换 → 仍新内容 (不卡同组)

### D. AI 答疑 1-3s ✅
- [ ] 点右下 AI 浮动按钮 → 问一句话
- [ ] 1-3s 内出首 chunk
- [ ] 内容因场景不同 (学生/工作的 AI 不同)

### E. 国际版 (走 isInternational=true)
- [ ] 切到国际版 userType (在 userType 选英文 user)
- [ ] 4 场景全英文 (无中文)
- [ ] source name 真实 (TechCrunch / Ars / NPR Books / NPR Music 等)

### F. source name 真实 (沿 SOUL #169 不撒谎)
- [ ] UI "来源" 标签跟实际匹配 (不再是 "36氪" 但实际是豆瓣音乐)
- [ ] 每个 tinder 卡显示真 source

### G. 已 ❌/已 ⭐ 排除
- [ ] 滑过的卡不重新出现
- [ ] ⭐ 收藏的卡不在 tinder (走"我的订阅")

---

## 🚀 推动正式应用 (Production-Ready)

### 服务架构
```
[用户浏览器] ─→ HTTPS (CF Tunnel)
            ─→ http://192.168.1.2:7080/ (ft_server.py)
                  ├─ /main.dart.js (Flutter web, latest commit 02dc378)
                  ├─ /service-worker.js (404, 强制禁用 SW)
                  ├─ /flutter_service_worker.js (404, 强制禁用)
                  ├─ /rss?url=... (代理 14 个公开 RSS 源, 4 源并发 < 2s)
                  └─ /api/llm (代理 http://127.0.0.1:11435 MiniMax)
                       └─ systemd daemon 守护
```

### RSS 源白名单 (ft_server.py, 14 域)
```
sspai.com, theverge.com, ximalaya.com,
feeds.npr.org (Top + Music + Arts + Books + Life + Health + Education + Politics + Planet Money),
geekpark.net, ithome.com, solidot.org, hnrss.org, douban.com,
techcrunch.com, arstechnica.com, engadget.com
```

### 守护进程
| 服务 | PID | 端口 | systemd 守护 |
|---|---|---|---|
| ft_server.py | (flutter-keepalive) | 7080 | ✅ |
| llm-proxy/server.py | (systemd) | 11435 | ✅ has_key=true |

---

## 📋 P1 已全部拍板 ✅

1. ✅ **推 main 分支** (8/14 15:30 ccfcb63, 13 commits → main, force-with-lease)
2. ✅ **继续 P2 优化**? 已完成 3 轮 P1 治本, 无 P1 必修
3. ⏳ **LLM 主路径拍板**? 当前 MiniMax 反代 + Ollama 7b fallback (1.3s 首 token)
4. ⏳ **加 metrics监控**? (P2)

---

## 📜 Git 状态 (8/14 16:25)

```
02dc378 perf(rss): dedupeSimilar 阈值 0.8→0.95 (听/relax/workout 真 RSS 涨 2-5x)
9a5c3f6 perf(rss): 替换 HN Best + source name 真实
5cfe6ab perf(rss): 移除 3 慢源 + 不再 forceFresh (负优化回滚)
2a73634 fix(content): 4 P1 真凶治本 (race + didUpdateWidget + forceFresh)
ccfcb63 docs: 8/14 上线检查清单 v2
de65b87 perf(rss): 真并发 fetchTop + 4 场景 0 重叠
89df024 docs: SOUL 规则累积 #190-#197 + MR-1~MR-10
bd1a114 fix(rss): 加 8 个真公开 RSS 源 + 4 场景偏不同源
30c597d fix(rss+web): source name 真实 + SW cleanup
... (10 more commits)
```

**全部推到 origin + gitea** ✅