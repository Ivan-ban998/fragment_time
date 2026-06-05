# FragmentTime

> 碎片化时间管理助手 - 国内版

Flutter Web 应用，帮用户在通勤、排队、休息等碎片化时间里高效消费优质内容。

## 功能特性

- 🏠 **多角色场景**：通勤、午休、睡前、运动、摸鱼五大场景
- 📰 **内容聚合**：新闻、播客、国际资讯一站式
- 🎨 **卡片式 UI**：Material Design 3 风格
- ⚡ **Flutter Web**：浏览器即开即用，端口 9090

## 技术栈

- **Flutter** 3.24.5
- **Dart** 3.x
- **Material Design 3**
- 部署目标：Web (Chrome/Edge)

## 项目结构

```
lib/
├── main.dart                  # 入口
├── models/                    # 数据模型
├── screens/                   # 页面
│   ├── user_type_screen.dart  # 角色选择
│   ├── content_screen.dart    # 内容流
│   ├── search_screen.dart     # 搜索
│   ├── podcast_screen.dart    # 播客
│   └── settings_tab.dart      # 设置
├── services/                  # 服务层
│   ├── news_service.dart
│   ├── international_service.dart
│   ├── podcast_service.dart
│   ├── audio_player_service.dart
│   ├── audio_play_service.dart
│   └── ximalaya_service.dart
└── theme/                     # 主题
test/                          # 测试
```

## 本地运行

```bash
flutter pub get
flutter run -d web-server --web-port 9090 --web-hostname 0.0.0.0
```

浏览器打开 http://localhost:9090

## 部署路径

NAS 部署：`/volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time`

## 路线图

- [ ] 真实接口对接（新闻/播客 API）
- [ ] 用户系统
- [ ] 内容个性化推荐
- [ ] 移动端打包（iOS / Android）
- [ ] 离线缓存

## License

MIT
