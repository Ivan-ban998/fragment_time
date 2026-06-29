import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/analytics_service.dart';
import '../services/time_aware_recommender.dart';
import '../services/handle_service.dart';
import 'content_screen.dart';
import 'loading_screen.dart';
import 'ai_assistant_screen.dart';

class SceneScreen extends StatefulWidget {
  final UserType userType;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;

  const SceneScreen({
    super.key,
    required this.userType,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
  });

  @override
  State<SceneScreen> createState() => _SceneScreenState();
}

class _SceneScreenState extends State<SceneScreen> {
  String _handle = '@你'; // 6/25 联动昵称

  @override
  void initState() {
    super.initState();
    _loadHandle();
  }

  Future<void> _loadHandle() async {
    try {
      final h = await HandleService().get();
      if (!mounted) return;
      setState(() => _handle = h);
    } catch (_) {}
  }

  UserType get userType => widget.userType;
  bool get isInternational => widget.isInternational;
  bool get isElderlyMode => widget.isElderlyMode;
  String get languageCode => widget.languageCode;

  double get _scale => widget.isElderlyMode ? 1.3 : 1.0;
  bool get isEn => widget.languageCode == 'en';

  @override
  Widget build(BuildContext context) {
    final scenes = isInternational
        ? [
            SceneIntl(Scene.learn, 'Learn Something', 'Progress every day', Colors.blue),
            SceneIntl(Scene.listen, 'Listen', 'Learn while commuting', Colors.purple),
            SceneIntl(Scene.relax, 'Relax', 'Deep breath & unwind', Colors.green),
            SceneIntl(Scene.workout, 'Workout', 'Stretch & move', Colors.orange),
          ]
        : [
            SceneIntl(Scene.learn, '学点东西', '每天进步一点点', Colors.blue),
            SceneIntl(Scene.listen, '听一听', '通勤路上听天下事', Colors.purple),
            SceneIntl(Scene.relax, '放松一下', '深呼吸，放空自己', Colors.green),
            SceneIntl(Scene.workout, '动一动', '告别久坐，活动筋骨', Colors.orange),
          ];

    // 6/25 联动昵称: userTypeName 删了 (AppBar + 欢迎语都改用 _handle)
    return Scaffold(
      appBar: AppBar(
        // 6/27 修: SceneScreen 在首页 Tab 内, 不是独立页 → 不要返回箭头 (6/26 Brien 反馈 12:02)
        automaticallyImplyLeading: false,
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(
          // 6/19 修: 删 userType.icon (IconData 不能跟 String 直接拼接, 6/19 00:16 Brien 反馈 'IconData(U+0E6F2)' bug)
          // 6/25 联动昵称: 用 handle 而不是 userTypeName
          // 6/27 修: AppBar 改回 userTypeName (SceneScreen 是选场景页, 该显角色名, 不是只昵称)
          _getUserTypeName(widget.userType),
          style: TextStyle(fontSize: 18 * _scale),
        ),
        // 6/28 加: 👁 按钮 → LoadingScreen (Brien 6/27 提议"选完兴趣点 → LoadingScreen → SceneScreen")
        // 6/28 Brien 反馈: 保留为 '强行加载刷新' 入口
        //   点 LoadingScreen 开始 → 推回 SceneScreen, SceneScreen 调 ContentAggregator 重新拉推荐池
        actions: [
          IconButton(
            tooltip: isEn ? 'Force reload recommendations' : '强制刷新推荐',
            // 6/29 11:15: 区别于 banner 旁边的紫色 shuffle 按钮 (换名言), 改图标避免跟 “刷”重
            icon: const Icon(Icons.restart_alt),
            onPressed: () {

              // 6/28 Brien 反馈: 保留 LoadingScreen 作为 '强行刷新' 入口
              // LoadingScreen 内部 按 '开始' → ForceReloadSignal.notifyReload() + pop
              // MainHomeScreen._onForceReload 监听到信号后重新拉推荐池
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LoadingScreen(
                    userTypeName: _getUserTypeName(widget.userType),
                    isInternational: widget.isInternational,
                    isElderlyMode: widget.isElderlyMode,
                    languageCode: widget.languageCode,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      // 6/29 段 1: AI 助手悬浮气泡
      // 6/30 00:15: AI 助手挪到 Tab 0 (AiTabScreen), SceneScreen 不再需要 floatingActionButton
      // 6/14 v5.4: 选场景页背景加白叠
      body: Container(
        decoration: BoxDecoration(
          gradient: GlassStyle.sceneBackgroundOverlay(),
        ),
        child: SafeArea(
        child: Padding(
          // 6/29 10:44 Brien 反馈: banner 跟 4 场景卡顶部重叠 — top 加 60 给 banner 让位
          padding: EdgeInsets.fromLTRB(20 * _scale, 60, 20 * _scale, 20 * _scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 6/24 v12: 顶部推荐区 (时段推荐 banner + 今日推荐 hero)
              _TimeRecommendBanner(
                userType: userType,
                scale: _scale,
                isEn: isEn,
                isInternational: isInternational,
                isElderlyMode: isElderlyMode,
                languageCode: languageCode,
              ),
              SizedBox(height: 12 * _scale),
              // 6/24 v12: “现在看什么?” hero 卡
              _TodayPickCard(
                scale: _scale,
                isEn: isEn,
                onTap: () {
                  AnalyticsService.instance.track(
                    AnalyticsService.EVT_USER_TYPE_SELECT,
                    props: {'userType': userType.name, 'source': 'today_pick_scene'},
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ContentScreen(
                        userType: userType,
                        // 6/25 修 bug: 用 userType 推荐的场景 (不传 userType 默认 student)
                        scene: TimeAwareRecommender.recommendAt(DateTime.now(), currentUserType: userType).scene,
                        isInternational: isInternational,
                        isElderlyMode: isElderlyMode,
                        languageCode: languageCode,
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 20 * _scale),
              Text(
                // 6/25 联动昵称: '上午好, @你' 而不是 '上午好, 上班族'
                '${DailyMessage.getGreeting(isEn)} $_handle',
                style: TextStyle(fontSize: 18 * _scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4 * _scale),
              Text(
                isEn ? 'What would you like to do?' : '选择你现在想干嘛',
                style: TextStyle(fontSize: 14 * _scale, color: AppTheme.textLight),
              ),
              SizedBox(height: 16 * _scale),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16 * _scale,
                    crossAxisSpacing: 16 * _scale,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: scenes.length,
                  itemBuilder: (context, index) {
                    final scene = scenes[index];
                    return _SceneCard(
                      scene: scene,
                      scale: _scale,
                      onTap: () {
                        AnalyticsService.instance.track(AnalyticsService.EVT_SCENE_SELECT, props: {
                          'userType': userType.name,
                          'scene': scene.type.name,
                        });
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContentScreen(
                              userType: userType,
                              scene: scene.type,
                              isInternational: isInternational,
                              isElderlyMode: isElderlyMode,
                              languageCode: languageCode,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  String _getUserTypeName(UserType type) {
    switch (type) {
      case UserType.student:
        return isInternational ? 'Student' : '学生';
      case UserType.officeWorker:
        return isInternational ? 'Office Worker' : '上班族';
      case UserType.entrepreneur:
        return isInternational ? 'Entrepreneur' : '创业者';
      case UserType.parent:
        return isInternational ? 'Parent' : '宝爸宝妈';
      case UserType.senior:
        return isInternational ? 'Senior' : '退休人群';
      case UserType.child:
        return isInternational ? 'Child' : '儿童';
    }
  }
}

class SceneIntl {
  final Scene type;
  final String title;
  final String subtitle;
  final Color color;
  const SceneIntl(this.type, this.title, this.subtitle, this.color);
}

class _SceneCard extends StatelessWidget {
  final SceneIntl scene;
  final double scale;
  final VoidCallback onTap;
  const _SceneCard({required this.scene, required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: scene.color.withOpacity(0.1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(12 * scale),
                decoration: BoxDecoration(
                  color: scene.color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(scene.type.icon, size: 32 * scale),
              ),
              SizedBox(height: 12 * scale),
              Text(scene.title, style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w600)),
              SizedBox(height: 4 * scale),
              Text(
                scene.subtitle,
                style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
  );
  }
}

class DailyMessage {
  static String getGreeting(bool isEn) {
    final hour = DateTime.now().hour;
    if (hour < 6) {
      return isEn ? 'Good night' : '夜深了，注意休息';
    } else if (hour < 9) {
      return isEn ? 'Good morning' : '早上好';
    } else if (hour < 12) {
      return isEn ? 'Good morning' : '上午好';
    } else if (hour < 14) {
      return isEn ? 'Good afternoon' : '中午好';
    } else if (hour < 18) {
      return isEn ? 'Good afternoon' : '下午好';
    } else if (hour < 22) {
      return isEn ? 'Good evening' : '傍晚好';
    } else {
      return isEn ? 'Good night' : '晚安';
    }
  }
}

// 6/24 v12: SceneScreen 顶部时段推荐 banner — 按时段推荐一个场景
class _TimeRecommendBanner extends StatelessWidget {
  final UserType userType;
  final double scale;
  final bool isEn;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;

  const _TimeRecommendBanner({
    required this.userType,
    required this.scale,
    required this.isEn,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
  });

  String _sceneLabel(Scene s) {
    switch (s) {
      case Scene.learn: return isEn ? 'Learn Something' : '学点东西';
      case Scene.listen: return isEn ? 'Listen' : '听一听';
      case Scene.relax: return isEn ? 'Relax' : '放松一下';
      case Scene.workout: return isEn ? 'Workout' : '动一动';
    }
  }

  // 6/27 加: AppBar 标题用 (独立于 main.dart 的 _userTypeNameEn/Zh, 避免循环 import)
  // 6/27 删: SceneScreen 已有 _getUserTypeName, 复用就行

  Color _sceneColor(Scene s) {
    switch (s) {
      case Scene.learn: return Colors.blue;
      case Scene.listen: return Colors.purple;
      case Scene.relax: return Colors.green;
      case Scene.workout: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = TimeAwareRecommender.recommendAt(DateTime.now(), currentUserType: userType);
    final color = _sceneColor(rec.scene);
    return GestureDetector(
      onTap: () {
        AnalyticsService.instance.track(
          AnalyticsService.EVT_SCENE_SELECT,
          props: {'userType': userType.name, 'scene': rec.scene.name, 'source': 'time_recommend_banner'},
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ContentScreen(
              userType: userType,
              scene: rec.scene,
              isInternational: isInternational,
              isElderlyMode: isElderlyMode,
              languageCode: languageCode,
            ),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 4 * scale),
        padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(Icons.auto_awesome, size: 14 * scale, color: color),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              isEn
                  ? 'Right now, we recommend: ${rec.label}'
                  : '根据现在的时间，推荐你：${_sceneLabel(rec.scene)}',
              style: TextStyle(
                fontSize: 12 * scale,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isEn ? 'Go' : '去逛逛',
              style: TextStyle(color: Colors.white, fontSize: 11 * scale, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ),
    );
  }
}

// 6/24 v12: 从 user_type_screen 复制过来的 “现在看什么?” hero 卡
class _TodayPickCard extends StatelessWidget {
  final double scale;
  final bool isEn;
  final VoidCallback onTap;

  const _TodayPickCard({
    required this.scale,
    required this.isEn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFC).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.white, size: 28 * scale),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn ? '"What should I read now?"' : '"现在看什么？"',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11 * scale,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    isEn ? 'Tap to start — 5 min story' : '点一下，5 分钟开始读',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8 * scale),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20 * scale),
              ),
              child: Text(
                isEn ? 'Start' : '开始',
                style: TextStyle(
                  color: const Color(0xFF7C5CFC),
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
