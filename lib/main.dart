import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ui';
import 'models/models.dart';
import 'theme/app_theme.dart';
import 'theme/glass_decoration.dart';
import 'services/local_subscription_service.dart';
import 'services/locale_service.dart';
import 'services/motivation_service.dart';
import 'services/llm_service.dart';
import 'services/audio_play_service.dart';
import 'services/analytics_service.dart';
import 'services/theme_preference_service.dart';
import 'services/eye_protection_scope.dart';
import 'screens/user_type_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/scene_screen.dart';
import 'screens/content_screen.dart';
import 'screens/content_reader_screen.dart';
import 'screens/search_screen.dart';
import 'screens/my_subscriptions_screen.dart';
import 'screens/settings_tab.dart';
import 'screens/about_screen.dart';
import 'services/news_service.dart';
import 'services/llm_service.dart';
import 'screens/content_reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 6/14 v4 公开跨屏导航入口:content_screen "去搜索" 按钣直接调
void navigateToMainTab(int index) {
  final state = _MainHomeScreenState.globalKey.currentState;
  if (state != null) {
    (state as dynamic).setTab(index);
  }
}

// 6/11 puppeteer E2E: 设 true 开启 dev=reader&userType=...&scene=...&autoQuiz=1 深链
// 验证完设回 false 走正常 home
const bool _devDeepLinkEnabled = false;

void main() {
  runApp(const FragmentTimeApp());
}

class FragmentTimeApp extends StatefulWidget {
  const FragmentTimeApp({super.key});

  @override
  State<FragmentTimeApp> createState() => _FragmentTimeAppState();
}

class _FragmentTimeAppState extends State<FragmentTimeApp> {
  ThemeMode _mode = ThemeMode.system;
  bool _eyeProtectionOn = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _loadEyeProtection();
  }

  Future<void> _loadMode() async {
    final m = await ThemePreferenceService.instance.getMode();
    if (!mounted) return;
    setState(() => _mode = m);
  }

  Future<void> _loadEyeProtection() async {
    final on = await ThemePreferenceService.instance.isEyeProtectionOn();
    if (!mounted) return;
    setState(() => _eyeProtectionOn = on);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '碎片时间',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      // 6/13 护眼 InheritedWidget 包装（让所有屏可读）
      builder: (context, child) {
        return EyeProtectionScope(
          isOn: _eyeProtectionOn,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _devDeepLinkEnabled && kIsWeb ? _resolveDevHome() : MainHomeScreen(
        key: _MainHomeScreenState.globalKey,
        themeMode: _mode,
        onThemeModeChanged: (m) => setState(() => _mode = m),
        eyeProtectionOn: _eyeProtectionOn,
        onEyeProtectionChanged: (on) => setState(() => _eyeProtectionOn = on),
      ),
    );
  }

  Widget _resolveDevHome() {
    try {
      final params = Uri.base.queryParameters;
      if (params['dev'] == 'reader') {
        final utName = params['userType'] ?? 'student';
        final scName = params['scene'] ?? 'learn';
        final autoQuiz = params['autoQuiz'] == '1';
        final userType = UserType.values.firstWhere(
          (e) => e.name == utName,
          orElse: () => UserType.student,
        );
        final scene = Scene.values.firstWhere(
          (e) => e.name == scName,
          orElse: () => Scene.learn,
        );
        return _DevReaderHome(userType: userType, scene: scene, autoQuiz: autoQuiz);
      }
    } catch (_) {}
    return MainHomeScreen(
      themeMode: _mode,
      onThemeModeChanged: (m) => setState(() => _mode = m),
      eyeProtectionOn: _eyeProtectionOn,
      onEyeProtectionChanged: (on) => setState(() => _eyeProtectionOn = on),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool eyeProtectionOn;
  final ValueChanged<bool> onEyeProtectionChanged;
  const MainHomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.eyeProtectionOn,
    required this.onEyeProtectionChanged,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  // 6/14 v4 跨屏切 tab: GlobalKey 让 content_screen 能直接调
  // 类型不写私有类，external file 看得到 globalKey
  static final globalKey = GlobalKey<State<MainHomeScreen>>();

  /// 公开方法：切到指定 Tab (0=首页 1=搜索 2=收藏 3=设置)
  void setTab(int index) {
    if (!mounted) return;
    setState(() => _selectedIndex = index);
  }
  Future<void> _cycleThemeMode() async {
    final next = widget.themeMode == ThemeMode.system
        ? ThemeMode.light
        : widget.themeMode == ThemeMode.light
            ? ThemeMode.dark
            : ThemeMode.system;
    widget.onThemeModeChanged(next);
    await ThemePreferenceService.instance.setMode(next);
  }

  Future<void> _toggleEyeProtection() async {
    // 三态循环：auto -> on -> off -> auto
    final cur = await ThemePreferenceService.instance.getEyeProtectionMode();
    final next = cur == 'auto' ? 'on' : cur == 'on' ? 'off' : 'auto';
    await ThemePreferenceService.instance.setEyeProtectionMode(next);
    final on = await ThemePreferenceService.instance.isEyeProtectionOn();
    widget.onEyeProtectionChanged(on);
  }

  // 6/13 护眼 auto 跨时段：每 1 分钟检查一次
  // 19:00-7:00 间 isEyeProtectionOn() 返回值会变
  Timer? _eyeCheckTimer;
  int _lastEyeHourBucket = -1;

  void _startEyeTimer() {
    _eyeCheckTimer?.cancel();
    _eyeCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final mode = await ThemePreferenceService.instance.getEyeProtectionMode();
      if (mode != 'auto') return; // 只在 auto 模式下才检查
      final on = await ThemePreferenceService.instance.isEyeProtectionOn();
      if (on != widget.eyeProtectionOn) {
        widget.onEyeProtectionChanged(on);
      }
    });
  }

  // 6/14 fix: 原 22:17 提交时多了个独立 initState（只调 _startEyeTimer），
  // 跟下面那个 initState 冲突，编译失败。合到下面那个里。
  @override
  void dispose() {
    _eyeCheckTimer?.cancel();
    super.dispose();
  }

  final LocalSubscriptionService _subService = LocalSubscriptionService.instance;
  final LocaleService _localeService = LocaleService();
  final StreakService _streakService = StreakService();
  final AudioPlayService _audioService = AudioPlayService();

  bool _isInternational = false;
  bool _isElderlyMode = false;
  // 6/13 护眼状态：null=未加载，true=开，false=关
  bool? _eyeProtectionOn;
  String _languageCode = 'zh';
  UserType? _selectedUserType;
  List<ContentItem> _subscribedItems = [];
  int _subscriptionCount = 0;
  int _selectedIndex = 0;
  String _streakMessage = '';
  // 6/12 加: 首次启动引导
  bool _showOnboarding = false;
  bool _checkedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _recordOpen();
    _checkOnboarding();
    _startEyeTimer();
    // 6/24 AI 私教: 启动时检查是否要生成周回顾 (周日 20:00 之后)
    _checkWeeklyRecap();
    // 6/24 AI 私教 亮点: 启动时生成 1 句鼓励, 首页顶部 banner
    _loadDailyEncouragement();
    AnalyticsService.instance.track(AnalyticsService.EVT_APP_OPEN);
  }

  // 6/24 AI 私教 亮点: 1 句鼓励 banner
  String? _dailyEncouragement;
  String? _dailyQuote; // 6/24 v3 亮点: 每日名言

  Future<void> _loadDailyEncouragement() async {
    try {
      // adapter: 把 LlmService.generateStream 收成 Future<String>
      Future<String> llmCall(String prompt) async {
        final buffer = StringBuffer();
        await for (final chunk in LlmService.generateStream(
          userType: _selectedUserType ?? UserType.student,
          scene: Scene.learn,
          languageCode: _languageCode,
          isInternational: _isInternational,
        )) {
          buffer.write(chunk);
        }
        return buffer.toString();
      }

      // 并行调两个 LLM
      final results = await Future.wait([
        _streakService.getDailyEncouragement(isEn: isEn, llmCall: llmCall),
        _streakService.getDailyQuote(isEn: isEn, llmCall: llmCall),
      ]);
      if (!mounted) return;
      setState(() {
        _dailyEncouragement = results[0];
        _dailyQuote = results[1];
      });
    } catch (e) {
      debugPrint('AI 私教 加载失败: $e');
    }
  }

  // 6/24 AI 私教: 调用 LLM 生成本周总结 (周日 20:00 之后 + 本周未生成)
  // 最小版: 不做后台 timer, 启动时一次性检查
  Future<void> _checkWeeklyRecap() async {
    try {
      // adapter: 把 LlmService.generateStream 收成 Future<String>
      Future<String> llmCall(String prompt) async {
        final buffer = StringBuffer();
        await for (final chunk in LlmService.generateStream(
          userType: _selectedUserType ?? UserType.student,
          scene: Scene.learn,
          languageCode: _languageCode,
          isInternational: _isInternational,
        )) {
          buffer.write(chunk);
        }
        return buffer.toString();
      }

      final recap = await _streakService.maybeGenerateWeeklyRecap(
        isEn: isEn,
        llmCall: llmCall,
      );
      if (recap == null || recap.isEmpty || !mounted) return;
      // 弹窗显示 LLM 总结
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              const Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 22),
              const SizedBox(width: 8),
              Text(isEn ? 'Weekly recap' : '本周回顾',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            content: Text(recap, style: const TextStyle(fontSize: 14, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(isEn ? 'Got it' : '收下'),
              ),
            ],
          ),
        );
      });
    } catch (e) {
      // 静默失败, 不打扰用户
      debugPrint('AI 私教 周回顾生成失败: $e');
    }
  }

  // 6/12 加: 检查是否首启
  // 6/18 改: 强制跳过 onboarding (Brien 看完 3 屏后确认 30s 引导是累赘)
  Future<void> _checkOnboarding() async {
    // 直接写 prefs,跟 OnboardingScreen._kShownKey = 'onboarding_shown_v1' 一致
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_shown_v1', true);
    if (mounted) {
      setState(() {
        _showOnboarding = false;
        _checkedOnboarding = true;
      });
    }
  }

  int _prevStreak = 0;
  Future<void> _recordOpen() async {
    final before = await _streakService.getStreakCount();
    await _streakService.recordOpen();
    final result = await _streakService.checkJustUnlocked(isEn, before);
    if (!mounted) return;
    setState(() => _prevStreak = result.streak);
    if (result.justUnlocked != null) {
      // 6/9 B：milestone 解锁弹窗
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(result.justUnlocked!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            content: Text(isEn
                ? 'You unlocked a new feature. Keep going!'
                : '解锁了新功能，继续坚持！'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(isEn ? 'Nice' : '好的'),
              ),
            ],
          ),
        );
      });
    }
  }

  bool get isEn => _languageCode == 'en';
  double get _scale => _isElderlyMode ? 1.3 : 1.0;

  Future<void> _loadSettings() async {
    final isInt = await _localeService.getIsInternational();
    final isElderly = await _localeService.getIsElderlyMode();
    final lang = await _localeService.getLanguageCode();
    final typeName = await _localeService.getSelectedUserTypeName();
    final items = await _subService.getSubscribedItems();
    final msg = await _streakService.getStreakMessage(isEn);
    setState(() {
      _isInternational = isInt;
      _isElderlyMode = isElderly;
      _languageCode = lang;
      _subscribedItems = items;
      _subscriptionCount = items.length;
      _streakMessage = msg;
      if (typeName.isNotEmpty) {
        _selectedUserType = UserType.values.firstWhere(
          (t) => t.name == typeName,
          orElse: () => UserType.student,
        );
      }
    });
  }

  Future<void> _refreshSubscriptionBadge() async {
    final items = await _subService.getSubscribedItems();
    if (!mounted) return;
    setState(() {
      _subscribedItems = items;
      _subscriptionCount = items.length;
    });
  }

  Future<void> _toggleInternational() async {
    setState(() {
      _isInternational = !_isInternational;
      // 6/12 改: 切国际默认联动切英文 (国际内容是英文源，中文 UI 难看懂)
      // 切回国内保留语言不动 (4 种组合都允许)
      if (_isInternational) _languageCode = 'en';
    });
    await _localeService.setIsInternational(_isInternational);
    await _localeService.setLanguageCode(_languageCode);
  }

  Future<void> _toggleLanguage() async {
    // 6/12 改: 切语言永远不动地区 (语言 × 地区是两个独立维度, 4 组合都允许)
    setState(() {
      _languageCode = _languageCode == 'zh' ? 'en' : 'zh';
    });
    await _localeService.setLanguageCode(_languageCode);
  }

  Future<void> _toggleElderlyMode() async {
    setState(() => _isElderlyMode = !_isElderlyMode);
    await _localeService.setIsElderlyMode(_isElderlyMode);
  }

  // 6/13 主题切换：system -> light -> dark -> system 三状态循环
  // 在 _MainHomeScreenState 里实现（需要访问 _mode）

  Future<void> _onUserTypeSelected(UserType type) async {
    setState(() => _selectedUserType = type);
    await _localeService.setSelectedUserType(type);
  }

  @override
  Widget build(BuildContext context) {
    final config = _isInternational ? AppConfig.global : AppConfig.domestic;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              UserTypeScreen(
                config: config,
                isInternational: _isInternational,
                isElderlyMode: _isElderlyMode,
                languageCode: _languageCode,
                streakMessage: _streakMessage,
                selectedUserType: _selectedUserType,
                onToggleInternational: _toggleInternational,
                onToggleLanguage: _toggleLanguage,
                onToggleElderlyMode: _toggleElderlyMode,
                onUserTypeSelected: _onUserTypeSelected,
              ),
              SearchScreen(
                isElderlyMode: _isElderlyMode,
                languageCode: _languageCode,
                isInternational: _isInternational,
              ),
              MySubscriptionsScreen(
                isElderlyMode: _isElderlyMode,
                isEn: isEn,
              ),
              SettingsTab(
                config: config,
                isInternational: _isInternational,
                isElderlyMode: _isElderlyMode,
                languageCode: _languageCode,
                onToggleInternational: _toggleInternational,
                onToggleLanguage: _toggleLanguage,
                onToggleElderlyMode: _toggleElderlyMode,
                onToggleTheme: _cycleThemeMode,
                onToggleEyeProtection: _toggleEyeProtection,
              ),
            ],
          ),
          // 6/12 加: 首启引导覆盖层
          if (_checkedOnboarding && _showOnboarding)
            OnboardingScreen(
              isEn: isEn,
              selectedUserType: _selectedUserType,
              onUserTypeSelected: _onUserTypeSelected,
              onSkip: () => setState(() => _showOnboarding = false),
            ),
          // 6/24 AI 私教 亮点: 顶部鼓励 + 名言 banner, 只在 Tab 0 显
          if (_selectedIndex == 0 && (_dailyEncouragement != null || _dailyQuote != null))
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _DailyEncouragementBanner(
                  text: _dailyEncouragement ?? '',
                  quote: _dailyQuote,
                  isEn: isEn,
                  isElderlyMode: _isElderlyMode,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        // 6/14 visionOS 胶囊导航:全宽胶囊 + 高亮胶囊 + 顶亮高光
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              height: 64,
              decoration: GlassStyle.glassCapsule(),
              child: Row(
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home, isEn ? 'Home' : '首页'),
                  _buildNavItem(1, Icons.search_outlined, Icons.search, isEn ? 'Search' : '搜索'),
                  _buildNavItem(
                    2,
                    Icons.bookmark_outline,
                    Icons.bookmark,
                    isEn ? 'Saved' : '收藏',
                    badge: _subscriptionCount,
                  ),
                  _buildNavItem(3, Icons.settings_outlined, Icons.settings, isEn ? 'Settings' : '设置'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleUnsubscribe(ContentItem item) async {
    await _subService.unsubscribe(item);
    await _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEn ? 'Unsubscribed' : '已取消订阅'),
          action: SnackBarAction(
            label: isEn ? 'Undo' : '撤销',
            onPressed: () async {
              await _subService.subscribe(item);
              await _loadSettings();
            },
          ),
        ),
      );
    }
  }
}

// 6/11 puppeteer E2E 临时深链已撤, 保留 footer 防止 git diff 误判
// 6/11 重启: 用 _devDeepLinkEnabled 常量开关, 不传 dev 参数走 MainHomeScreen

// 6/11 puppeteer E2E 临时深链
class _DevReaderHome extends StatefulWidget {
  final UserType userType;
  final Scene scene;
  final bool autoQuiz;
  const _DevReaderHome({required this.userType, required this.scene, this.autoQuiz = false});
  @override
  State<_DevReaderHome> createState() => _DevReaderHomeState();
}

// 6/14 visionOS 胶囊导航 item：当前 tab = 高亮胶囊 + 白字
Widget _buildNavItem(
  int index,
  IconData icon,
  IconData iconActive,
  String label, {
  int badge = 0,
}) {
  return Builder(builder: (context) {
    final mainState = context.findAncestorStateOfType<_MainHomeScreenState>();
    if (mainState == null) return const SizedBox.shrink();
    final selected = mainState._selectedIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            mainState.setState(() {
              mainState._selectedIndex = index;
              if (mainState._showOnboarding) mainState._showOnboarding = false;
            });
            if (index == 2) mainState._refreshSubscriptionBadge();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: selected
                  ? GlassStyle.glassLiquidHighlight(radius: 18)
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? iconActive : icon,
                        size: 20,
                        color: selected ? Colors.white : AppTheme.textDark.withOpacity(0.65),
                      ),
                      if (badge > 0)
                        Positioned(
                          right: -6,
                          top: -3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: GlassStyle.danger,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: Text(
                              '$badge',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  });
}

class _DevReaderHomeState extends State<_DevReaderHome> {
  late Future<ContentItem?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ContentItem?> _load() async {
    final list = await NewsService().getRecommendations(widget.userType, widget.scene);
    if (list.isEmpty) return null;
    return list.first;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: FutureBuilder<ContentItem?>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = snap.data;
          if (item == null) {
            return const Center(child: Text('No content'));
          }
          return _AutoQuizWrapper(
            item: item,
            autoQuiz: widget.autoQuiz,
          );
        },
      ),
    );
  }
}

class _AutoQuizWrapper extends StatefulWidget {
  final ContentItem item;
  final bool autoQuiz;
  const _AutoQuizWrapper({required this.item, required this.autoQuiz});
  @override
  State<_AutoQuizWrapper> createState() => _AutoQuizWrapperState();
}

class _AutoQuizWrapperState extends State<_AutoQuizWrapper> {
  @override
  void initState() {
    super.initState();
    if (widget.autoQuiz) {
      Future.microtask(() async {
        final t0 = DateTime.now();
        try {
          final qs = await LlmService.generateQuiz(
            title: widget.item.title,
            description: widget.item.description,
          );
          // ignore: avoid_print
          print('[AUTOQUIZ] OK ${qs.length} questions in ${DateTime.now().difference(t0).inSeconds}s');
        } catch (e) {
          // ignore: avoid_print
          print('[AUTOQUIZ] FAIL after ${DateTime.now().difference(t0).inSeconds}s: $e');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentReaderScreen(item: widget.item);
  }
}

// 6/24 AI 私教 亮点: 1 句鼓励 banner — 顶部飘条, 玻璃磨砂风格
// 6/24 v3 升级: 鼓励 + 名言 2 行
class _DailyEncouragementBanner extends StatelessWidget {
  final String text;
  final String? quote;
  final bool isEn;
  final bool isElderlyMode;
  const _DailyEncouragementBanner({
    required this.text,
    this.quote,
    required this.isEn,
    required this.isElderlyMode,
  });

  @override
  Widget build(BuildContext context) {
    final scale = isElderlyMode ? 1.3 : 1.0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 鼓励
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          // 名言 (6/24 v3)
          if (quote != null) ...[
            SizedBox(height: 6 * scale),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                '“$quote”',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
