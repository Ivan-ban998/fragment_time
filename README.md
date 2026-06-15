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
