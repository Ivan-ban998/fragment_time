# FragmentTime · 碎片时间

为碎片时间设计的轻量级内容聚合应用。Flutter Web 单仓，覆盖 6 类用户 × 4 种场景 = 24 个内容桶。

## ✨ 特性

- **6 类用户**: 退休 (senior) / 家长 (parent) / 学生 (student) / 上班族 (officeWorker) / 创业者 (entrepreneur) / 儿童 (child)
- **4 种场景**: 学 (learn) / 听 (listen) / 放松 (relax) / 运动 (workout)
- **24 个内容桶** = 6 用户 × 4 场景，**288 条精选内容**
- **真 LLM 兜底** (本地 Ollama qwen2.5:7b) — 30s 内未出首 chunk → 自动降级到预缓存内容
- **玻璃磨砂 UI** (visionOS Liquid Glass 风格)
- **老人模式** (一键放大字号 + 按钮 + 简化动效)
- **场景沉浸背景色** (学蓝紫 / 听青蓝 / 放松绿 / 运动橙)
- **三套主题**: Light / Dark / 暖琥珀护眼 (auto 19:00-7:00)
- **Tinder 风格推荐卡** — ❌ 跳过 / 👆 进详情 / ❤️ 收藏
- **进度追踪** — 阅读进度 + 续读提示 + 已读成就
- **跨设备同步**: 本地 SharedPreferences (未来接云同步)

## 🏗️ 技术栈

- **Flutter 3.5.4** (Dart 3.5.4) — Web 优先 (HTML renderer)
- **LLM**: Ollama qwen2.5:7b (本地, 端口 11434)
- **存储**: SharedPreferences
- **国际化**: 中 / 英 × 国内 / 国际版本

## 🚀 本地启动

```bash
# 1. 安装依赖
flutter pub get

# 2. 构建 + 启动 (单条命令)
bash build_and_serve.sh

# 3. 访问
#   http://127.0.0.1:9090/  (本机)
#   http://192.168.1.20:9090/  (局域网, 前提: NAS/电脑 IP)
```

`build_and_serve.sh` 自动做: build web → 清 canvaskit/skwasm → patch SW → 启 Python http.server

## 🧪 Phase 1 试用指南 (2-3 人试用, 1-2 周)

### 给试用者的 1 页说明

**你是什么**: 为碎片时间设计的轻量级内容聚合应用, 6 类用户 × 4 种场景 = 24 桶

**怎么用**:
1. 浏览器开 **http://192.168.1.20:9090/** (需连与 Brien 同 wifi)
2. 选身份 → 选场景 → 看推荐卡 → 点进读
3. Tab 0 = 首页 / Tab 1 = 搜索 / Tab 2 = 收藏 / Tab 3 = 设置

**核心体验**:
- 🎴 **Tinder 风格推荐**: 左右滑 / 点 ❤️ 收藏 / ❌ 跳过
- 📖 **详情页**: 上滑读全文 / 点右下角听文章 (TTS) / 点 ✨ AI 摘要 / 点 📖 站内读全文
- ⚙️ **设置**: 我的昵称 / 我的身份 / 老人模式 / 主题 / 语言

**发现 bug 请告诉 Brien**:
- 截屏 (问题画面)
- 在哪个 Tab / 点了什么
- 控制台错误 (浏览器 F12 → Console 标签)

### Brien 需要反馈的 5 个问题 (试用 1 周后)

1. **5 角色 × 4 场景都点过没? 哪角色哪个场景错位严重?**
2. **老人模式 1.3x 缩放看得清不?**
3. **推荐准不准? 哪类推荐总是不想看?**
4. **AI 鼓励/名言/摘要 出不出得来?**
5. **站内读全文 (📖 按钮) 是否加载成功?**

### 试用范围内 (不需关注)

- 0 服务器 (LLM 走本地 Ollama, 你家带宽跑)
- 假数据 (288 条手工精校, 不是实时 RSS)
- 仅 LAN 可访问 (公网需 Phase 2 上线 Cloudflare Tunnel)
- TTS 浏览器原生 (部分老人电脑可能不支持)

## 📂 目录结构

```
lib/
├── main.dart                   # 入口 + 主题路由
├── models/
│   └── models.dart             # ContentItem / UserType / Scene
├── services/
│   ├── news_service.dart       # 国内 24 桶假数据
│   ├── international_service.dart  # 国际 24 桶假数据
│   ├── content_aggregator.dart # 统一推荐/搜索入口
│   ├── llm_service.dart        # Ollama 流式 + 兜底
│   ├── user_preference_service.dart  # 行为记录 (view/like/dismiss/save)
│   ├── subscription_service.dart     # 关注 + 进度追踪
│   └── theme_preference_service.dart # ThemeMode + 护眼
├── screens/
│   ├── content_screen.dart     # 推荐流 + LLM 流式
│   ├── search_screen.dart      # 搜索
│   ├── saved_screen.dart       # 收藏 + 关注汇总
│   ├── settings_tab.dart       # 设置 + 关注管理
│   ├── content_reader_screen.dart  # 详情阅读
│   ├── onboarding_screen.dart  # 30s 引导
│   └── ...
├── widgets/
│   ├── tinder_recommendation_stack.dart  # 推荐卡堆叠
│   ├── iframe_video_view.dart            # 视频 (B站/YouTube/跳原站)
│   └── ...
└── theme/
    ├── app_theme.dart          # Material 主题
    └── glass_decoration.dart   # visionOS 玻璃 token

CONSTITUTION.md    # 项目宪法 (3 条核心 + 协作纪律)
ROADMAP.md         # 路线图
```

## 📜 项目宪法

1. **版权是命根子** — 内容源 = 链接跳转, 不下载不二次分发
2. **双版本 × 双语 × 老年模式是定位** — 不简化
3. **假数据可上线, 真数据要谨慎** — 视频接真需要验证

详见 `CONSTITUTION.md`。

## 📄 许可证

MIT — 见 [LICENSE](LICENSE)

免责声明: 本仓库为演示项目, 所有内容链接均指向第三方平台, 不存储不二次分发任何音视频/图文内容。

## 🐙 关于

由 [小O 🐙](https://github.com/openclaw) 协助 Brien 开发, 历时 ~10 天 (2026-06-05 ~ 2026-06-15)。

## 📝 6/30 变更日志 (Brien 接手后)

### 早段 4 轮 AI 位置迭代 (08:42-09:42)
1. ❌ AI 占 Tab 0 (08:42-08:46) — 用户首启卡 AI 助手
2. ❌ AI 挪到 AppBar 按钮 (08:46) — 用户说"AI 不好看"
3. ❌ AI Tab 0 改 5 个 tab 平铺 (09:22) — Tab 错位 (nav 5 vs IndexedStack 4)
4. ✅ AI 改场景页浮动 FAB (09:42) — 工具感, 不抢戏

### AI 智能化 4 件 (12:23-12:42)
- **A 顶部今日总结 banner**: sheet 打开主动提"今天读了 X, 不错"
- **B AI 卡可点跳详情**: 6/29 已实现, audio 跳 reader 跳原文
- **C 3 个上下文建议 chip**: sheet 顶部 AI 推 3 个提问, LLM 失败 fallback 静态
- **D 看完弹 AI 答疑**: content_screen 滚到底 → 1.5s 后弹 sheet (带今日历史)

### Bug 修 (5 件)
- 修"Tab 错位" (nav 5 vs IndexedStack 4)
- 修"刷新页面 AI 名字变默认" (RobotNameService 启动时未拉 prefs)
- 修"LLM 慢手动重试" → 加自动 retry 1 次 (1.5s 后, _llmRetried flag 防死循环)
- 修"答疑历史为空撞 LLM 30s 等" → 直接秒回友好提示
- **修 APK 2 bug**: 名言加 8s 总超时 + 刷新按钮 onComplete 走 globalMainKey._reloadAll (不再调 webForceReload stub)

### 全工程 SnackBar 扫完 (8 屏 20 处)
- 全部改 floating + marginBottom:80, 不挡底部 nav
- 修法: 每个屏加 `_showFloatingSnack` helper

### 清理 + 优化
- onboarding 30s 引导加 DEPRECATED 注释 (已强制跳过, widget 保留)
- debugPrint 21 处全部 catch 兜底类日志, 无残留诊断

### 决策搁置
- E AI 主动推送 (web HTTPS + 跨设备 + 固定时机 ROI 低, 走 D 看完弹已覆盖)

### 11 commit (8 commit 推 + 3 待)
- 703e334 6/30 早段: AI 改浮动 FAB + 3 能力卡做实
- 6b0b68e settings_tab 4 处 SnackBar
- 2c50b44 search + content 5 处 SnackBar
- 1f8fdd6 content_reader 5 处 SnackBar
- f807ecd history/study_group/about/subscription 6 处 SnackBar
- 5e4895d 修 AI 名字刷回默认
- 61952b6 LLM 自动重试 1 次
- 5336926 onboarding DEPRECATED
- edb6a74 答疑空状态秒回
- 9908a81 AI 智能化 3 件 (A banner + D 看完弹 + G 角色)
- f8e9211 AI 智能化 C: 上下文 chip (待推)
- 156113e APK 2 bug 修 (待推)

### SOUL 累积 9 条 (6/30)
- #15 选项 ABC = 累赘
- #30 撂挑子边界 (疲劳时反复劝 = 烧 token)
- #31 改 Tab 顺序 = IndexedStack + nav + _selectedIndex 三件套同步
- #32 SnackBar 默认底部弹挡 nav, 必须 floating + marginBottom
- #33 ValueNotifier 服务必须启动时主动拉 prefs
- #34 onError 自动重试用 Future.delayed + flag 防死循环
- #35 token 含 unicode (如 …) 被 URL encode 断, helper 不读用 URL inline
- #36 历史/数据为空时不调 LLM 走 fallback
- #37 新功能 ROI 评估 4 问
