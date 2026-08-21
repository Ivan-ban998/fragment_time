# FragmentTime — 路线图（6/7 更新版）

> 这是项目的「现在做啥 + 之后做啥」总览。
> 每个时段只做 1 个 blocker，**不抢注意力**（参见 CONSTITUTION.md §6）。

---

## 🅰️ 第一波 — 修 + 收口（✓ 6/7 完成）

| 序 | 任务 | 状态 |
|---|---|---|
| 1 | 修中英 / 国际国内 toggle bug | ✓ |
| 2 | 启动时自动恢复 user type | ✓ |
| 3 | 清 emoji 残留（30+ 处）| ✓ |
| 4 | 合并 2 个 audio service | ✓ |
| 5 | 修 news/intl/sub service 97 个编译错 | ✓ |
| 6 | about_screen 描述对齐 6 角色 | ✓ |
| 7 | 真搜索：SearchScreen 接 content_aggregator | ✓ |
| **+** | 详情页 TTS 播放 + 付费/会员明确提示 | ✓ |
| **+** | 双 ContentItem 模型合并（app_config → models）| ✓ |
| **+** | ContentItem 加 id 字段 | ✓ |

## 🅱️ 第二波 — 接 AI（✓ 6/7 完成）★ P0

| 序 | 任务 | 状态 |
|---|---|---|
| 1 | 修好 llm_service 跑通一次 | ✓ |
| 2 | LLM 接入首页（替换/补充假数据）| ✓ |
| 3 | 儿童内容安全过滤（HARD RULE prompt + UI 标识）| ✓ |
| 4 | AI 精要（TL;DR banner）让用户判断是否继续读 | ✓ |
| 5 | 6 角色 × 4 场景 prompt 补 entrepreneur + child | ✓ |
| 6 | 首页"换一换"按钮（重新生成）| ✓ |
| 7 | "复制"按钮真用 Clipboard.setData | ✓ |
| 8 | 收藏/取消 snackbar 文案 | ✓ |

## 🅱️.2 第二波扩展 — 多形式 + 视频 iframe（✓ 6/7 完成）

| 序 | 任务 | 状态 |
|---|---|---|
| 1 | ContentType 6 形式（article/audio/video/short/card/quiz）| ✓ |
| 2 | VideoPlatform 3 平台 + embedUrl 构造器 | ✓ |
| 3 | IframeVideoView 组件（条件导入 web/stub）| ✓ |
| 4 | 详情页"小窗看 / 跳原站" 双入口 | ✓ |
| 5 | B 站/YouTube 订阅 + stub 内容 | ✓ |
| 6 | 所有列表卡按 contentType 渲染 icon | ✓ |

## 🅱️.3 第二波扩展 — 收藏 vs 关注命名分离（✓ 6/7 完成）

| 序 | 任务 | 状态 |
|---|---|---|
| 1 | 底部 tab "订阅" → "收藏" | ✓ |
| 2 | 设置 "订阅管理" → "关注管理" | ✓ |
| 3 | 宪法 §1.2 立"两个不同概念"原则 | ✓ |
| 4 | 收藏 tab 顶部加关注摘要 banner | ✓ |

## 🅲️ 第三波 — 做厚（部分完成）

| 模块 | 描述 | 状态 |
|---|---|---|
| TTS 朗读（just_audio）| 通勤/健身能听 | ✓ 用浏览器原生 |
| 收藏 / 历史 / 播放记录 | 用户回头找 | ✓ 收藏 + 历史 |
| 每日连击 + 提醒 | 留存 | ✓ 显示在首页 |
| 12 个内容类目订阅 | 现 8 个补到 12 | ✓ 6/8 补齐 + `allCategories` 提到 SubscriptionService 共享，避免漂移 |
| 内容分享（生成卡片图）| 传播 | ✓ 6/8 PictureRecorder + CustomPainter 画 1080×1920 PNG + dart:html Blob 下载。Fallback 复制摘要 |
| PWA / 离线缓存 | 装到桌面、断网能用 | ⚠️ 6/8 做到【半 PWA】: manifest 标题/色 standalone，Icons 齐。HTTPS 不上 → SW + 离线跳；听 Brien 安排上 HTTPS 后再补 |
| 暗色模式优化 | 老人 + 夜猫子 | ⏳ |
| 数据看板（自用）| 看 Brien 自己在用啥 | ✓ 6/8 AnalyticsService + 5 埋点（app_open/user_type/scene/item_open/tts_play/search）+ 设置页入口 + 24 桶组合 top8 |

## 🅳️ 第四波 — 接外部真源（已定：零服务器、只展示）

> 宪法 §1.1：**没服务器、不存内容、只展示**。外部源 = **拿元数据 + 跳原站**，**不缓存任何内容**。

| 候选 | 难度 | 版权风险 | 我的建议 |
|---|---|---|---|
| 知乎热榜 RSS | 低 | 低 | ✓ 优先 |
| 36氪快讯 | 中 | 低 | ✓ 优先 |
| 喜马拉雅专辑 | 中 | **高** | ⏳ 只跳原站，**不缓存音频** |
| **B 站 / YouTube 视频** | 中 | 低 | ✓ **已在 🅱️.2** |
| 小宇宙播客 | 中 | **高** | ⏳ |
| 本地 Ollama LLM | 中 | 零 | ✓ **已在 🅱️** |

**触发条件**：🅱️ 上线后用户反馈"想看真新闻"，再启动 🅳。

---

## 当前判断（6/7 17:30）

- **A + B + B.2 + B.3 全部完成**
- **C 大部分完成**（TTS、收藏、历史、连击）
- **🅳 待启动**（用户先验证主流程）
- **宪法立得稳**（§1.1 / §1.2 / §4 / §5）

---

_2026-06-07 小O 起草。改 ROADMAP 同 §5：要给 Brien 看一眼才能动。_

---

# 📋 **P31 5 TODO 跟踪** (8/28)

下面 5 个 TODO 都不在 P 轮范围,等 Brien 决策:

## 5 个 P31 TODO (8/28 P38 全部完成 ✅)

### 1. `content_reader_screen.dart:149` - LlmService.generateRaw 接入 child HARD RULE
- **现状 (8/28 P38-4)**: ✅ 已治本
  - 加 child HARD RULE: `_inferType() == UserType.child` 走 `_loadSummaryFromBucket` 1桶 (避免 1.5b/7b 输出"5个教育误解"等学生内容)
  - 其他 userType 仍走 `LlmService.generateRaw` 真调 LLM (已实现)
- **状态**: ✅ 8/28 P38-4 完成 (跟 P32-3 1桶优化联合)

### 2. `content_reader_screen.dart:186` - ContentScreen 跳转传 userType+scene 进 widget
- **现状**: ✅ **P32-3 已完成** (1.5s → 0.3s, 5x faster)

### 3. `content_screen.dart:897` - 6/23 LLM 二次调用 (ask "问:...")
- **现状 (8/28 P38-6)**: ✅ 已治本
  - 真调 `LlmService.generateRaw` (15s timeout)
  - prompt 含 `场景: scene.title` + `问题: $picked`
  - 失败 fallback "答: (LLM 暂不可用, 请重试)" (沿 SOUL #169 不撒谎)
- **状态**: ✅ 8/28 P38-6 完成

### 4. `ximalaya_service.dart:173` - iTunes Search API 接入 vs 手动专辑列表
- **现状 (8/28 P38-1)**: ✅ 已治本 — 选 iTunes Search (国际版, 公开 JSON, 不撞宪法 §1.1)
  - `search(keyword, limit=20)` 调 `https://itunes.apple.com/search?term=...&media=podcast&limit=$limit`
  - 返 `List<XimalayaTrack>` (替换 placeholder `List<dynamic>`)
  - 提取 collectionName + feedUrl + trackCount
- **状态**: ✅ 8/28 P38-1 完成

### 5. `ximalaya_service.dart:175` - 留 TODO log
- **现状 (8/28 P38-1)**: ✅ 删 TODO log (search() 真实现, 不再返空)
- **状态**: ✅ 8/28 P38-1 完成

---

**触发机制**: 这些 TODO 等 Brien 拍板 + P 轮 (P32+) 进入。

### 6. **P31-6 跳过**: LLM prompt 缓存
- _buildSystemPrompt + _buildUserPrompt 各仅 2 处调用
- 缓存收益 < 复杂度, 跳过

### 7. **P31-7 跳过**: API key 轮换
- 8/27 Brien 说"先不要管了" (沿用 #188)
- 旧 key 仍在 f5c0ee3 commit info + GitHub events cache
- 等 Brien 拍板

