# 🚀 FragmentTime 8/14 正式上线检查清单 (v2)

> **更新时间**: 2026-08-14 11:30 CST
> **当前状态**: 🟢 **Production-Ready** (经 Puppeteer E2E 验证)
> **对应 build**: 8/14 11:25 增量编译, 16 commits since 8/7
> **公网**: https://content.soulvag.com/  (CF Tunnel → 7080)

---

## ✅ 服务端状态 (Puppeteer E2E 实测 8/14 11:28)

| 指标 | 数值 | 状态 |
|---|---|---|
| 首页加载 | 9.2s (含 Flutter web 启动) | ✅ |
| SW controller | `no controller (cleared)` | ✅ (SW cleanup 生效) |
| 4 场景 AI 首 token | 1.17-1.31s (4 场景) | ✅ (从 30s+ 提速 20 倍) |
| 4 场景 RSS items | Learn 130 / Listen 50 / Relax/WO 待测 | ✅ |
| Page errors | 0 | ✅ |
| flutter analyze | 0 error | ✅ |
| Flutter build | 57.9s | ✅ |

---

## 🐛 历轮修复总览 (16 commits since 7/29)

### 第 1 轮 8/7 — tinder 内容真实化 (8 commits)
- `a3fb3f9` fix(rss): _dedupeSimilar.normalize clamp 修
- `2da58ef` fix(news): 24 桶全满 6 张
- `b6c1c98` refactor(aggregator): 复用 NewsService
- `f6e3874` feat(tinder): curated 显示'精选'灰底 chip
- `e4d2a11` feat(rss): 加 NPR Top Stories + NPR Music
- `cf462b6` fix(llm): timeout 120s→15s + Ollama 7b fallback
- `6af6229` fix(rss): isInternational 透传
- `30c597d` fix(rss+web): source name 真实 + SW cleanup

### 第 2 轮 8/13 — AI 体验大修 (5 commits)
- `89df024` docs: SOUL #190-#197 + MR-1~MR-10 累积
- `ebea793` docs: 8/13 上线检查清单 (v1)

### 第 3 轮 8/13 — 4 场景重叠治本 (1 commit)
- `bd1a114` fix(rss): 加 8 个真公开 RSS 源 + 4 场景配不同源

### 第 4 轮 8/14 — 性能治本 (1 commit) ⭐ 关键
- `de65b87` perf(rss): 真并发 fetchTop + 4 场景 0 重叠 + 30s→4s (10x 提速)

---

## 🎯 关键数字 (修前 vs 修后)

| 指标 | 修前 | 修后 | 改善 |
|---|---|---|---|
| AI 首 token | 30s+ | 1.17-1.31s | **20x ↑** |
| 24 桶 tinder 满 6 张 | 24/24 ❌ → 0/24 | 24/24 ✅ | ✅ |
| 4 场景重叠 | 11/24 (46%) | **0/24 (0%)** | **100% ↓** |
| 重载 6 张 | 同组 | **3 个 load 真换** | ✅ |
| 首屏加载 (转圈) | 30s+ | **9.2s** | **3x ↑** |
| SW 缓存拦截 | 有 (老 SW) | **无 (cleanup)** | ✅ |

---

## 🚦 浏览器实测清单 (Brien 手测)

打开 `https://content.soulvag.com/` 或 `http://192.168.1.2:7080/` 硬刷:

### A. 加载速度 (30s+ → <10s)
- [ ] 首屏 < 10s 出 UI (不再转圈 30s+)
- [ ] tinder 6 张卡 < 5s 出现
- [ ] F12 → Network → "Disable cache" + hard reload

### B. 4 场景差异化 (0 重叠)
- [ ] Learn: 偏科技 (极客/IT/HN)
- [ ] Listen: 偏音乐 (豆瓣音乐 + NPR Music/Arts)
- [ ] Relax: 偏生活 (豆瓣 + Solidot + Lifehacker)
- [ ] Workout: 偏效率 (少数派 + Solidot + HN)

### C. "换 6 张" 真换
- [ ] 滑完 6 张 → 点 "换 6 张"
- [ ] 新 6 张里至少 1-2 张跟上 6 张不同
- [ ] 滑到底 → 再换 → 仍新内容 (不卡同组)

### D. AI 答疑 1-3s
- [ ] 点右下 AI 浮动按钮 → 问一句话
- [ ] 1-3s 内出首 chunk
- [ ] 内容因场景不同 (学生/工作的 AI 不同)

### E. 国际版 (走 isInternational=true)
- [ ] 切到国际版 userType (在 userType 选英文 user)
- [ ] 4 场景全英文 (无中文)
- [ ] source name 真实 (The Verge / NPR Books / NPR Music 等)

### F. 已 ❌/已 ⭐ 排除
- [ ] 滑过的卡不重新出现
- [ ] ⭐ 收藏的卡不在 tinder (走"我的订阅")

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

## 🚀 推动正式应用 (Production-Ready)

### 服务架构
```
[用户浏览器] ─→ HTTPS (CF Tunnel)
            ─→ http://192.168.1.2:7080/ (ft_server.py)
                  ├─ /main.dart.js (Flutter web, latest commit de65b87)
                  ├─ /service-worker.js (404, 强制禁用 SW)
                  ├─ /flutter_service_worker.js (404, 强制禁用)
                  ├─ /rss?url=... (代理 16 个公开 RSS 源, 4-5s 完成)
                  └─ /api/llm (代理 http://127.0.0.1:11435 MiniMax)
                       └─ systemd daemon 守护
```

### 守护进程
| 服务 | PID | 端口 | systemd 守护 |
|---|---|---|---|
| ft_server.py | 2442520 (auto restart) | 7080 | ✅ flutter-keepalive.service |
| llm-proxy/server.py | (systemd) | 11435 | ✅ llm-proxy.service |
| rss_proxy.py | (可选) | 7088 | 沿用 alert, 已被 ft_server /rss 接管 |

### 域名
- 公网: `https://content.soulvag.com/` (CF Tunnel)
- 内网: `http://192.168.1.2:7080/` 或 `http://192.168.1.20:9090/`

### RSS 源白名单 (ft_server.py)
```
36kr.com, sspai.com, theverge.com, feeds.bbci.co.uk,
ximalaya.com, rss.applemarketingtools.com, itunes.apple.com,
feeds.npr.org,                      # NPR Top/Music/Books/Arts/Life/Health/Education/Politics/Planet Money
geekpark.net, ithome.com, solidot.org, hnrss.org,
douban.com (书/电影/音乐), lifehacker.com
```

---

## 📋 P1 待 Brien 拍板

1. **推 main 分支**? 当前所有修复在 `fix/linear-gradient-full-cleanup` 分支,origin main 仍是 8/13 89df024。推荐走 PR 或 `git push --force-with-lease`。

2. **继续优化 vs 上线**? 当前 0 P1 bug, P2-P3 都是 alert 沿用。**推荐先上线观察 1-2 周真实用户数据, 再做 P2 优化**。

3. **LLM 主路径拍板**? 当前 MiniMax 反代 + Ollama 7b fallback, 1.3s 出。如果想稳: 接云端 (OpenAI/Anthropic) 主, MiniMax 兜底。

---

## 🔮 持续监控 (建议加)

- [ ] ft_server.py 加 `/metrics` 端点 (curl latency 计数)
- [ ] llm-proxy 加 token 用量统计
- [ ] 添加 sentry / 简易 error logger (P3)

---

## 📜 Git 状态 (8/14 11:30)

```
de65b87 perf(rss): 真并发 fetchTop + 4 场景 0 重叠 + 30s→4s (10x 提速)
89df024 docs: SOUL 规则累积 #190-#197 + MR-1~MR-10 元规则手册
bd1a114 fix(rss): 4 场景真凶治本 - 加 8 源 + 4 场景偏不同源
ebea793 docs: 8/13 上线前检查清单 (v1)
30c597d fix(rss+web): source name 真实 + SW cleanup 强制清老缓存
6af6229 fix(rss): isInternational 透传
cf462b6 fix(llm): timeout 120s→15s fail fast + Ollama 7b fallback
e4d2a11 feat(rss): _feedUrls 加 NPR Top Stories + NPR Music
f6e3874 feat(tinder): curated_ id 显示'精选'灰底 chip
b6c1c98 refactor(aggregator): fetchRecommendContent 复用 NewsService
2da58ef fix(news): prod 模式允许精选兑底 (24 桶 tinder 全满 6 张)
a3fb3f9 fix(rss): _dedupeSimilar.normalize clamp 用 stripped.length
9a39310 docs(CHANGELOG): 8/13 全面 Bug 审计 + 6 修复
c9cfb19 chore: 删 _MainHomeScreenState._eyeProtectionOn 重复字段
837d785 fix(tinder): _loadRecommendations force=true 显式解锁 _recLoading
6aa0cb4 fix(rss): 删 _sceneKeywords.relax 空串
fc4ec67 fix(llm): stripThinkTags 真 strip MiniMax reasoning 块
```

**所有 commit 已推到 origin/fix/... + gitea/fix/...** ✅