import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui';
// 6/29: web-only dart:js 平台实现走条件 import
import 'web_helpers_stub.dart'
    if (dart.library.js) 'web_helpers_web.dart';
// re-export 让 loading_screen.dart 用 appMain.webForceReload() 不用改
export 'web_helpers_stub.dart'
    if (dart.library.js) 'web_helpers_web.dart';
import 'models/models.dart';
import 'theme/app_theme.dart';
import 'theme/glass_decoration.dart';
import 'services/local_subscription_service.dart';
import 'services/subscription_service.dart';
import 'services/history_service.dart';
import 'services/locale_service.dart';
import 'services/motivation_service.dart';
import 'services/llm_service.dart';
import 'services/audio_play_service.dart';
import 'services/analytics_service.dart';
import 'services/theme_preference_service.dart';
import 'services/eye_protection_scope.dart';
import 'services/handle_service.dart';
import 'screens/user_type_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/loading_screen.dart';
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
import 'screens/ai_assistant_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 6/14 v4 公开跨屏导航入口:content_screen "去搜索" 按钣直接调
void navigateToMainTab(int index) {
  final state = _MainHomeScreenState.globalKey;
  if (state.currentState != null) {
    (state.currentState as dynamic).setTab(index);
  }
}

// 6/28 公开 globalKey accessor (跨文件使用, 不暴露私有类 _MainHomeScreenState)
// 直接暴露 GlobalKey 让调用方调 currentState, 避免跨 getter 调用
GlobalKey<State<MainHomeScreen>> get globalMainKey => _MainHomeScreenState.globalKey;

// 6/28 公开跨屏入口: LoadingScreen '开始' 按钮调用
// 真凶猜测: popUntil(isFirst) 在 Flutter web 上可能有 Navigator 事件没正常路由
//              → 改用 GlobalKey 直接调 _MainHomeScreenState 跳转 + popUntil
void completeLoadingAndGoHome() {
  final state = _MainHomeScreenState.globalKey;
  if (state.currentState != null) {
    // 强制跳到 Tab 0 (SceneScreen), 关闭 WelcomeScreen / Onboarding
    (state.currentState as dynamic).setTab(0);
    (state.currentState as dynamic).finishLoading();
  }
}

// 6/28 公开入口: WelcomeScreen '继续' 按钮调用
// 真凶: WelcomeCompleteSignal ValueNotifier 在 Flutter web 上 listener 偶发不触发
// 修: 直接用 GlobalKey 调 _MainHomeScreenState.hideWelcomeScreen()
void hideWelcomeScreenFromOutside() {
  final state = _MainHomeScreenState.globalKey;
  if (state.currentState != null) {
    (state.currentState as dynamic).hideWelcomeScreen();
  }
}

// 6/28 16:11 Brien 反馈: '点开始不能强刷' (3 次反馈, 终于懂了)
// webReloadPage / webForceReload 实现挪到 lib/web_helpers_web.dart (web-only),
// 6/29 抽出来是为了 android APK build 也能编 (dart:js 是 web-only API)

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
  ThemeMode _mode = ThemeMode.light; // 6/28 Brien 反馈: 手机 dark system 让 app 变 dark → 强制 light default
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
      // 6/28 Brien 反馈: '手机加载页面总是黑黑的, 深色模式, 永远' (手机 system dark → app dark → 老人/上班族看着累)
      // 真凶: themeMode = system 跟随手机 system, 手机 dark → app dark → SceneScreen / LoadingScreen 全 dark
      // 修: 强制 themeMode = light, 老人/上班族看着累别选 dark。
      //     用户在设置 Tab 手动点 dark 会调 setMode → _mode → setState (ThemeMode.dark) 仍然生效
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
  /// 6/24 v8: 切到收藏 Tab 时 reload 刷新刚订阅的内容
  void setTab(int index) {
    if (!mounted) return;
    setState(() => _selectedIndex = index);
    // 6/24 v14: IndexedStack 一直挂载, reload 路径不可靠
    // 改为: LocalSubscriptionService 用 ChangeNotifier, MySubscriptionsScreen watch 自动 rebuild
  }

  /// 6/28 LoadingScreen '开始' 回调: 关闭 WelcomeScreen / Onboarding, 跳 Tab 0
  void finishLoading() {
    if (!mounted) return;
    setState(() {
      _showWelcome = false;
      _showOnboarding = false;
      _checkedWelcome = true;
      _checkedOnboarding = true;
      _selectedIndex = 0;
    });
  }

  /// 6/28 LoadingScreen 作为覆盖层使用 (不走 Navigator push/pop, 避免 Flutter web Navigator 事件不触发)
  /// MainHomeScreen Stack 多加一个 LoadingScreen 覆盖层, 用 _showLoading 控制显示
  bool _showLoading = false;
  bool get showLoading => _showLoading;

  void showLoadingScreen() {
    if (!mounted) return;
    setState(() {
      _showLoading = true;
    });
  }

  void hideLoadingScreen() {
    if (!mounted) return;
    // 6/28 Brien 反馈: 'LoadingScreen 消失后一片白'
    // 真凶: prefs 'first_run_done_v1' 没写成功 (fire-and-forget 丢) → _showWelcome=true 一直显示 WelcomeScreen
    // 修: hideLoadingScreen 同时强制关掉 WelcomeScreen / Onboarding, 不依赖 prefs
    setState(() {
      _showLoading = false;
      _showWelcome = false;
      _showOnboarding = false;
      _checkedWelcome = true;
      _checkedOnboarding = true;
    });
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
    WelcomeCompleteSignal.instance.removeListener(_onWelcomeComplete);
    ForceReloadSignal.instance.removeListener(_onForceReload);
    super.dispose();
  }

  // 6/25 WelcomeScreen 完成回调
  void _onWelcomeComplete() {
    if (!mounted) return;
    setState(() => _showWelcome = false);
  }

  /// 6/28 公开方法: WelcomeScreen '继续' 按了直接调 (不走 ValueNotifier)
  /// 真凶: WelcomeCompleteSignal ValueNotifier 在 Flutter web 上 listener 偶发不触发
  void hideWelcomeScreen() {
    if (!mounted) return;
    setState(() => _showWelcome = false);
  }

  /// 6/28 加: hideOnboarding / hideLoadingScreen 公开方法, 让 LoadingScreen '开始' 一键关所有
  void hideOnboarding() {
    if (!mounted) return;
    setState(() => _showOnboarding = false);
  }

  // 6/28 LoadingScreen '强制刷新' 回调 (Brien 反馈: 保留为强行加载入口)
  // 接收到信号后: 重新拉 _subscribedItems + 让 ContentScreen rebuild
  void _onForceReload() {
    _reloadAll();
  }

  Future<void> _reloadAll() async {
    if (!mounted) return;
    try {
      // 1. 重新拉关注列表 (LocalSubscriptionService)
      final items = await _subService.getSubscribedItems();
      if (!mounted) return;
      setState(() {
        _subscribedItems = items;
        _subscriptionCount = items.length;
      });
      // 2. 重新拉每日名言 (DailyMessage)
      await _loadDailyQuote();
      // 3. ContentScreen 通过 _subscribedItems 变化自动 rebuild (Consumer/Provider 风格)
    } catch (e) {
      debugPrint('[force-reload] 失败: $e');
    }
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
  int _selectedIndex = 0; // 6/30 09:42: 默认进场景 (Tab 0), AI 是场景页浮动按钮
  String _streakMessage = '';
  // 6/12 加: 首次启动引导
  bool _showOnboarding = false;
  bool _checkedOnboarding = false;
  bool _showWelcome = true; // 6/25 Brien 反馈: 首启欢迎屏 (取昵称/跳过)
  bool _checkedWelcome = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _recordOpen();
    _checkOnboarding();
    _checkWelcome(); // 6/25 首启欢迎屏
    // 6/25 WelcomeScreen 完成信号监听
    WelcomeCompleteSignal.instance.addListener(_onWelcomeComplete);
    // 6/28 LoadingScreen '强制刷新' 信号监听 (Brien 反馈: 保留为强行加载入口)
    ForceReloadSignal.instance.addListener(_onForceReload);
    _startEyeTimer();
    // 6/24 AI 私教: 启动时检查是否要生成周回顾 (周日 20:00 之后)
    _checkWeeklyRecap();
    // 6/24 AI 私教 亮点: 启动时生成 1 句鼓励, 首页顶部 banner
    _loadDailyQuote();
    // 6/25 昵称扩展: 启动时加载 handle
    _loadHandle();
    // 6/26 迁移: 删老 id 'encourage_*' 的 item (banner 改名言后老 item 装的是完整 LLM 推的鼓励新闻)
    _migrateOldEncourageItems();
    AnalyticsService.instance.track(AnalyticsService.EVT_APP_OPEN);
  }

  // 6/26 迁移: 删老 id 'encourage_*' 的 item, banner 现在只存名言
  Future<void> _migrateOldEncourageItems() async {
    try {
      final items = await LocalSubscriptionService.instance.getSubscribedItems();
      final old = items.where((it) => it.id.startsWith('encourage_')).toList();
      for (final it in old) {
        await LocalSubscriptionService.instance.unsubscribe(it);
      }
      if (old.isNotEmpty) debugPrint('[migrate] 删了 ${old.length} 个老 encourage_ item');
    } catch (_) {}
  }

  // 6/25 昵称扩展: 加载 handle (banner / 收藏 tab / 分享卡都用)
  Future<void> _loadHandle() async {
    final h = await HandleService().get();
    if (!mounted) return;
    setState(() => _handle = h);
  }

  // 6/26 Brien 反馈: 名言对各角色通用, 删掉鼓励字段
  String? _dailyQuote; // 每日名言 — banner 唯一内容
  String _handle = HandleService.defaultHandle; // 6/25 昵称扩展: 从 HandleService 传入
  bool _quoteLoading = false; // 6/29: 防止点 "下一个" 按钮时双击

  Future<void> _loadDailyQuote() async {
    try {
      // 6/26 重构: 只调名言, 删鼓励 (名言对各角色通用)
      Future<String> llmCall(String prompt) async {
        final buffer = StringBuffer();
        await for (final chunk in LlmService.generateStream(
          userType: UserType.officeWorker, // 名言不跟 userType 绑, 随便传个
          scene: Scene.learn,
          languageCode: _languageCode,
          isInternational: _isInternational,
        ).timeout(const Duration(seconds: 5), onTimeout: (sink) {
          // 6/28 Brien 反馈: '顶上的名言呢' — LLM 冷启动 12-20s 不 throw 也不返回
          // 这里 5s 强行 timeout, 避免 _dailyQuote 永远 null
          sink.close();
        })) {
          buffer.write(chunk);
        }
        return buffer.toString();
      }

      final quote = await _streakService.getDailyQuote(isEn: isEn, llmCall: llmCall);
      // 6/26 Brien 反馈: LLM 1.5b 推 250 字新闻, 不是 25 字名言 → 硬截断 50 字
      final trimmed = quote.length > 50 ? '${quote.substring(0, 50)}…' : quote;
      if (!mounted) return;
      setState(() {
        _dailyQuote = trimmed;
      });
    } catch (e) {
      // 6/28 Brien 反馈: '顶上的名言呢' = _dailyQuote 一直是 null, banner 不显示
      // 真凶: 这里 catch 之后 _dailyQuote 永不被设值, main.dart 的 banner condition 永远失败
      // 修: 兑底给一句硬编码名言 + 仍 setState
      debugPrint('名言 加载失败 (兑底): $e');
      final fallback = isEn
          ? 'The impediment to action advances action. — Marcus Aurelius'
          : '竹杖芒鞋轻胜马, 谁怕? 一蓑烟雨任平生。';
      if (!mounted) return;
      setState(() {
        _dailyQuote = fallback;
      });
    }
  }

  // 6/29 10:59: 简化 — 不调 LLM, 走 hardcoded 池 (快)
  void _loadNextQuote() {
    if (_quoteLoading) return;
    if (!mounted) return;
    setState(() {
      _quoteLoading = true;
      _dailyQuote = _streakService.getRandomQuoteSync(isEn: isEn);
      _quoteLoading = false;
    });
  }

  // 6/29 13:56: quote 变 prefs key 也要变 — 不然同一天 quote_saved 状态串台
  String get _currentQuoteKey {
    if (_dailyQuote == null || _dailyQuote!.isEmpty) return '';
    return _dailyQuote!.hashCode.toString();
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
              Text(isEn ? 'Weekly recap · $_handle' : '$_handle 的本周回顾',
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

  // 6/25 Brien 反馈: 首启欢迎屏 (取昵称/跳过)
  Future<void> _checkWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('first_run_done_v1') ?? false;
    if (!mounted) return;
    setState(() {
      _showWelcome = !done;
      _checkedWelcome = true;
    });
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
    // 6/28 Brien 反馈: '选完兴趣点后系统自动会加载'
    // 设计: 选完角色后不弹 TopicOnboarding (6/18 已确认 30s 引导累赘),
    //       直接调 SubscriptionService.subscribeCategory × defaultCategories
    //       让首页推荐池一打开就有内容, 跟用户预期一致
    // 用 fire-and-forget, 不阻塞角色选择
    _autoSubscribeDefaultCategories();
  }

  // 6/28: 自动关注默认 8 个类目 (用户没显式选过的话)
  // 防御: 检查 SharedPreferences 'subscribed_categories' 是否为空, 避免重复
  Future<void> _autoSubscribeDefaultCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('subscribed_categories') ?? [];
      if (existing.isNotEmpty) return; // 已有手动选过, 不重复
      for (final cat in SubscriptionService.defaultCategories) {
        await SubscriptionService.instance.subscribeCategory(cat);
      }
      // 刷新 _subscribedItems 让 banner / Tab 1 推荐池更新
      if (mounted) {
        try {
          final items = await _subService.getSubscribedItems();
          if (!mounted) return;
          setState(() {
            _subscribedItems = items;
            _subscriptionCount = items.length;
          });
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('auto-subscribe 失败: $e');
    }
  }

  // 6/24 v12: 设置 Tab "我的身份" — 弹出 6 角色选择
  // 6/24 v13: 点击 banner 名言/鼓励 → 弹底部 Sheet, 显示今天读过的相关推荐
  Future<void> _showQuoteDetailSheet() async {
    // 拉今天的历史 (推荐相关)
    final all = await HistoryService.instance.getAll();
    final now = DateTime.now();
    final recent = all.where((h) {
      final t = DateTime.fromMillisecondsSinceEpoch(h.readAt);
      return now.difference(t).inDays <= 7;
    }).take(10).toList();

    // 6/24 v16: 名言 LLM 升级 — 调 LLM 生成 3 个相关关键词作为 sheet 顶部提示
    List<String>? llmKeywords;
    if (_dailyQuote != null && _dailyQuote!.isNotEmpty) {
      try {
        llmKeywords = await _getLLMKeywordsForQuote(_dailyQuote!);
      } catch (_) {
        llmKeywords = null;
      }
    }

    if (!mounted) return;
    if (recent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEn
            ? 'Read a few items first — then tap this for related content.'
            : '先看几篇文章/听几个内容，再点这里看相关推荐。')),
      );
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _QuoteDetailSheet(
        recent: recent,
        isEn: isEn,
        // 6/26: 删鼓励字段, 只传 quote
        quote: _dailyQuote,
        llmKeywords: llmKeywords, // 6/24 v16
      ),
    );
  }

  // 6/24 v16: LLM 提取名言相关关键词 (最多 3 个)
  Future<List<String>?> _getLLMKeywordsForQuote(String quote) async {
    try {
      final prompt = isEn
          ? 'Given this quote: "$quote"\nReturn 3 short related topic keywords (1-3 words each), comma-separated. NO explanation, NO quotes, NO labels.'
          : '名言: "$quote"\n返回 3 个相关话题关键词（每个 1-3 字），用逗号分隔。不要解释，不要引号。';
      final raw = await LlmService.generateRaw(prompt, isEn: isEn);
      if (raw.isEmpty) return null;
      return raw
          .split(RegExp(r'[,，、\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.length <= 8)
          .take(3)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _showChangeUserTypeDialog() async {
    final picked = await showDialog<UserType>(
      context: context,
      builder: (ctx) {
        final isEn = _languageCode == 'en';
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isEn ? 'Choose your identity' : '选择你的身份'),
          content: SizedBox(
            width: 320,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.2,
              children: UserType.values.map((t) {
                final isSelected = _selectedUserType == t;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary.withOpacity(0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        isEn ? _userTypeNameEn(t) : _userTypeNameZh(t),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? AppTheme.primary : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
    if (picked != null && picked != _selectedUserType) {
      await _onUserTypeSelected(picked);
    }
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
              // 6/30 09:42: AI 助手改为场景页 FAB 浮动按钮, 不占 Tab
              _Tab0Switcher(
                selectedUserType: _selectedUserType,
                config: config,
                isInternational: _isInternational,
                isElderlyMode: _isElderlyMode,
                languageCode: _languageCode,
                streakMessage: _streakMessage,
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
                key: MySubscriptionsScreen.reloadKey, // 6/24 v8: reload 刷新
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
                selectedUserType: _selectedUserType, // 6/24 v12
                onChangeUserType: _showChangeUserTypeDialog, // 6/24 v12
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
          // 6/25 加: 首启欢迎屏 (取昵称/跳过) — 在 Onboarding 之上, 不冲突
          if (_checkedWelcome && _showWelcome)
            WelcomeScreen(
              key: const ValueKey('welcome_screen'),
              onComplete: () {
                // 6/28 19:54 Brien 反馈: '所有浏览器都不行, 你自己想办法'
                // 真凶: globalKey.currentState = null (Flutter web canvas render detach)
                // 修法: 不用 globalKey, 让 MainHomeScreen 自己用 setState 关闭 _showWelcome
                //   WelcomeScreen 是 Stack child, 不依赖 Navigator, 直接 setState 即可
                if (mounted) {
                  setState(() {
                    _showWelcome = false;
                    _checkedWelcome = true;
                  });
                }
              },
            ),
          // 6/28 LoadingScreen 作为覆盖层 (不走 Navigator)
          // 真凶: LoadingScreen push 出来 + Navigator pop 在 Flutter web 上不触发
          // 修: MainHomeScreen Stack 多加一个 LoadingScreen, _showLoading 控制显示
          if (_showLoading)
            LoadingScreen(
              key: const ValueKey('loading_screen'),
              userTypeName: _selectedUserType == null ? '' : (_isInternational ? _selectedUserType!.name : _selectedUserType!.title),
              isInternational: _isInternational,
              isElderlyMode: _isElderlyMode,
              languageCode: _languageCode,
              onComplete: () {
                // 6/28: '开始' callback 关 LoadingScreen + Welcome + Onboarding, 切到 Tab 0
                if (mounted) {
                  setState(() {
                    _showLoading = false;
                    _showWelcome = false;
                    _showOnboarding = false;
                    _checkedWelcome = true;
                    _checkedOnboarding = true;
                    _selectedIndex = 0;
                  });
                }
              },
            ),
          // 6/28 Brien 反馈: 'LoadingScreen 消失后一片白' = LoadingScreen widget 报错 (e.g. _scale getter 未定义) 中断了 main build
          // 修: 加 ErrorWidget 兑底 (出 bug 时显红色块而不是白屏, 便于诊断)
          // 6/26 Brien 反馈: 恢复 banner, 只显示 1 句名言
          if (_selectedIndex == 0 && _dailyQuote != null && !_showWelcome && !_showOnboarding && _selectedUserType != null)
            Positioned(
              // 6/29 10:38 Brien 反馈: banner 跟 AppBar 挤了 — top 0 跟 AppBar 重叠
              // 修: top = AppBar toolbarHeight + status bar (MediaQuery padding.top)
              // 老人模式 AppBar 默认 56×1.3 ≈ 72
              top: (_isElderlyMode ? 72 : 56) + MediaQuery.of(context).padding.top,
              left: 0,
              right: 0,
              child: _DailyEncouragementBanner(
                text: '',
                quote: _dailyQuote,
                isEn: isEn,
                isElderlyMode: _isElderlyMode,
                handle: _handle,
                onTapDetail: _showQuoteDetailSheet,
                onNextQuote: _loadNextQuote, // 6/29: 点 "下一个" 按钮
              ),
            ),
            // 6/29 10:54 Brien 反馈: ↻ 按钮从 banner 内挪到外, 放在 64dp 空白区
            // top 对齐 banner 顶部 (80 老人 96), right 距屏边 8
            if (_dailyQuote != null && !_showWelcome && !_showOnboarding && _selectedUserType != null && _selectedIndex == 0)
              Positioned(
                top: (_isElderlyMode ? 72 : 56) + MediaQuery.of(context).padding.top + 4,
                right: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _quoteLoading ? null : _loadNextQuote,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: _isElderlyMode ? 44 : 36,
                      height: _isElderlyMode ? 44 : 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFC).withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF7C5CFC).withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: _quoteLoading
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF7C5CFC),
                              ),
                            )
                          : Icon(
                              Icons.shuffle, // 6/29 10:57: 区别于 AppBar 绿色 ↻ (Icons.refresh_outlined)
                              size: _isElderlyMode ? 22 : 18,
                              color: const Color(0xFF7C5CFC),
                            ),
                    ),
                  ),
                ),
              ),
        ],
      ),
      bottomNavigationBar: (_showWelcome || _showOnboarding || _selectedUserType == null)
          ? null
          : Padding(
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
                  _buildNavItem(0, Icons.home_outlined, Icons.home, isEn ? 'Home' : '场景'),
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
// 6/24 v6: ❤️ 收藏按钮 - 把鼓励 + 名言当一条收藏存到 Tab 2
class _DailyEncouragementBanner extends StatefulWidget {
  final String text;
  final String? quote;
  final bool isEn;
  final bool isElderlyMode;
  final String handle; // 6/25: 昵称 (从 HandleService 传入)
  final VoidCallback onTapDetail; // 6/24 v13: 点 banner 弹相关推荐
  final VoidCallback? onNextQuote; // 6/29: 点 "下一个" 按钮
  const _DailyEncouragementBanner({
    required this.text,
    this.quote,
    required this.isEn,
    required this.isElderlyMode,
    required this.handle,
    required this.onTapDetail,
    this.onNextQuote,
  });

  @override
  State<_DailyEncouragementBanner> createState() => _DailyEncouragementBannerState();
}

class _DailyEncouragementBannerState extends State<_DailyEncouragementBanner> {
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
  void didUpdateWidget(covariant _DailyEncouragementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quote != widget.quote) {
      _loadSaved();
    }
  }

  // 6/24 v9: 从 SharedPreferences 读今日是否已收藏 (重启后保持 ❤️)
  // 6/25 修 bug: 同时查订阅 list 验证 (双重保险, prefs true 但 list 已删 → 重置 prefs)
  // 6/26: id 从 encourage_ 改 quote_ (banner 现在是名言不是鼓励)
// 6/29 13:56: 改 key 用 quote text hash — 换名言后状态重置, 不同名言不同 prefs key
  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final quoteText = widget.quote ?? '';
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
          // list 里没了, 重置 prefs (修正数据不一致)
          await prefs.setBool(key, false);
        }
      }
      // 6/29 14:59: 不管 prefSaved 是什么, 都显式 setState, 避免中间帧 _saved 为默认值 false 闪空心
      if (mounted) setState(() => _saved = shouldBeSaved);
      _loaded = true;
    } catch (_) {
      if (mounted) setState(() => _saved = false);
      _loaded = true;
    }
  }

  // 6/24 v6: 收藏鼓励+名言 当一条 ContentItem 到 Tab 2
  Future<void> _onSave() async {
    if (_saved) return;
    final now = DateTime.now();
    // 6/29 13:56: 改 id 用 quote text hash — 不同名言不同 id/prefs key
    final quoteText = widget.quote ?? widget.text;
    final id = 'quote_${quoteText.hashCode}';
    final title = widget.isEn
        ? 'AI ${now.month}/${now.day} quote'
        : 'AI ${now.month}月${now.day}日名言';
    final desc = quoteText; // 6/26: 只存名言本身, 不拼鼓励+引号
    final item = ContentItem(
      id: id,
      title: title,
      description: desc,
      duration: widget.isEn ? '1 min read' : '1 分钟阅读',
      source: widget.isEn ? 'AI Companion' : 'AI 私教',
      sourceType: ContentSource.rss,
      contentType: ContentType.card,
      lastReadAt: now,
    );
    try {
      await LocalSubscriptionService.instance.subscribe(item);
      if (!mounted) return;
      // 6/24 v9: 持久化已收藏标记 (重启后保持 ❤️)
      // 6/29 13:56: key 用 quote hash, 换名言后状态隔离
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
              // 6/24 v9: 切到 Tab 2 (收藏)
              navigateToMainTab(2);
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

  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 6/26 Brien 反馈: banner 只放名言, 不显示鼓励 / 推荐内容
            Row(
              children: [
                const Icon(Icons.format_quote, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.quote ?? widget.text, // 6/26: 优先 quote, 没 quote 时兑底用鼓励
                    maxLines: 1, // 6/26 Brien 反馈: LLM 1.5b 推 250 字 → 强制 1 行省略
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                // 6/24 v6: ❤️ 收藏按钮
                GestureDetector(
                  onTap: _onSave,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _saved
                        ? Icon(
                            Icons.favorite,
                            key: const ValueKey('saved'),
                            color: Colors.white,
                            size: 20 * scale,
                          )
                        : Row(
                            key: const ValueKey('unsaved'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.favorite_border,
                                color: Colors.white,
                                size: 20 * scale,
                              ),
                              SizedBox(width: 4 * scale),
                              Text(
                                widget.isEn ? 'Save' : '收藏',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11 * scale,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                // 6/29 10:49 改为: "下一个名言" 按钮挪到 banner 外, 放 64dp 空白处
                // (banner 让给 AppBar actions 的 64dp 区域)
                // 见 main.dart Stack 里的 _NextQuoteFab Positioned
              ],
            ),
          ],
      ),
      ),
    );
  }
}

// 6/24 v12: Tab 0 切换 — 已选角色 → ContentScreen, 未选 → UserTypeScreen
// 用 AnimatedSwitcher 保持 state, 用 ValueKey 防重建丢失
class _Tab0Switcher extends StatelessWidget {
  final UserType? selectedUserType;
  final dynamic config;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final String streakMessage;
  final VoidCallback onToggleInternational;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleElderlyMode;
  final ValueChanged<UserType> onUserTypeSelected;

  const _Tab0Switcher({
    required this.selectedUserType,
    required this.config,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
    required this.streakMessage,
    required this.onToggleInternational,
    required this.onToggleLanguage,
    required this.onToggleElderlyMode,
    required this.onUserTypeSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedUserType == null) {
      return UserTypeScreen(
        key: const ValueKey('user_type_screen'),
        config: config,
        isInternational: isInternational,
        isElderlyMode: isElderlyMode,
        languageCode: languageCode,
        streakMessage: streakMessage,
        selectedUserType: selectedUserType,
        onToggleInternational: onToggleInternational,
        onToggleLanguage: onToggleLanguage,
        onToggleElderlyMode: onToggleElderlyMode,
        onUserTypeSelected: onUserTypeSelected,
      );
    }
    return SceneScreen(
      // 6/25 修 bug: key 加 userType 联动，改角色后 SceneScreen 重建 (否则推荐不变)
      key: ValueKey('scene_screen_${selectedUserType!.name}'),
      userType: selectedUserType!,
      isInternational: isInternational,
      isElderlyMode: isElderlyMode,
      languageCode: languageCode,
    );
  }
}

// 6/24 v12: 6 角色名 helper (供 _showChangeUserTypeDialog 使用)
String _userTypeNameZh(UserType t) {
  switch (t) {
    case UserType.student: return '学生';
    case UserType.officeWorker: return '上班族';
    case UserType.entrepreneur: return '创业者';
    case UserType.parent: return '宝爸宝妈';
    case UserType.senior: return '退休人群';
    case UserType.child: return '儿童';
  }
}

String _userTypeNameEn(UserType t) {
  switch (t) {
    case UserType.student: return 'Student';
    case UserType.officeWorker: return 'Office Worker';
    case UserType.entrepreneur: return 'Entrepreneur';
    case UserType.parent: return 'Parent';
    case UserType.senior: return 'Senior';
    case UserType.child: return 'Child';
  }
}

// 6/24 v13: 名言点开弹底部 Sheet — 显示近 7 天相关推荐
// 6/26: 删鼓励字段, 只显示 quote
class _QuoteDetailSheet extends StatelessWidget {
  final List<HistoryItem> recent;
  final bool isEn;
  final String? quote;
  final List<String>? llmKeywords;
  final UserType? selectedUserType; // 6/30 10:11: 问 AI 用
  const _QuoteDetailSheet({
    required this.recent,
    required this.isEn,
    required this.quote,
    this.llmKeywords,
    this.selectedUserType,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF7C5CFC), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEn ? 'Related to today' : '今天的相关内容',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              // 6/29 段 4: quote 联动 AI 助手 — 点 "问 AI" 关 sheet + 弹 AiAssistantScreen, 带 quote context
              if (quote != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(); // 关 quote detail sheet
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      barrierColor: Colors.black54,
                      builder: (_) => AiAssistantScreen(
                        isEn: isEn,
                        isElderlyMode: false, // quote sheet 拿不到 MainHomeScreen isElderlyMode, 兑底 false
                        userTypeName: 'you', // 兑底
                        contextQuote: quote,
                        userType: selectedUserType, // 6/30 10:11: 帮推荐/答疑用
                      ),
                    );
                  },
                  icon: const Icon(Icons.support_agent, color: Color(0xFF7C5CFC), size: 18),
                  label: Text(
                    isEn ? 'Ask AI' : '问 AI',
                    style: const TextStyle(
                      color: Color(0xFF7C5CFC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            // 6/26: 删鼓励文本
            if (quote != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '“$quote”',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            // 6/24 v16: LLM 提取的 3 个相关关键词
            if (llmKeywords != null && llmKeywords!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text(
                      isEn ? 'Related: ' : '相关: ',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    ...llmKeywords!.map((kw) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFC).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        kw,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF7C5CFC), fontWeight: FontWeight.w500),
                      ),
                    )),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            ...recent.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  elevation: 0,
                  color: const Color(0xFF7C5CFC).withOpacity(0.06),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(
                            ContentType.values.firstWhere(
                              (c) => c.name == h.contentTypeName,
                              orElse: () => ContentType.article,
                            ).icon,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${h.duration} · ${h.source}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }
}
