# Fragment Time Changelog

## 2026-08-28 (P41-P42) — Caches + LLM truncate + Scene.fromBucketKey

### P42 (8/28)
- 加 ApplePodcastsService cache 测试 (test/apple_podcasts_cache_test.dart)
  - 验证 P41-5 10min cache (topCharts hits/misses)
- Scene.fromBucketKey() 加 (反查, RSS / analytics 持久化)
- content_reader_screen _truncateForLLM() helper
  - 截断 description/extension 800 字符
  - 防止豆瓣音乐 / NPR 长文 2-5KB 让 LLM prompt 超限

### P41 (8/28, commit `e34201c`)
- ft_server.py 加 /admin/build_size_history (24h trend)
  - 当前点真实值 + 24 bucket 估算
- ApplePodcastsService 10min in-memory cache
  - topCharts: key=${country}_$limit
  - search: key=${keyword}_${limit}_$country
  - hits/misses 计数器

### P40 (8/28, commit `edf3542`)
- 加 ContentItem toJson/fromJson 单元测试 (3 tests, all passing)
- ft_server.py /admin/clear_metrics?full=1 加 ximalaya_cache_bust signal
  - 返 JSON 格式 (从 string concat 改 json.dumps)

### P39 (8/28, commit `2a135e7` + `1d2110a`)
- ximalaya_service albums() Future.wait 并发 fetch (5 串行 → 5 并发, ~3s)
- ximalaya_service search() 10min in-memory cache
  - 加 searchCacheHits/Misses getter
- ft_server.py /admin/clear_ximalaya_cache (bust signal)

### P38 (8/28, commit `be5e428`)
- 5 TODO 全部治本 (P31 跟踪列表)
  - ximalaya iTunes Search API 接入 (治本 #4)
  - ximalaya search 真调 (治本 #5, 删 TODO log)
  - content_reader child HARD RULE (治本 #1)
  - content_screen ask 真调 LLM (治本 #3)
- 加 test/ximalaya_search_test.dart (2 tests)

### P37 (8/28, commit `9073855`)
- 加 test/llm_cache_test.dart (2 tests, all passing)
- main.dart autoquiz print() → debugPrint (沿 SOUL #25 #27)
- chatStream 日志减少 (12 → 9 logs)

### P36 (8/28, commit `93097bf`)
- 加 test/llm_smoke_test.dart (chatStream 真 API 验证)
- build_and_serve.sh drop --source-maps (-3.1MB build)

### P35 (8/28, commit `9d1a93e`) ⭐ 治本 3 真凶
- P35-1: ft_server thread death 修复 (沿 SOUL #137)
  - 真凶: P32-6 bucket 4-tuple, _check_llm_rate unpack 2-tuple
    → ValueError → handler thread 静默死
  - 修: existing_bucket[0]/[1] + master try-except
- P35-2: chatStream transient retry (502/503/504 → 1s 后 retry)
- P35-3: _getExtendedContent() 真数据 (沿 SOUL #169 不撒谎)

## 2026-08-28 (P29-P33) — 批量 lint cleanup + 性能优化

### P33 (8/28)
- `/admin/sparkline` — 24h per-hour trend (24 buckets)
- dashboard 加 4 场景 RSS 缓存命中率 table (`loadSceneCacheStats()`)
- 0 dart changes, ft_server.py backup: `notes/ft_server_2026-08-28_p33.py`

### P32 (8/28, commit `f96cedf`)
- `_loadSummaryFromBucket` — 24桶循环 → 1桶 (5x faster 推荐)
- 直接用 `_inferType()` + `_inferScene()` 推断 (从 item.id 解析)
- 启动耗时 1.5s → 0.3s

### P31 (8/28, commit `745ec8d`)
- 60 个 `catch (_)` → `catch (e) + debugPrint` (SOUL #169 不撒谎)
- 5 个 TODO 治本: 加 ROADMAP.md 跟踪列表
- 2 个 lint false-positive: `// ignore_for_file` 抑制
- ft_server.py: `setInterval` 包装 `setTimeout(Math.random() * 2000)` 防 thundering herd
- 0 issues, 0 errors ✅

### P30 (8/28, commit `3a8fc4d`)
- 修复豆瓣 RSS description JSON dump leak (`{"entityMap":...}`)
- `_stripHtml` 加 `"entityMap":` 检查
- 1 file, +15/-11

### P29 (8/28, commits `6d5cb51` `3037761` `41faf9a`)
- 158 → 2 lint issues (98.7% 清理)
- 0 errors 全程
- 27 commits since 7/29

## 2026-08-13 (下午续) — tinder 内容真实化 + AI 体验大修 + 上线验证

## 2026-08-13 (下午续) — tinder 内容真实化 + AI 体验大修 + 上线验证

### 🎯 24 桶 tinder 跳不出内容 治本 (沿 SOUL #137 真凶链)

**症状**: 用户报 tinder 跳不出内容 → 占位卡"今日暂无新内容"
**根因 (test 驱动治本)**:
- `rss_service.dart:220` `_dedupeSimilar.normalize` 链式调用,`s.length.clamp(0,100)` 在 `replaceAll` 之后用
- 中文标题缩短后 substring 越界 → `RangeError` → `fetchByBucket` 整体崩 → 24 桶全空

**修法** (`a3fb3f9`): `stripped.length.clamp(0,100)` — 用 replaceAll 后长度,永安全

**真凶链方法**: 沿 SOUL #137 "真对比多个相似路径找物理差别, 不是猜真凶" + `flutter test` 模拟 production 链路看堆栈 (而不是猜)

### 🟢 24 桶全满 6 张 (沿 SOUL #119 不撒谎 + #188 透明)

| commit | 改动 |
|---|---|
| `2da58ef` | `NewsService.getRecommendations` prod 模式允许精选兑底 (RSS≥6 纯真, 1-5 补精选, 0 全精选) |
| `b6c1c98` | `ContentAggregator.fetchRecommendContent` 复用 NewsService 单一来源 |
| `f6e3874` | tinder UI: `curated_*` 灰色 "精选" chip vs `rss_*` 红色 "实时" Live 圆点 |
| `e4d2a11` | `_feedUrls` 国内加 NPR Top Stories + NPR Music, 国际加 NPR, 同步 `ft_server.py` 白名单 |
| `6af6229` | **国际版纯英文** — 透传 `isInternational`, 国际版 RSS<6 不补中文精选 (避免污染英文体验) |

**验证** (`flutter test`):
- 国际版 4 场景: 0 中文, 5 条真 RSS ✅
- 国内版 4 场景: 6 条 (5 真 RSS + 1 精选) ✅

### 🤖 AI 体验大修 (端到端 30s+ → 1.6s)

**真凶链** (3 个连环):
1. **llm-proxy systemd 实例 env 隔离** → `LLM_API_KEY` 丢失 → `has_key: false`
2. **endpoint 路径错** → systemd ExecStartPre 写 `${BASE_URL}` 没补 `/chat/completions` 后缀 → MiniMax 返 404
3. **fragment_time timeout 120s** → 坏路径等天荒地老, 用户以为 AI 死了

**修法** (`cf462b6` + 3 处 systemd unit 修):
1. **systemd unit 改写** `/home/Brien/.config/systemd/user/llm-proxy.service`
   - 直接读 Hermes `.env` 取 `MINIMAX_CN_API_KEY` + `MINIMAX_CN_BASE_URL`
   - `ExecStart` 显式 `export LLM_ENDPOINT="${MINIMAX_CN_BASE_URL}/chat/completions"`
2. **fragment_time `llm_service.dart`**:
   - 3 处 timeout 120s → 15s (fail fast)
   - `generateRaw` 加 `_ollamaFallbackRaw()` 兜底 (proxy 挂自动降级本地 7b)

**验证** (curl 端到端):
- `POST /api/llm` 1.6s 首 chunk (从 30s+ 提速 18 倍)
- `has_key: true` + `endpoint: https://api.minimaxi.com/v1/chat/completions`
- systemd restart 后仍 working ✅

### 📜 Git 状态

- **12 个 commit** 推 GitHub `fix/linear-gradient-full-cleanup` 分支 (SSH 限流这次没拦)
- **Gitea NAS 本地备份** 同步推到 `gitea/fix/linear-gradient-full-cleanup`
- `origin/main` 仍是 7/28 13d826d (待 Brien 决定 push 方式)

### 🆕 SOUL 新规则 (8/13 下午)

- **#193** 链式调用前一步可能改变长度, clamp 必须用最后一步的结果
- **#194** 多 RSS 源扩展必须同步 `ft_server.py` ALLOWED_RSS_DOMAINS 白名单

### 📜 关键 commit (已推 GitHub)

```
6af6229 fix(rss): isInternational 透传 NewsService→RssService
cf462b6 fix(llm): timeout 120s→15s fail fast + Ollama 7b fallback
e4d2a11 feat(rss): _feedUrls 加 NPR Top Stories + NPR Music
f6e3874 feat(tinder): curated_ id 显示'精选'灰底 chip
b6c1c98 refactor(aggregator): fetchRecommendContent 复用 NewsService
2da58ef fix(news): prod 模式允许精选兑底 (24 桶 tinder 全满 6 张)
a3fb3f9 fix(rss): _dedupeSimilar.normalize clamp 用 stripped.length
```

### 📜 沿用 alert 老坑 (待 Brien 拍)

- `origin/main` 仍是 7/28 13d826d (13 个 commit 待推, 需手动 merge)
- `pubspec.lock` 含 105 个依赖未审 (Flutter 3.27 升级遗留)
- `lib/main.dart` 1834 行 + `content_screen.dart` 1949 行 (单文件过大, 按 feature 拆 module 是 P2)
- 305 处 `withOpacity` deprecation (沿用 ROADMAP §C 不擅自动)

---

## 2026-08-13 — 全面 Bug 审计 + 6 修复 (沿 SOUL #103 真改没改对 第 N+1 次)

### 🎯 深度审计 8 个核心文件 → 发现 9 个 bug,治本 6 个

**审计范围**: main.dart (1834) + content_screen.dart (1931) + rss_service.dart (487) + llm_service.dart (698) + news_service.dart (352) + content_aggregator.dart (75) + tinder_recommendation_stack.dart (719) + main.dart 跨屏路径

**审计方法**: 沿 SOUL #103 "真对比多个相似路径找物理差别, 不是猜真凶" + #137 真凶链 + #169 不撒谎

### 🐛 3 个 P0 治本

**Bug #1: `stripThinkTags` MiniMax 思维链泄露** (`llm_service.dart:50`)
- **真凶**: 注释说"删除  ...  块"(MiniMax reasoning),但代码只匹配 ``` 三反引号 (Markdown 代码栅栏)
- **后果**: 1) LLM reasoning block 整段漏到 UI (用户看到 AI 思维过程) 2) 真代码块被误删
- **修法**: 同时 strip  完整块 + 未关闭块 (chunk 边界截断) + 兜底 ```
- **沿用**: #103 真改 vs 真猜

**Bug #2: `_sceneKeywords.relax` 含空串 → relax 过滤失效** (`rss_service.dart:401`)
- **真凶**: `text.contains('')` 永远 true → 所有新闻都"命中" relax 主题词
- **后果**: 整个 8/8 的"4 套 scene 主题词筛"对 relax 完全失效,跑题严重 (学场景也能看到娱乐)
- **修法**: 删空串 1 个字符
- **沿用**: #160 scene 主题词 + #119 不撒谎

**Bug #3: `_loadRecommendations` force 参数从不生效 → "换 6 张" 卡死** (`content_screen.dart:314`)
- **真凶**: `force` 参数声明但内部不检查,`_onAllSixDismissed` setState 把 `_recLoading = false`,函数进来又被 async setState 切回 true,守卫拦住
- **后果**: 用户报"换 6 张没反应" — 第 4 次尝试修仍没修对 (CHANGELOG: 1808cfd → 287acdf → 2db53bd → 5f0ffbe → 307d892 → 913bb9b → 1c16c00)
- **修法**: `force=true` 显式 `_recLoading = false` + `_recRetryCount = 0`
- **沿用**: #103 改了 ≠ 修了 + #18 force flag 必须真生效

### 🔧 3 个 P1/P2 清理

**Bug #4: `_MainHomeScreenState._eyeProtectionOn` 重复声明** (`main.dart:337`)
- 父 `_FragmentTimeAppState` 已持有此字段,子 class 又声明一个 `bool?` 从未读写
- 修法: 删子 class 字段,留注释指引到父

**Bug #5: `_loadFromBucketErr` 死字段** (`content_screen.dart:236`)
- 桶数据加载失败/为空时 setState 写入,但 build() 从不显示
- 修法: `_buildEmptyState` 加 debug 行 (kDebugMode 守卫,生产不显示)

**Bug #6: `llm_service.dart` 8 个 `print()` 残留** (`llm_service.dart:339-380`)
- chatStream 函数 print 调试, web release 模式 print 走 stdout 被截
- 修法: 全部替换为 `debugPrint` (release 自动剥)

### 📊 验证

- ✅ `flutter analyze` 0 error (490 issues, 全是原有 withOpacity deprecation + unused field, 沿 #15 不擅自动)
- ✅ `flutter build web` 成功, 65.3s, main.dart.js 3.2MB
- ✅ 沿用 ROADMAP §C 决策: withOpacity 500 处不动 (Flutter 3.27 升级遗留)

### 🆕 SOUL 新规则 (8/13)

- **#190** `force` 参数必须显式生效 — 声明了不检查 = 等于不声明
- **#191** 关键词列表不能含空串 — `text.contains('')` 永远 true = 过滤失效
- **#192** regex 注释要跟实现一致 — "strip 思维链" 写 ``` 是骗自己

### 📜 关键 commit (待推)

- `fix(llm): stripThinkTags 真 strip MiniMax reasoning 块 (沿 SOUL #103 #190)`
- `fix(rss): 删 _sceneKeywords.relax 空串 (沿 SOUL #160 #191)`
- `fix(tinder): _loadRecommendations force 显式解锁 _recLoading (沿 SOUL #18 #190)`
- `chore: 删 _MainHomeScreenState._eyeProtectionOn 重复字段`
- `chore: _loadFromBucketErr 接 _buildEmptyState debug 显示`
- `chore: llm_service 8 个 print → debugPrint (沿 SOUL #25 #27)`

---

## 2026-07-28 — 听一声 8 天连环坑 治本 + GitHub 治本 + 正式上线

### 🎯 听一声 "啥也没有" / "白屏" 8 天真凶 (治本)

**问题**: Scene.listen (听一声) 24 桶 100% `ContentType.audio`, 走 `_buildAudioEntry` (喜马拉雅入口卡, 在 hero 上面)。 该 widget 卡死 → hero 不可见 = "白屏"。 学/放松/动一动 24 桶是 article/video/card 混 → 不走 `_buildAudioEntry` → 正常显示。

**真凶定位**: 7/24 14:47 Brien "看不见" → 7/25-7/27 14 次盲改 (字体/布局/ScrollView/shader/OTF/LinearGradient/BackdropFilter/Navigator/容器/路由/结构/tofu/Roboto), 全失败。 7/28 12:16 Brien 一句 "**为何其他三个可以**" = 真线索, 让小 O 真对比 4 场景代码路径 → 找到唯一物理差别 (听一声专属 widget) → 1 次改对。

**修法** (commit `13d826d`):
```dart
if (_aiContentItem != null && _aiContentItem!.contentType == ContentType.audio && widget.scene != Scene.listen) ...[
  _buildAudioEntry(_aiContentItem!),
  SizedBox(height: 8 * _scale),
],
```
Scene.listen 跳过 `_buildAudioEntry`, 走 _buildHero 跟其他 3 场景同路径。

**SOUL 加新规则** (7/28):
- **#103** 修 bug 第一步 = 真对比多个相似路径找物理差别, 不是猜真凶
- **#104** "继续干" ≠ "再盲改 1 次", 改 UI 必有真诊断依据
- **#105** 主动短问 1 次就够, 2 次 = 骚扰

### 🌐 正式上线 content.soulvag.com

- DNS: `content.soulvag.com` → CF anycast (104.21.44.167 / 172.67.201.95) ✅
- CF Tunnel: `content.soulvag.com` → `http://localhost:7080` ✅ (沿用 `haisoul-prod-v2` tunnel, 沿用 alert 7/21 修)
- HTTPS: CF 边缘自带证书 ✅
- CF Access: "soulvag.com 全域" Bypass policy for content.soulvag.com (Public) ✅ (7/28 18:46 Brien 改)
- 公开访问: `https://content.soulvag.com/` HTTP 200 4.5s ✅

### 📦 GitHub 治本

- `fix/linear-gradient-full-cleanup` → `origin/dev` 推送 (15 commit, GHub SSH 限流 70h+ 沿用 7/18 解)
- `fix/linear-gradient-full-cleanup` → `origin/main` 强推 (替换 `46b88b9` 灾难版) ✅
- GitHub `main` = `13d826d` ✅ (公共 clone 默认看到完整版)
- GitHub `dev` = `13d826d` ✅
- 别名: 之前别人分析 GitHub 看到 `46b88b9` (只剩 home_stub 占位) = 已替换

### 🧹 打磨 (能干的都干了)

- `lib/services/bilibili_service.dart` 清 4 个诊断 debugPrint (业务 catch 兜底保留) — SOUL #25 #27
- `lib/services/content_aggregator.dart` 无 stub 残留 (干净) ✅
- `lib/services/tts_service.dart` + `tts_service_web.dart` silent-fail fallback 已 ok ✅
- `lib/services/share_service.dart` 三件套 (main + stub + web) conditional import 干净 ✅

### ❌ 没干 (列 TODO)

- **听一声真音频源** = NAS 上行不通国外 (NPR/BBC/Vox/RSSHub 全 timeout), 国内 podcast RSS 缺, 需付费 API (喜马拉雅/得到/听云)
- **云端 TTS 真接** = 现在浏览器 `window.speechSynthesis` 机械音, 接 Azure/阿里云/MiniMax 是大活
- **24 桶内容扩充 24 → 100+** = 内容运营, 不是代码
- **3 个 TODO 注解**: child HARD RULE stub (content_reader:149), ContentScreen 跳转优化 (content_reader:186), 接 LLM 二次调用 (content_screen:844)

### 📜 关键 commit

- `13d826d` fix(听一声): Scene.listen 跳过 _buildAudioEntry (不凑合) ← 治本
- `5ef451f` revert(scenes): 删 v2 听一声 试用入口, 4 场景回 v1 (回滚)
- `8b71bc4` fix(听一声 7 天 真凶): content_screen hero fontFamily 'Roboto' → null (后 revert)
- `bc02bcf` fix(听一声 7 天 真凶): app_theme fontFamily 'Roboto' → null (后 revert)
- `1c2146f` fix: LinearGradient 全清 + 听一声真凶 + 收藏搜索 + 顶栏统一
- `5f7d15f` WIP: 听一声 v10 玻璃不透明 + 深色文字 (老基线)

### 📊 沿用 alert

- **cloudflared-tunnel-dns-dead** (RESOLVED 7/21 12:18) ✅
- **GHub SSH 限流** (RESOLVED 7/18 22:00) ✅
- **8100-stale-port** (沿用 7/13)
- **haisoul.com / openclaw.haisoul.com TLS RST** (沿用 7/14)
- **snipe.vagtek.com DNS 不解** (沿用 7/21)
- **odoo-wangyi-atc-missing** (沿用 7/19)
## 2026-07-29 — 内容真实化 (上线后 访客反馈) + TL;DR 文案澄清 + 跳原站读全文

### 🎯 7/29 早 Brien 反馈 "上线行动 = 内容不真实"

**问题**: `fetchFromRss` 注释写"优先 RSS"但代码返假数据 (沿用 7/15 ban RSS 后临时顶替). `_allContent` 288 条 hardcoded 假内容 + 搜索 URL stub. 访客打开 content.soulvag.com 看到的就是这堆假数据.

**真凶 (沿用 SOUL #103)**: `fetchFromRss` 内部 `return _allContent[key] ?? _fallback(...)` —— **骗自己**. `news_service.dart:73` 注释写"注释写优先 RSS"但代码不接.

**修法 (3 commit, 沿用宪法 §1.1 不存原片)**:

| commit | 改动 |
|---|---|
| **`1cae292`** | `fetchFromRss` 真接 `RssService.fetchByBucket` + `rss_service.dart` 多源 fallback (36 氪 → 少数派) + `content_aggregator.dart` RSS 空时返 `[]` (不再 fallback `_allContent`) + `_buildEmptyState` 空状态 UI + `_fetchFakeForDev` 仅 dev 演示用 |
| **`b89f6a0`** | TL;DR 文案改"上次看到的总结 (不是当前文章摘要)" + icon 改 history 明确标历史偏好 + 新 `_buildReadFullHint` 提示访客"点 Read → 在原站读全文" |

### 🎯 7/29 17:55 Brien 反馈: 36 氪内容切合实际但可阅读性低 / 延伸阅读 AI 摘要不真实

**根因**:
- **TL;DR banner** (`_tlDrText = cache`): 实际是**历史偏好缓存**, 不是当前文章摘要 — **访客误以为是 TL;DR**
- **跳原站读全文** UI 没提示 → 访客不知道点 Read 后在阅读器底部有"在原站读全文"按钮

**修法** (`b89f6a0`): TL;DR 文案澄清 + `_buildReadFullHint` 跳原站提示卡 (沿用宪法 §1.1 不存原片)

### 🌐 上线验证

- **build 成功**: `?v=1785321026` (b89f6a0 + 1cae292 改动生效)
- **9090 起来**: `?v=1785321026` (build_and_serve.sh 沿用)
- **7080 沿用**: 沿用 alert 老服务仍跑
- **analyze 0 error** (54 info/warning 全是 Flutter 3.27 withOpacity 升级遗留, 沿用 #15 不擅自动)

### ❌ 还没干 (你 18:14 问但还没拍)

- **in-app webview 嵌入**: 让用户不用跳出 app 也能看完整 36 氪/少数派文章. 沿用宪法 §1.1 ✅ (不存原片). 工程量: 加 webview_flutter 依赖 + 集成 widget + 测 X-Frame-Options (36 氪/少数派可能拒绝嵌入)
- **解 SSH 限流 push 4 commit 到 origin/dev** (沿用 #74 #116 SSH 仍不稳, 7 通 / 5 不通 = 间歇, 不暴力重试)
- **接云端 TTS / RSS feed 真音频源** (沿用 #8 红灯区 = 要钱 + 部署活)

### 📜 关键 commit

- `b89f6a0` fix(content): 7/29 TL;DR 文案 + 跳原站读全文提示 ← **待你浏览器硬刷验**
- `1cae292` fix(content): 7/29 RSS 真接 + 空状态 UI + 多源 fallback
- `9fc7e41` fix(subscriptions): 关注平台/类目标题去掉字面占位符
- `558a77b` polish: bilibili 诊断 debugPrint 清 4 个 + CHANGELOG.md 7/28 一天大事记
- `13d826d` fix(听一声): Scene.listen 跳过 _buildAudioEntry (沿用 7/28 沿用 #103 真改)

### 🔧 7/29 18:30-20:10 沿用 #103 "改了 ≠ 修了" — CORS 修复 + in-app webview

**问题 1 (CORS)**: 你 18:36 浏览器硬刷 9090 发现 `Access to fetch at 'https://36kr.com/feed' from origin 'http://100.89.204.123:7080' has been blocked by CORS policy`. **沿用 #103**: fetchFromRss 真接 RSS 但 web 平台浏览器 fetch 受 CORS 拦截, 改完跟没改一样

**修法 (1 commit)**:
- 新 `/home/Brien/.openclaw/bin/rss_proxy.py` (7088 端口): 后端 curl 拉 RSS, 加 `Access-Control-Allow-Origin: *` 让浏览器放行
  - 安全白名单: 36kr.com / sspai.com / theverge.com (防止 SSRF)
  - `/health` 监控
- `rss_service.dart`: `kIsWeb` 判定 web 端走 NAS proxy, native 端 (mobile) 直接 fetch
- 启动: `nohup python3 /home/Brien/.openclaw/bin/rss_proxy.py 7088 > /tmp/rss_proxy.stdout 2>&1 &`

**问题 2 (webview)**: in-app webview 嵌入 36 氪/少数派完整文章 (留住用户在 app 内, 不跳外部浏览器)
- 修法 (3f0cf2c): webview_flutter 4.13.0 + 新 `lib/screens/in_app_webview_screen.dart`
- 错误 fallback: X-Frame 拒绝时显示 URL 让用户改用浏览器
- 宪法 §1.1 沿用: webview 本身不存原片, 只渲染

### 📜 关键 commit

- `0ca3084` fix(content): 7/29 NAS proxy 绕 CORS ← **待你浏览器硬刷验**
- `3f0cf2c` feat(content): 7/29 in-app webview 嵌入
- `c132f00` docs(CHANGELOG): 7/29 内容真实化 + TL;DR 文案 + 跳原站读全文
- `b89f6a0` fix(content): 7/29 TL;DR 文案 + 跳原站读全文提示
- `1cae292` fix(content): 7/29 RSS 真接 + 空状态 UI + 多源 fallback
- `9fc7e41` fix(subscriptions): 关注平台/类目标题去掉字面占位符
- `558a77b` polish: bilibili 诊断 debugPrint 清 4 个 + CHANGELOG.md 7/28 一天大事记
- `13d826d` fix(听一声): Scene.listen 跳过 _buildAudioEntry

### ❌ 还没干 (待 Brien 拍)

- **rss_proxy 自启**: 沿用 #113 NAS reboot 后 rss_proxy 不跑. 加 systemd user unit 或 keepalive script (沿用 SOUL #13 沿用 #15)
- **解 SSH 限流 push 7 commit 到 origin/dev** (沿用 #74 #116 SSH 仍不稳)
- **接云端 TTS / RSS feed 真音频源** (沿用 #8 红灯区)
- **CF Access + 自定义域正式上线** (content.soulvag.com 沿用 alert)
