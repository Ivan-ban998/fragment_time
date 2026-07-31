# MiniMax H3 名言"15s 视频解读" P0 Demo Plan

> 7/31 立项,Brien "都要干"。沿用 SOUL #6 #8 (能跑起来 > 等完美)。

## 目标
fragment_time 名言 Tab-收藏 → 任意名言 → 在"延伸思考"卡片下,加 1 个 "AI 解读视频" 卡片。
点 → 调 MiniMax H3 API 生成 15s 视频(苏轼定风波 → 山雨意境画面 + 原文朗读)

## 为什么接 H3
- 名言 text 30-100 字,H3 Caption 100K → 4K Token 完全 cover
- 15s 视频适合 "碎片时间"消费,跟 fragment_time 产品定位合
- 双声道原生音视频 = 文本朗读 + 背景音乐(可省 TTS 步骤)
- 商用级多场景,落广告/UI 真能用

## 不接什么(沿用 #113 沿用 #15)
- 不接 H3 的"多模态理解"部分(7b 已能做)
- 不接 H3 V2V 动作迁移(fragment_time 暂不需要)
- 不动 NAS ollama 7b (H3 是云端 API)

## 技术方案

### 1. UI 卡片 (沿用 #6 #8 简化)
- 在 `_QuoteExtendedSection` 之后,加 `_QuoteH3VideoSection`
- 显示: 占位灰卡 + "🎬 AI 解读视频 (15s) — 点击生成" 按钮
- 用户点击 → 调 API → 显示 loading → 返视频 embed (或跳 YouTube/B站类似占位)

### 2. API 接入 (沿用 #117 rss_proxy 模式)
- NAS 写 1 个 `h3_proxy.py` 后端代理:
  - listen 0.0.0.0:7089
  - POST /generate { quote_text, author, source, language }
  - 内部调 MiniMax H3 API (web → proxy → H3)
  - 缓存: 已生成的名言放 NAS `/volume1/.../cache/h3/{quote_hash}.mp4`
  - 安全白名单: MiniMax API endpoint only, 防止 SSRF

### 3. MiniMax H3 API key 管理 (沿用 #113 不可逆公开配置)
- key 存 `/home/Brien/.openclaw/secrets/h3_api_key` (root only, 沿用 6/24 划线)
- proxy 启动时读, 不硬编
- proxy 自己加 keepalive cron (沿用 #118 #13)
- **等 Brien 拍: 是否真的接 H3 API key?**
  - 选项 a: 用 MiniMax 当前 Token Plan (跟 keep_alive_ollama 同一个 key)
  - 选项 b: 单独买 H3 配额 (不知价)
  - 选项 c: 先 mock 后端 (返个占位 mp4), 不真接 API

### 4. Flutter web 调用
- `llm_service.dart` 加 `h3GenerateVideo(quoteText, author)` 
- 走 http post → 127.0.0.1:7089/generate → 返 mp4 url
- embed: video_player 或 IframeVideoView (沿用 7b/36氪 iframe)

## 阶段 (沿用 #6 #8)

### Phase 1 (今天,1-2h): plan + 设计 + 卡片 UI 占位
- ✅ 已写本 plan
- 加 `_QuoteH3VideoSection` 占位卡片 (不调 API)
- 显示 "🎬 视频解读即将上线"

### Phase 2 (等 Brien 拍 API key 后): proxy + 真接 H3
- 写 h3_proxy.py 后端
- 写 keepalive cron
- 接 MiniMax H3 API

### Phase 3 (1-2 周): P0 demo 上线
- 苏轼《定风波》→ 山雨 + 15s 视频 demo
- A/B 测 5 个不同作者的名言
- 收集用户反馈

## 风险 (沿用 #107)

1. **API key 配额** — H3 单次 100K Token,1 个 15s 视频估消耗 ~1 元 (估, 等 Brien 拍)
2. **生成时长** — H3 估 30-60s (15s 视频), 比 7b 慢, UI loading 必须做
3. **NAS 缓存** — 视频 5-10MB/条, 100 条名言 = 1GB, 沿用 #44 #112 必先问
4. **代理端口冲突** — 7089 跟现有 7088/7080/7090 都近, 需 `lsof -i :7089` 验

## 沿用 SOUL
- #6 #8 能跑起来 > 等完美
- #113 不可逆公开配置 → 等 Brien 拍 key
- #117 沿用 rss_proxy 模式 (proxy + keepalive + 白名单)
- #74 #116 沿用,不擅自调 API
- #44 #112 cache 路径先问