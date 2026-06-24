# fragment_time 项目宪法

> 这是项目的"底线规则"。任何人/agent 改这个项目之前，先读完这份。
> 6/6 Brien 亲自点头定下的"要保留的项目优点"沉淀在这里。

## 一、原则（最高优先级）

### 1. 版权是命根子
- **所有内容都标注原始来源**，点击跳转原平台
- **不擅自存储或传播受版权保护的内容**（音频、文章正文、图片）
- 可以做的事：聚合、推荐、跳转；不能做的事：抓全文、缓存原片、绕过登录
- 接入新内容源时，第一步先确认：版权清晰吗？能跳转原站吗？

### 1.1 零服务器、零后端、只做收集展示（6/7 Brien 定）
- **核心定位**：fragment_time 是**纯客户端聚合器**——没有自己的服务器
- **不承载**：不缓存内容正文、不存视频文件、不持久化用户浏览历史
- **依赖**：
  - **AI 生成** = 本地 Ollama（NAS 上，不消耗外部，不上传）
  - **视频播放** = B 站/YouTube 官方 embed iframe（**它们自己的服务器承载**）
  - **内容元数据** = 跳转原站（原文在知乎/36氪/喜马拉雅自己的服务器上）
  - **用户状态** = SharedPreferences（**只在用户设备本地**）
- **产品边界**：我们**只展示、不存储、不缓存**
- **设计后果**：
  - ❌ 不做用户账号系统（不存用户数据）
  - ❌ 不做云端推荐（推荐只能本地算）
  - ❌ 不做内容全文搜索（只能拿元数据）
  - ✅ 做小窗视频播放（iframe 0 成本）
  - ✅ 做 AI 流式生成（本地 LLM 0 成本）
  - ✅ 做跨平台跳转（聚合展示的天然延伸）

### 1.2 两个不同概念：「收藏」 vs 「关注」（6/7 命名分离）
- **收藏 (Saved / Bookmarks)** = **对具体内容条目加书签**（AI 生成、视频、文章）
  - 存储：LocalSubscriptionService（**内容 ID + 完整元数据**）
  - 入口：底部"收藏" tab、内容详情页 🔖 按钮、推荐卡 ⭐ 按钮
- **关注 (Following)** = **对平台/类目配置**（知乎、36氪、科技、财经）
  - 存储：SubscriptionService（**平台名 + 类目标签**）
  - 入口：设置 → 关注管理
- **二者关系**：
  - 收藏是**用户的主动选择**（"我想看这篇"）
  - 关注是**用户的偏好配置**（"我想看这类"）
  - **不交叉**——一个内容可以"被收藏"和"符合关注配置"，但**两套独立存储、独立显示**
- **命名规则**：
  - UI 上看到"订阅"这个词时 = **历史遗留**，要改成"收藏"或"关注"
  - 底部 tab = **收藏**（不是"订阅"）
  - 设置项 = **关注管理**（不是"订阅管理"）

### 2. 双版本 + 双语 + 老年模式 是核心定位
- 国内版 (`BUILD_MODE=domestic`) / 国际版 (`BUILD_MODE=global`) **必须都能跑**
- 中/英双语切换是 P0 功能，不是 nice-to-have
- 老年模式（大字体、高对比、操作简化）保留——这个产品名字叫"碎片时间"，老年人是主要用户群之一
- **新功能开发前先想：6 种 user type（学生/上班族/创业者/宝爸宝妈/退休人群/儿童）× 4 种场景（学/听/放松/运动）都覆盖了吗？**
- **术语固定**（6/7 定）：退休人群英文 = `senior`，不用 `retiree`（理由：覆盖更广，retiree 字面"已退休"会排他）

### 4. AI 生成是核心供给，不是装饰（6/7 升 P0）
- **本质定位**：这是个 AI 产品 —— "碎片时间" 5 分钟一单元的密度，**人写不出，AI 是天然供给方**
- **AI 是护城河**：别的聚合 app 护城河是版权（贵、有风险）；我们护城河是 AI 生成（**便宜、零版权、个性化**）
- **自部署优先**：本地 LLM（Ollama）+ 流式输出 → 不联网、不花钱、隐私可控
- **明确标注**：AI 生成的内容**必须**带 "AI 生成" 标识，不假装是真人写的
- **安全约束**（硬规则）：
  - 🚫 不接医疗/法律建议（prompt 里硬约束 + UI 免责文案）
  - 🚫 儿童内容必须有安全过滤（"温柔、安全、适合 6-12 岁"是硬约束）
- **个性化设计**：6 角色 × 4 场景 = 24 种组合，每种都量身生成
- **降级策略**：LLM 失败时降级回 stub（不能让 app 空白）

### 3. 假数据可以上线，真数据要谨慎
- 现在内容是 `_stubDomesticContent` / `_stubIntlContent` 假数据，**这是允许的、可上线的**
- 接真实 API（不是 LLM 生成的）时必须：
  - 区分国内/国际两个 source
  - 失败降级回 stub（不能让 app 空白）
  - 留 `lastFetchedAt` 给后续接 SharedPreferences 用
- **AI 生成内容** 走另一套规则（见 §4），不走"真数据" 范畴

## 二、工程纪律

### 4. Material Icons，**不要 emoji**
- 6/6 教训：emoji 字体在 web 客户端缺失 → UI 看着像白屏
- **所有 icon 一律用 `Icons.xxx`**（参考 `app_theme.dart`）
- 如果发现 `String` 里有 emoji 字符 → 当 bug 处理

### 5. 接口对齐
- 6/6 教训：`main.dart` 用老接口、`screens/` 用新接口 → 7 个编译错误，浪费 Brien 半天
- **改 model / service 接口时必须同步搜**：
  ```
  grep -rn "ClassName" lib/
  ```
- **改完先 `flutter analyze` 再 `flutter build`**

### 5.1 24 桶 ID 命名必须用完整 enum 名（6/8 补充）
- 6/8 教训：intl_service 24 桶 ID 实际用了缩写 `ent_*` / `ow_*`，但字典 key 和 enum 是 `entrepreneur` / `officeWorker` 完整名 → 命名不一致，技术债
- **规则**：任何桶相关 id / key / 文件名 / 变量名，**必须**用 `UserType.name` 完整拼，**不能用缩写**
  - ✓ `intl_student_learn_1`、`entrepreneur_relax`、`parent_workout`
  - ✗ `intl_stu_lrn_1`、`ent_relax`、`pr_wkt`
- 验证方法：
  ```bash
  grep -rE "id: '.*_(ent|ow|stu|teach|ret|com)_" lib/services/
  # 期望：无输出
  ```
- 加新桶时：先看 enum，再 grep 一下全名是否已存在，不重复造轮子

### 6. 发布流程固定走 `build_and_serve.sh`
- **不要手敲** `flutter build` + `python3 -m http.server` 命令行拼
- 6/6 教训：Brien 自己手敲 build + 端口冲突挂掉
- 一条命令 = build + 清 canvaskit/skwasm + patch SW + 重启 server
- 当前 URL：`http://100.89.204.123:9090/`

## 三、协作方式（人 ↔ agent）

### 7. 诊断优先于动手
- Brien 反馈"白屏"/"卡"/"挂了"→ **先复现**（puppeteer 截图 / 看 F12 console / 翻日志）
- 不要立刻改代码、不要立刻换依赖、不要立刻重装

### 8. 不抢用户注意力
- 不要同时搞太多事（环境 + 项目 + 新功能 = 全崩）
- 一个时段只解决 1 个 blocker
- 累了就停，不硬调

### 9. 留痕
- 每天的对话 → 落到 `memory/YYYY-MM-DD.md`
- 关键决策 → 同步进 `MEMORY.md` 长期区
- 改了项目宪法 → 改这个文件，**别动 git 后悄悄改**

### 10. “声/像/能播” 特性要有真验证（6/7 补充）
- 包含 **播放/读取/生成/输出/出声/出图/上传** 语义的功能，**不能仅凭 UI state 切换说“能用”**
- 必须有真证据：
  - **出声** → Brien 真浏览器点播放 + 亲耳听到
  - **出图** → Brien 真看一张生成的图
  - **上传** → 看到网络请求 200 + 服务器接收
- **反面例子**：6/7 TTS 修复前，`_speakWeb` 是 print 假函数，UI 状态（播放/暂停）切得对，但 **0 声**。我以“UI 状态变了 = 响了”蒙骗 Brien。**这是 6/6 教训的复刻**。
- **检测清单**（凡是动这些语义都要逐项走）：
  1. 代码里有没有“假实现”模式？grep `print('` 看是不是只 print 不真调
  2. 有没有 `TODO` / `FIXME` / `// ignore: avoid_print` 作为掩饰？
  3. state 变量（`isSpeaking`、`isPlaying`）有变，**但底层调用能不能独立验证**？
  4. 是不是依赖“推论”而不是“实证”？（“build 过 = 能用” = 推论）
- **验证方法**：
  - **puppeteer 能验的**（DOM / console / 资源加载）：写脚本自动验
  - **puppeteer 验不了的**（声音、图像真感官）：Brien 亲测，记下时间 + 证据
  - **推论验不了**的：老实说“未验证”，不等 Brien 问

## 四、当前已知坑（不要再踩）

| 坑 | 现象 | 解决 |
|---|---|---|
| 9090 端口 | `python3 -m http.server 9090` 重复启动会 EADDRINUSE | 先 `lsof -i:9090` 或用 `.restart.sh` |
| Service Worker 失败 | HTTP 下 SW 注册失败导致 flutter 卡死 | `flutter_bootstrap.js` 末尾 `_flutter.loader.load({})` patch（脚本自动做） |
| canvaskit 太大 | debug 模式 25M | release + HTML renderer → 5.5M（脚本自动做） |
| emoji 字缺失 | UI 看着像白屏 | 全改 Material Icons（参见 §4） |
| emoji 字缺失 | 评论区/按钮里出现 🎧/📰/💬 等 | 改 `Icons.headset` / `Icons.article` / `Icons.chat_bubble` |
| 端口被占 | 443 被 UGOS Pro nginx 占 | tailscale serve 改其他端口或 SSH 反向隧道 |

## 五、改宪法的流程

- **改原则 (§1-§3)**：需要 Brien 明确同意
- **改工程纪律 (§4-§6)**：agent 自己可以改，但要在当日 `memory/` 里记一笔
- **改协作方式 (§7-§9)**：agent 自己可以改，记一笔
- **加坑 (§10)**：谁踩谁加

---

_2026-06-07 由 Brien 点头立宪。小O 起草。_

## 六、未来想做但还没做（备忘，不动 §1-§9）

### 简单模式 vs 完整模式（6/23 23 Brien 提）

**背景**：6/23 Brien 想起可以加"简单模式（功能简单）/完整模式（目前）"。

**理由**：
- 老人/不熟技术用户/第一次用 = 0 步看到内容
- 习惯用 App 的用户 = 现有 5 桶 × 4 scene = 20 桶选
- 现有 user_type_screen 选 userType 是 3 步流程的第一步，决策成本高

**3 个方案 (6/23 推 B)**:
- A) 加 mode toggle - **不推荐**：跟老年模式概念重叠
- B) 改造 user_type_screen = 默认显示时段推荐卡 + 5 桶用 ExpansionTile 默认收起 - **推荐**:
  - 复用 6/23 已做的时段推荐 banner (TimeAwareRecommender)
  - 老人/第一次用 = 0 步看到内容（banner 1 步到位）
  - 熟练用户 = 下拉找完整 5 桶
  - 跟宪法 "老年友好" 定位对齐
- C) 把完整模式藏 Settings 入口 - 备选

**状态** (6/23 20:39 收手)：
- **今晚没动代码**（11.5h 疲劳 + 改 Stateless→Stateful 风险 = 6/16 SOUL 错报事故重演）
- **TODO 明天做**：
  1. user_type_screen 改 Stateful（加 `_showAllTypes` 状态）
  2. 顶部 banner 已经在（TimeAwareRecommender）
  3. 5 桶 GridView 用 ExpansionTile 包裹
  4. 不动 main.dart + 不动 Settings 联动（最小版本）
  5. build 验证后 commit 推上

**SOUL #28 (新增)**：23h 后想做"产品方向"改动，先写宪法备忘，**不动代码**。

---

_2026-06-23 23:00 (Brien 工作 12h 后) 添加。_


### 6.2 多模型 fallback + 分级（6/23 20:52 Brien 提）

**背景**：6/23 20:43 Brien 提"openclaw 用 MiniMax 太耗 token,能不能部署本地模型"。20:52 Brien 点到真问题——**单点失败**："token 限额用完,你就歇菜了"。

**核心**：不是省钱,是 **高可用**。多模型分担 = MiniMax 限额/挂时降级到本地。

**现状 (6/23 20:43 查)**：
- NAS (DXP4800+) = Intel Pentium Gold 8505 (6 核,**无独立 GPU**), RAM 15Gi
- **Ollama 已在跑**（端口 11434）, 5 个本地模型已下：
  - qwen2.5:14b (8.9 GB Q4 量化) - 主力
  - qwen2.5:7b (4.7 GB Q4)
  - deepseek-r1:7b
  - deepseek-r1:1.5b (1.1 GB, 轻量)
  - ollama:latest
- **openclaw 现在用 MiniMax-M3** (从 runtime 看) - 单点
- fragment_time 项目的 `services/llm_service.dart` 已经在用 Ollama (100.89.204.123:11434)
- **NAS 装着的本地模型 0 浪费** (openclaw 没用)

**3 个方案**：

| 方案 | 描述 | 优点 | 缺点 |
|---|---|---|---|
| A. 简单 fallback | MiniMax 失败 → 14B 本地 | 0 改 MiniMax 行为, 高可用 | 本地慢 (Pentium Gold 无 GPU) |
| B. 按任务分级 | 心跳/cron 走 7B 本地 (0 token), 交互走 MiniMax | 真省 token | 7B 处理复杂 bug 排查失忆 (6/22 那种) |
| **C. A + B 组合** | 心跳/cron → 7B, 交互 → MiniMax 优先 + 失败降级 14B | **省 70%+ token + 不停摆** | 配置复杂 |

**推荐 C** (20:52 我推): fallback + 分级 一起上。

**部署方案 (骨架, 6/23 20:52 列, 不动配置)**：

#### 阶段 1: openclaw 配置 fallback 链
- 改 openclaw agentId 模型路由
- 优先 MiniMax-M3 → 失败 → Ollama qwen2.5:14b (127.0.0.1:11434) → 失败 → deepseek-r1:7b
- 测试: 模拟 MiniMax 限额 (用本地 token 烧光) → 自动降级

#### 阶段 2: 任务分级
- **心跳 / cron / "读 + 简单判断"** → qwen2.5:7b (本地, 0 token)
- **交互 (你发的消息) / bug 排查 / 长推理** → MiniMax 优先 + 14B fallback
- 配置: openclaw 的 cron / heartbeat 用独立 agentId, 走本地

#### 阶段 3: 监控
- 跑 1 周看 token 节省多少
- 看哪些任务 7B 跑得好, 哪些必须 14B / MiniMax
- 调优路由

**明天 TODO (6/24)**:
1. [ ] 改 openclaw agentId 模型路由 (找 docs, 不动 MiniMax 默认)
2. [ ] heartbeat / cron 改 7B 本地
3. [ ] 交互 fallback 到 14B (测限额降级)
4. [ ] 跑 1 周看数据
5. [ ] 调优

**风险**：
- **改 openclaw 配置 = 容易改坏** (6/16 SOUL 错报事故根因 = 改一堆没 build)。先 dry-run, 不直接生效。
- 本地模型无 GPU = **推理慢** (Q4 14B 在 Pentium Gold ≈ 5-10 token/s)。简单任务够, 复杂任务会卡。
- 7B 质量降 = 6/22 那种 5 次盲改可能重演（7B 看不懂 box_2d 坐标图）。

**SOUL #29 (新增)**：openclaw 配置改动 = 风险高, **先 dry-run**（不真改, 写新 config 试）, 别直接覆盖现有。

---

_2026-06-23 20:52 (Brien 12h 工作后) 添加。_

