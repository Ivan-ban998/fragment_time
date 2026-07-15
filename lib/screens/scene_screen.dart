import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/quote.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_subscription_service.dart';
import '../theme/glass_decoration.dart';
import '../services/analytics_service.dart';
import '../services/time_aware_recommender.dart';
import '../services/handle_service.dart';
import '../services/history_service.dart';
import '../main.dart' as appMain;
import 'content_screen.dart';
import 'loading_screen.dart';
import 'ai_assistant_screen.dart';
import 'about_screen.dart'; // 7/1: AppBar 加反馈按钮

class SceneScreen extends StatefulWidget {
  final UserType userType;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  // 21:00 banner 入参 (从 main.dart 抽过来, 现在 SceneScreen 自己管理 banner 位置)
  final Quote? dailyQuote;
  final String handle;
  final bool isEn;
  final VoidCallback? onTapBannerDetail;
  final Future<void> Function()? onNextQuote;
  final Future<void> Function(Quote)? onSaveQuote;

  const SceneScreen({
    super.key,
    required this.userType,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
    required this.dailyQuote,
    required this.handle,
    required this.isEn,
    this.onTapBannerDetail,
    this.onNextQuote,
    this.onSaveQuote,
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
              // 6/30 13:02 Brien APK bug: 开始按钮点了没反应 — webForceReload 在 APK stub
              // 修: onComplete 走 Navigator.pop + 通过 globalMainKey 调 MainHomeScreen._reloadAll()
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LoadingScreen(
                    userTypeName: _getUserTypeName(widget.userType),
                    isInternational: widget.isInternational,
                    isElderlyMode: widget.isElderlyMode,
                    languageCode: widget.languageCode,
                    onComplete: () {
                      // 6/30 13:02: APK 不走 webForceReload, 走 Navigator.pop + MainHomeScreen reload
                      Navigator.of(context).pop();
                      // 调 MainHomeScreen._reloadAll() 重新拉关注列表 + 每日名言
                      try {
                        final state = appMain.globalMainKey.currentState;
                        if (state != null) {
                          (state as dynamic)._reloadAll();
                        }
                      } catch (e) {
                        debugPrint('[scene] reload failed: $e');
                      }
                    },
                  ),
                ),
              );
            },
          ),
          // 7/1: 反馈按钮 (AppBar 顶部常驻, 用户哪都能反馈)
          IconButton(
            tooltip: isEn ? 'Feedback / Talk to 章鱼' : '反馈 / 跟章鱼说话',
            icon: const Text('🐙', style: TextStyle(fontSize: 20)),
            onPressed: () => AboutScreen.showFeedbackDialog(context, widget.languageCode),
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
          // 21:00 banner 从 main.dart 移入, Padding top 100 → 8 (banner 自己管)
          padding: EdgeInsets.fromLTRB(20 * _scale, 8, 20 * _scale, 20 * _scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 7/15 21:00: 主页 banner (从 main.dart Positioned 移入, 现在是 SceneScreen Column 顶部)
              if (widget.dailyQuote != null && widget.onTapBannerDetail != null)
                DailyEncouragementBanner(
                  text: '',
                  quote: widget.dailyQuote,
                  isEn: widget.isEn,
                  isElderlyMode: widget.isElderlyMode,
                  handle: widget.handle,
                  onTapDetail: widget.onTapBannerDetail!,
                  onNextQuote: () { widget.onNextQuote?.call(); },
                ),
              SizedBox(height: 12 * _scale),
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
              // 6/24 v12: 现在看什么 hero 卡 (7/15 统一间距 12)
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
              SizedBox(height: 16 * _scale),
              // 6/25 联动昵称
              Text(
                '${DailyMessage.getGreeting(isEn)} $_handle',
                style: TextStyle(fontSize: 18 * _scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4 * _scale),  // 7/15: title 跟 subtitle 中间 4px (不让紧贴)
              Text(
                isEn ? 'What would you like to do?' : '选择你现在想干嘛',
                style: TextStyle(fontSize: 14 * _scale, color: AppTheme.textLight),
              ),
              SizedBox(height: 12 * _scale),
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
      // 6/30 09:42: AI 助手浮动按钮 (不占 Tab, 场景页右下角)
      floatingActionButton: FloatingActionButton(
        heroTag: 'ai_assistant_fab',
        backgroundColor: const Color(0xFF7C5CFC),
        tooltip: isEn ? 'AI Assistant' : 'AI 助手',
        onPressed: () async {
          // 6/30 10:11: 答疑需要今日历史, 从 HistoryService 异步拉
          final today = await HistoryService.instance.getAll();
          final now = DateTime.now();
          final todayHistory = today.where((h) {
            final t = DateTime.fromMillisecondsSinceEpoch(h.readAt);
            return now.difference(t).inDays < 1;
          }).toList();
          if (!context.mounted) return;
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            builder: (_) => AiAssistantScreen(
              isEn: isEn,
              isElderlyMode: isElderlyMode,
              userTypeName: _getUserTypeName(widget.userType),
              userType: widget.userType, // 6/30 10:11: 给 LLM 推荐用
              scene: TimeAwareRecommender.recommendAt(DateTime.now(), currentUserType: widget.userType).scene, // 7/1 推荐兑底用
              todayHistory: todayHistory, // 6/30 10:11: 答疑用
            ),
          );
        },
        child: const Icon(Icons.support_agent, color: Colors.white),
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


class DailyEncouragementBanner extends StatefulWidget {
  final String text;
  final Quote? quote; // 7/15: 改 Quote 结构 (text/author/source/createdAt/textEn/authorEn)
  final bool isEn;
  final bool isElderlyMode;
  final String handle; // 6/25: 昵称 (从 HandleService 传入)
  final VoidCallback onTapDetail; // 6/24 v13: 点 banner 弹相关推荐
  final VoidCallback? onNextQuote; // 6/29: 点 "下一个" 按钮
  const DailyEncouragementBanner({
    required this.text,
    this.quote,
    required this.isEn,
    required this.isElderlyMode,
    required this.handle,
    required this.onTapDetail,
    this.onNextQuote,
  });

  @override
  State<DailyEncouragementBanner> createState() => _DailyEncouragementBannerState();
}

class _DailyEncouragementBannerState extends State<DailyEncouragementBanner> {
  bool _saved = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  // 6/29 14:59 Brien 反馈: "已进收藏的爱心还会变空心" — 真凶: didUpdateWidget 里 _saved=false 立即 setState,
  // 但 _loadSaved 是 async, 中间空心帧
  // 修: 不预先 setState(_saved=false), 走 _loadSaved async 查 prefs 后才 setState
  @override
  void didUpdateWidget(covariant DailyEncouragementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quote != widget.quote) {
      _loadSaved();
    }
  }

  // 6/24 v9: 从 SharedPreferences 读今日是否已收藏 (重启后保持 ❤️)
  // 6/25 修 bug: 同时查订阅 list 验证 (双重保险, prefs true 但 list 已删 → 重置 prefs)
  // 6/26: id 从 encourage_ 改 quote_ (banner 现在是名言不是鼓励)
  // 6/29 13:56: 改 key 用 quote text hash — 换名言后状态重置, 不同名言不同 prefs key
  // 7/15: banner 接 Quote? 后 id/prefs key 都用 quote.text.hashCode
  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final quoteText = widget.quote?.text ?? '';
      if (quoteText.isEmpty) {
        if (mounted) setState(() => _saved = false);
        _loaded = true;
        return;
      }
      final key = 'quote_saved_${quoteText.hashCode}';
      final prefSaved = prefs.getBool(key) ?? false;
      bool shouldBeSaved = false;
      if (prefSaved) {
        // 验证 list 里还有这条名言 (防止 prefs true 但 list 已删)
        final id = 'quote_${quoteText.hashCode}';
        final items = await LocalSubscriptionService.instance.getSubscribedItems();
        final exists = items.any((it) => it.id == id);
        if (exists) {
          shouldBeSaved = true;
        } else {
          await prefs.setBool(key, false);
        }
      }
      if (mounted) setState(() => _saved = shouldBeSaved);
      _loaded = true;
    } catch (_) {
      if (mounted) setState(() => _saved = false);
      _loaded = true;
    }
  }

  // 6/24 v6: 收藏鼓励+名言 当一条 ContentItem 到 Tab 2
  // 7/15: title 改作者, source 字段升级 (description 含完整 text + 作者 + 出处)
  Future<void> _onSave() async {
    if (_saved) return;
    final now = DateTime.now();
    final quote = widget.quote;
    if (quote == null) return;
    final quoteText = quote.text;
    final id = 'quote_${quoteText.hashCode}';
    // 7/15: title 改作者名 (不是 "AI 7/15 名言")
    final title = quote.author.isNotEmpty
        ? quote.author
        : (widget.isEn ? 'AI Quote' : 'AI 名言');
    // 7/15: description 放完整 quote + source (后续点击读详情看到)
    final descParts = <String>[quote.text];
    if (quote.source != null && quote.source!.isNotEmpty) {
      descParts.add('《${quote.source}》');
    }
    final desc = descParts.join(' — ');
    final item = ContentItem(
      id: id,
      title: title,
      description: desc,
      duration: widget.isEn ? '1 min read' : '1 分钟阅读',
      source: widget.isEn ? 'Daily Quote' : '每日名言',
      sourceType: ContentSource.rss,
      contentType: ContentType.card,
      lastReadAt: now,
    );
    try {
      await LocalSubscriptionService.instance.subscribe(item);
      if (!mounted) return;
      // 6/24 v9: 持久化已收藏标记
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'quote_saved_${quoteText.hashCode}';
        await prefs.setBool(key, true);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _saved = true);
      // 6/24 v9: 弹 SnackBar + "查看" 按钮 (跳 Tab 2)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEn
              ? 'Saved to Favorites'
              : '已收藏到 “收藏”'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: widget.isEn ? 'View' : '查看',
            onPressed: () {
              appMain.navigateToMainTab(2);
            },
          ),
        ),
      );
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() {});
      });
    } catch (e) {
      debugPrint('banner 保存失败: $e');
    }
  }

  // 7/15: Avatar 圆中显示作者首字符 (中文首字 / 英文首字母)
  String _authorInitial() {
    final a = widget.quote?.author ?? '';
    if (a.isEmpty) return '✦';
    return a.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
    final q = widget.quote;
    final hasQuote = q != null && q.text.isNotEmpty;
    return GestureDetector(
      // 6/24 v13: 点 banner → 弹相关推荐 sheet
      onTap: widget.onTapDetail,
      child: Container(
        // 9:53 Brien 反馈: 刷新按钮被 banner 压住 — 修法: right 多 48dp 给 AppBar actions 让位
        margin: const EdgeInsets.fromLTRB(16, 8, 64, 8),
        padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFC).withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        // 7/15: banner 顶部 avatar (作者首字) + 1-2 行 quote + 小字作者/出处
        child: hasQuote
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44 * scale,
                    height: 44 * scale,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.45), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _authorInitial(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          q.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.98),
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                        ),
                        if (q.author.isNotEmpty || (q.source != null && q.source!.isNotEmpty))
                          Padding(
                            padding: EdgeInsets.only(top: 4 * scale),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    [
                                      if (q.author.isNotEmpty) '— ${q.author}',
                                      if (q.source != null && q.source!.isNotEmpty) '《${q.source}》',
                                    ].join(' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.78),
                                      fontSize: 11 * scale,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _onSave,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: _saved
                                        ? Icon(Icons.favorite, key: const ValueKey('saved'), color: Colors.white, size: 32 * scale)
                                        : Row(
                                            key: const ValueKey('unsaved'),
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.favorite_border, color: Colors.white, size: 32 * scale),
                                              SizedBox(width: 2 * scale),
                                              Text(widget.isEn ? 'Save' : '收藏',
                                                style: TextStyle(color: Colors.white, fontSize: 10 * scale, fontWeight: FontWeight.w500)),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          // 没有作者出处时, 把 ❤ 按钮放这里
                          Padding(
                            padding: EdgeInsets.only(top: 4 * scale),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: _onSave,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: _saved
                                      ? Icon(Icons.favorite, key: const ValueKey('saved'), color: Colors.white, size: 32 * scale)
                                      : Row(
                                          key: const ValueKey('unsaved'),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.favorite_border, color: Colors.white, size: 32 * scale),
                                            SizedBox(width: 2 * scale),
                                            Text(widget.isEn ? 'Save' : '收藏',
                                              style: TextStyle(color: Colors.white, fontSize: 10 * scale, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.format_quote, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
