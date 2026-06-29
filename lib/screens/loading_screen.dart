import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/glass_decoration.dart';
import '../services/news_service.dart';
import '../services/local_subscription_service.dart';
import '../services/llm_service.dart';
import '../models/models.dart';
import '../main.dart' as appMain;

// 6/28 加: SceneScreen '强制刷新' 信号
// LoadingScreen 开始 → SceneScreen 收到信号 → 调 ContentAggregator 重新拉推荐池
class ForceReloadSignal {
  static final ValueNotifier<int> _notifier = ValueNotifier<int>(0);
  static ValueNotifier<int> get instance => _notifier;
  static void notifyReload() => _notifier.value++;
}

/// LoadingScreen — 选完兴趣点后, 真加载场景主页前的过渡页
///
/// 6/27 加: Brien 提议 — 在 TopicOnboardingScreen → SceneScreen 中间插入一页
///   1) 问候语 (按 userType + time)
///   2) 后台预热 NewsService / LlmService / LocalSubscriptionService / HandleService
///   3) "开始"按钮 → 跳 SceneScreen (IndexTab 0)
///
/// 6/28 Brien 反馈: '加那个, 一是仪式感, 二是后台加载出正确完整页面'
///   → 接上真实业务: 4 步骤对应 NewsService.preheat / LlmService.keepAlive /
///     LocalSubscriptionService / _loadDailyQuote, 每个步骤完成后 setState done
///   → 超时兑底: 4s 后就算某步未完也允许 '开始'
class LoadingScreen extends StatefulWidget {
  final String userTypeName;       // '上班族' / 'Student'
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final bool isEntryRoute;         // 6/28: true = 首启 pushReplacement 进来, false = SceneScreen 内按钮
  final VoidCallback? onComplete;  // 6/28 19:59: MainHomeScreen 传 callback, 不靠 globalKey

  const LoadingScreen({
    super.key,
    required this.userTypeName,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
    this.isEntryRoute = false,
    this.onComplete,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressCtrl;
  double _progress = 0;
  late List<_LoadingTask> _tasks;

  @override
  void initState() {
    super.initState();
    _initTasks();
    _startLoading();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(() {
        setState(() => _progress = _progressCtrl.value);
      });
    _progressCtrl.forward();
  }

  // 6/28 启动 4 步真业务加载 + 4 秒超时兑底
  void _startLoading() {
    final isEn = widget.isInternational;
    final userTypeName = widget.userTypeName;
    // 1) NewsService 预热 24 桶
    () async {
      try {
        await NewsService().preheatAll();
        _markDone(0);
      } catch (e) {
        debugPrint('[loading] NewsService preheat 失败: $e');
        _markDone(0); // 失败也走, 不卡
      }
    }();
    // 2) LLM keep_alive — 发个轻量请求让模型加载到内存
    () async {
      try {
        // 轻量 prompt: 调一下服务, 让 keep_alive 生效
        final buffer = StringBuffer();
        await for (final _ in LlmService.generateStream(
          userType: _userTypeFromName(userTypeName),
          scene: Scene.learn,
          languageCode: widget.languageCode,
          isInternational: isEn,
        ).timeout(const Duration(seconds: 3), onTimeout: (sink) {
          sink.close();
        })) {
          buffer.write(_);
        }
        _markDone(1);
      } catch (e) {
        debugPrint('[loading] LLM keep_alive 失败 (兑底): $e');
        _markDone(1);
      }
    }();
    // 3) LocalSubscriptionService 预热 — 拉关注列表
    () async {
      try {
        await LocalSubscriptionService.instance.getSubscribedItems();
        _markDone(2);
      } catch (e) {
        debugPrint('[loading] LocalSubscription 失败: $e');
        _markDone(2);
      }
    }();
    // 4) 今日推荐 — 拉 4 场景初始推荐 (SceneScreen 进 Tab 0 后才显示)
    () async {
      try {
        // 预拉当前 userType + 4 场景的推荐, 缓存进 memory
        final u = _userTypeFromName(userTypeName);
        for (final s in Scene.values) {
          await NewsService().getRecommendations(u, s);
        }
        _markDone(3);
      } catch (e) {
        debugPrint('[loading] Today picks 失败: $e');
        _markDone(3);
      }
    }();
    // 4 秒超时兑底: 任何未完步骤设 done=true, 让用户能点 '开始'
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      for (var i = 0; i < _tasks.length; i++) {
        if (!_tasks[i].done) {
          _markDone(i);
        }
      }
    });
  }

  // 把 userTypeName 字符串转回 enum (LoadingScreen 只接了 name)
  UserType _userTypeFromName(String name) {
    return UserType.values.firstWhere(
      (t) => t.title == name || t.name == name,
      orElse: () => UserType.officeWorker,
    );
  }

  // 单个任务完成后改 done 状态
  void _markDone(int index) {
    if (!mounted) return;
    setState(() {
      _tasks[index].done = true;
      // 进度条以 done 任务为准, 不以 AnimationController 为准
      final completed = _tasks.where((t) => t.done).length;
      _progress = completed / _tasks.length;
    });
    // 如果全部完成, 跳 _progressCtrl.stop() 让动画停在 100%
    if (_tasks.every((t) => t.done) && _progressCtrl.isAnimating) {
      _progressCtrl.stop();
      _progressCtrl.value = 1.0;
    }
  }

  // 提取: 任务列表初始化 (6/28 重构, 从 field initializer 挪出来避免访问 widget)
  void _initTasks() {
    final isEn = widget.isInternational;
    _tasks = [
      _LoadingTask(
        isEn ? 'Content ready' : '内容加载完成',
        isEn ? '24 categories primed' : '24 个类目就绪',
        0.25,
      ),
      _LoadingTask(
        isEn ? 'AI warmed up' : 'AI 准备就绪',
        isEn ? 'Smart summary ready' : 'AI 摘要可用',
        0.25,
      ),
      _LoadingTask(
        isEn ? 'Your follows' : '关注列表',
        isEn ? 'Loaded from device' : '已从本地读取',
        0.25,
      ),
      _LoadingTask(
        isEn ? 'Today\'s picks' : '今日推荐',
        isEn ? 'Fresh content mixed in' : '新内容已混入',
        0.25,
      ),
    ];
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    final isEn = widget.isInternational;
    if (h < 5) return isEn ? 'Still up?' : '夜深了';
    if (h < 9) return isEn ? 'Good morning' : '早上好';
    if (h < 12) return isEn ? 'Good morning' : '上午好';
    if (h < 14) return isEn ? 'Good afternoon' : '中午好';
    if (h < 18) return isEn ? 'Good afternoon' : '下午好';
    if (h < 22) return isEn ? 'Good evening' : '晚上好';
    return isEn ? 'Good night' : '夜深了';
  }

  String _emoji() {
    final h = DateTime.now().hour;
    if (h < 6 || h >= 22) return '🌙';
    if (h < 12) return '☀️';
    if (h < 18) return '🌤️';
    return '🌆';
  }

  @override
  Widget build(BuildContext context) {
    final isEn = widget.isInternational;
    final scale = widget.isElderlyMode ? 1.3 : 1.0;

    return Scaffold(
      // 6/28 Brien 反馈: '页面总是黑黑的, 深色模式, 永远' (即使 WelcomeScreen 白 background, SceneScreen / LoadingScreen 在 dark theme 下 还是 dark)
      // 真凶: sceneBackgroundOverlay 只叠 0.18 白, dark theme 下 surface 近黑, 叠上去还是近黑
      // 修: LoadingScreen 是独立的过渡页, 直接强制 light 背景 (不等 theme)
      backgroundColor: const Color(0xFFF8F6FC),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              const Color(0xFFF8F6FC),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 40 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 40 * scale),
                // 问候语
                Text(
                  '${_emoji()}  ${_greeting()},',
                  style: TextStyle(
                    fontSize: 18 * scale,
                    color: GlassStyle.onGlassSecondary,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Text(
                  widget.userTypeName,
                  style: TextStyle(
                    fontSize: 36 * scale,
                    fontWeight: FontWeight.w800,
                    color: GlassStyle.onGlassPrimary,
                    height: 1.2,
                  ),
                ),
                Text(
                  isEn ? 'Preparing your day...' : '准备你的一天...',
                  style: TextStyle(
                    fontSize: 16 * scale,
                    color: GlassStyle.onGlassSecondary,
                  ),
                ),
                SizedBox(height: 48 * scale),

                // 进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 10 * scale,
                    backgroundColor: GlassStyle.onGlassSecondary.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation(GlassStyle.onGlassPrimary),
                  ),
                ),
                SizedBox(height: 24 * scale),

                // 后台任务清单
                Expanded(
                  child: ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (ctx, i) {
                      final t = _tasks[i];
                      final done = _progress >= t.weight * (i + 1);
                      return Padding(
                        padding: EdgeInsets.only(bottom: 16 * scale),
                        child: Row(
                          children: [
                            Icon(
                              done ? Icons.check_circle : Icons.circle_outlined,
                              size: 22 * scale,
                              color: done
                                  ? GlassStyle.onGlassPrimary
                                  : GlassStyle.onGlassSecondary.withOpacity(0.5),
                            ),
                            SizedBox(width: 12 * scale),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.label,
                                    style: TextStyle(
                                      fontSize: 15 * scale,
                                      fontWeight: FontWeight.w600,
                                      color: GlassStyle.onGlassPrimary,
                                    ),
                                  ),
                                  Text(
                                    t.detail,
                                    style: TextStyle(
                                      fontSize: 12 * scale,
                                      color: GlassStyle.onGlassSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // 开始按钮: 点了之后跳 SceneScreen + 调 ContentAggregator / SubscriptionService 重新拉
                SizedBox(
                  width: double.infinity,
                  height: 56 * scale,
                  child: ElevatedButton(
                    // 6/29: onPressed 跟 _progress 解耦, 用 _tasks 全 done 判定 (AnimationController 会覆盖 _progress)
                    onPressed: _tasks.every((t) => t.done)
                        ? () {
                            if (widget.isEntryRoute) {
                              // 首启: onComplete 关 LoadingScreen, webForceReload 刷新到 SceneScreen
                              widget.onComplete?.call();
                              appMain.webForceReload();
                            } else {
                              // 非首启: 同样走 onComplete + 刷新, 不调 Navigator.pop (Stack child pop 会抛异常)
                              ForceReloadSignal.notifyReload();
                              widget.onComplete?.call();
                              appMain.webForceReload();
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassStyle.onGlassPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isEn ? 'Start →' : '开始 →',
                      style: TextStyle(
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16 * scale),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingTask {
  final String label;
  final String detail;
  final double weight;
  bool done;
  _LoadingTask(this.label, this.detail, this.weight, {this.done = false});
}