import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
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
import 'models/quote.dart';
import 'theme/app_theme.dart';
import 'theme/glass_decoration.dart';
import 'services/local_subscription_service.dart';
import 'services/subscription_service.dart';
import 'services/history_service.dart';
import 'services/locale_service.dart';
import 'services/motivation_service.dart';
import 'services/llm_service.dart';
import 'services/analytics_service.dart';
import 'services/theme_preference_service.dart';
import 'services/daily_prefs_service.dart';
import 'services/eye_protection_scope.dart';
import 'services/handle_service.dart';
import 'services/robot_name_service.dart';
import 'screens/user_type_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/scene_screen.dart';
import 'screens/content_reader_screen.dart';
import 'screens/search_screen.dart';
import 'screens/my_subscriptions_screen.dart';
import 'screens/settings_tab.dart';
import 'services/news_service.dart';
import 'services/time_aware_recommender.dart';
import 'services/quote_related_engine.dart';
import 'screens/ai_assistant_screen.dart';

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
    }
  }

  final LocalSubscriptionService _subService = LocalSubscriptionService.instance;
  final LocaleService _localeService = LocaleService();
  final StreakService _streakService = StreakService();

  bool _isInternational = false;
  bool _isElderlyMode = false;
  // 6/13 护眼状态: _eyeProtectionOn 由父 _FragmentTimeAppState 持有 (EyeProtectionScope 监听它)
  // 这里不再声明 (8/8 删: 之前重复声明 bool? 字段, 从未被读, 死代码 shadow 风险)
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


  // 8/16 加 (沿 SOUL #103): public method 替代外部 setState (avoid protected warning)
  void switchTab(int index) {
    setState(() {
      _selectedIndex = index;
      if (_showOnboarding) _showOnboarding = false;
    });
    if (index == 2) _refreshSubscriptionBadge();
  }
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
    // 7/30: 每日推荐 开关初始化 (默认值都开, 在 settings 可关)
    DailyPrefsService.init();
    AnalyticsService.instance.track(AnalyticsService.evtAppOpen);
  }

  // 6/26 迁移: 删老 id 'encourage_*' 的 item, banner 现在只存名言
  Future<void> _migrateOldEncourageItems() async {
    try {
      final items = await LocalSubscriptionService.instance.getSubscribedItems();
      final old = items.where((it) => it.id.startsWith('encourage_')).toList();
      for (final it in old) {
        await LocalSubscriptionService.instance.unsubscribe(it);
      }
    } catch (_) {}
  }

  // 6/25 昵称扩展: 加载 handle (banner / 收藏 tab / 分享卡都用)
  Future<void> _loadHandle() async {
    final h = await HandleService().get();
    if (!mounted) return;
    setState(() => _handle = h);
  }

  // 6/26 Brien 反馈: 名言对各角色通用, 删掉鼓励字段
  Quote? _dailyQuote; // 7/15 重构: 每日名言 — banner 唯一内容, Quote struct (含 作者/出处/翻译/日期)
  String _handle = HandleService.defaultHandle; // 6/25 昵称扩展: 从 HandleService 传入
  bool _quoteLoading = false; // 6/29: 防止点 "下一个" 按钮时双击

  Future<void> _loadDailyQuote() async {
    debugPrint('[Quote] _loadDailyQuote start, isEn=$isEn');
    // 8/6 修: 不阻塞 banner. 先 hardcoded pool 立即 setState, 后台异步调 LLM 写 cache.
    // 真凶链: 之前 await getDailyQuote 等 LLM 16.98s, banner 阻塞 17s 才出 (沿 #169 真凶链 #21 #126 #127 同根因).
    // 老 commit 8d7e464 试过 .timeout(8s) 跳, 8/3 e2582cb 改 try/finally 5s, 都还卡上游 socket 释放.
    // 修: 立即出 banner, 后台 LLM 跑完写 cache, 下次启动看 cache 直接返, 永不快出.
    final pool = isEn ? _QuotePoolFallback.en : _QuotePoolFallback.zh;
    final immediate = pool[DateTime.now().day % pool.length];
    if (!mounted) return;
    setState(() {
      _dailyQuote = immediate;
    });
    unawaited(_loadDailyQuoteAsync());
  }

  // 8/6 后台异步版: 调 LLM + 写 cache, 不阻塞 UI. 只在 banner 已经立即显示后跑.
  Future<void> _loadDailyQuoteAsync() async {
    try {
      Future<String> llmCall(String prompt) async {
        final buffer = StringBuffer();
        try {
          await for (final chunk in LlmService.generateStream(
            userType: UserType.officeWorker, // 名言不跟 userType 绑, 随便传个
            scene: Scene.learn,
            languageCode: _languageCode,
            isInternational: _isInternational,
          ).timeout(const Duration(seconds: 5))) {
            buffer.write(chunk);
          }
        } on TimeoutException {
          debugPrint('[Quote] LLM 5s timeout, 已写 ${buffer.length} chars, 跳兜底');
        }
        return buffer.toString();
      }

      debugPrint('[Quote] calling getDailyQuote (后台异步)...');
      final quote = await _streakService.getDailyQuote(isEn: isEn, llmCall: llmCall);
      debugPrint('[Quote] got quote, text.length=${quote.text.length}');
      // 7/15: LLM 或 fallback 返 Quote, 超过 80 字兑底 (仍返回原 Quote, 让 banner 截)
      final trimmed = quote.text.length > 80
          ? Quote(text: quote.text.substring(0, 80) + '…', author: quote.author, source: quote.source, textEn: quote.textEn, authorEn: quote.authorEn, createdAt: quote.createdAt)
          : quote;
      if (!mounted) return;
      setState(() {
        _dailyQuote = trimmed;
      });
    } catch (e) {
      // 后台跑: 失败就静默 (banner 已经显示 hardcoded pool), 不报错
      debugPrint('[Quote] 后台 LLM 失败 (静默, banner 仍显示): $e');
    }
  }

  // 7/15: 简化 — 不调 LLM, 走 hardcoded 池 (快), 返回 Quote struct
  void _loadNextQuote() {
    if (_quoteLoading) return;
    if (!mounted) return;
    setState(() {
      _quoteLoading = true;
      _dailyQuote = _streakService.getRandomQuoteSync(isEn: isEn);
      _quoteLoading = false;
    });
  }


  // 21:00: banner 保存抽出 (banner widget 搬到 SceneScreen 后, save 逻辑留 main.dart)
  Future<void> _onBannerSaveQuote(Quote quote) async {
    final now = DateTime.now();
    final quoteText = quote.text;
    final id = 'quote_${quoteText.hashCode}';
    final title = quote.author.isNotEmpty
        ? quote.author
        : (isEn ? 'AI Quote' : 'AI 名言');
    final descParts = <String>[quote.text];
    if (quote.source != null && quote.source!.isNotEmpty) {
      descParts.add('《${quote.source}》');
    }
    final desc = descParts.join(' — ');
    final item = ContentItem(
      id: id,
      title: title,
      description: desc,
      duration: isEn ? '1 min read' : '1 分钟阅读',
      source: isEn ? 'Daily Quote' : '每日名言',
      sourceType: ContentSource.rss,
      contentType: ContentType.card,
      lastReadAt: now,
    );
    try {
      await LocalSubscriptionService.instance.subscribe(item);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('quote_saved_${quoteText.hashCode}', true);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEn ? 'Saved to Favorites' : '已收藏到收藏'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: isEn ? 'View' : '查看',
            onPressed: () => navigateToMainTab(2),
          ),
        ),
      );
    } catch (e) {
      debugPrint('banner 保存失败: $e');
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
  // 6/30 12:11 WARNING: onboarding 已被 Brien 判定累赘, 代码强制跳过 (_showOnboarding=false)
  // 不要加任何 "恢复 onboarding" 的逻辑, 要恢复跟 Brien 确认
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

  Future<void> _loadSettings() async {
    final isInt = await _localeService.getIsInternational();
    final isElderly = await _localeService.getIsElderlyMode();
    final lang = await _localeService.getLanguageCode();
    final typeName = await _localeService.getSelectedUserTypeName();
    final items = await _subService.getSubscribedItems();
    final msg = await _streakService.getStreakMessage(isEn);
    // 6/30 11:55: 拉 RobotNameService 写回 notifier (修"刷新人名变默认" bug)
    await RobotNameService().get();
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
    if (_dailyQuote == null || _dailyQuote!.text.isEmpty) return;
    // 7/15 16:56 Q2: 跑 QuoteRelatedEngine 真关联, history 作为兜底
    List<RelatedHit> hits = [];
    try {
      hits = await QuoteRelatedEngine.findRelated(
        quote: _dailyQuote!,
        userType: _selectedUserType ?? UserType.officeWorker,
        scene: Scene.learn,
        isEn: isEn,
        limit: 6,
      );
    } catch (_) {/* engine 失败就 fallback */}

    // 兜底: history 7 天 抽 6 条
    List<HistoryItem> historyFallback = [];
    if (hits.isEmpty) {
      try {
        final all = await HistoryService.instance.getAll();
        final now = DateTime.now();
        historyFallback = all.where((h) {
          final t = DateTime.fromMillisecondsSinceEpoch(h.readAt);
          return now.difference(t).inDays <= 7;
        }).take(6).toList();
      } catch (_) {}
    }

    // 关键词 (kg 仍然走 LLM 现算, 显示在 chip)
    List<String>? llmKeywords;
    try {
      llmKeywords = await _getLLMKeywordsForQuote(_dailyQuote!.text);
    } catch (_) {
      llmKeywords = null;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _QuoteDetailSheet(
        recent: historyFallback, // 兜底用
        hits: hits, // 真关联优先
        isEn: isEn,
        quote: _dailyQuote,
        llmKeywords: llmKeywords,
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
                      color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.grey[100],
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
                // 21:00 banner 状态 + 回调 (传给 SceneScreen)
                dailyQuote: _dailyQuote,
                handle: _handle,
                isEn: isEn,
                onTapBannerDetail: _showQuoteDetailSheet,
                onNextQuote: () async { _loadNextQuote(); },
                onSaveQuote: (q) async { await _onBannerSaveQuote(q); },
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
                userType: _selectedUserType,
                scene: TimeAwareRecommender.recommendAt(DateTime.now(), currentUserType: _selectedUserType).scene,
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
          // 21:00 重构: 主页 banner + ↻ 都搬进 SceneScreen Column 顶部了
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
            // 8/16 修 (沿 SOUL #103): 用 public method 替代外部 setState (avoid protected warning)
            mainState.switchTab(index);
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
                        color: selected ? Colors.white : AppTheme.textDark.withValues(alpha: 0.65),
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
  final Quote? quote; // 7/15: 改 Quote 结构 (text/author/source/createdAt/textEn/authorEn)
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
          // 7/19 fix v2: LinearGradient 全量清除
          color: const Color(0xFF7C5CFC),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFC).withValues(alpha: 0.25),
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
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
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
                            color: Colors.white.withValues(alpha: 0.98),
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
                                      color: Colors.white.withValues(alpha: 0.78),
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
                        color: Colors.white.withValues(alpha: 0.95),
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
  // 21:00 banner 入参转发给 SceneScreen
  final Quote? dailyQuote;
  final String handle;
  final bool isEn;
  final VoidCallback onTapBannerDetail;
  final Future<void> Function() onNextQuote;
  final Future<void> Function(Quote) onSaveQuote;

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
    required this.dailyQuote,
    required this.handle,
    required this.isEn,
    required this.onTapBannerDetail,
    required this.onNextQuote,
    required this.onSaveQuote,
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
      // 21:00 banner 从 main.dart 移进 SceneScreen
      dailyQuote: dailyQuote,
      handle: handle,
      isEn: isEn,
      onTapBannerDetail: onTapBannerDetail,
      onNextQuote: onNextQuote,
      onSaveQuote: onSaveQuote,
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
  final List<RelatedHit> hits; // 7/15 16:56 Q2: 真关联 (hits 优先, recent 兜底)
  final bool isEn;
  final Quote? quote; // 7/15: Quote struct
  final List<String>? llmKeywords;
  final UserType? selectedUserType;
  const _QuoteDetailSheet({
    required this.recent,
    required this.hits,
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
                        contextQuote: quote?.text, // 7/15: sheet 传 Quote, AI 屏收 text
                        userType: selectedUserType, // 6/30 10:11: 帮推荐/答疑用
                        scene: TimeAwareRecommender.recommendAt(DateTime.now(), currentUserType: selectedUserType).scene, // 7/1 推荐兑底用

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
            // 7/15: 显示 Quote struct (主文 italic + 作者/出处小字)
            // 不用 spread 是 Dart 在 spread 里不传播 null promotion
            if (quote != null)
              Builder(builder: (ctx) {
                final q = quote!; // 上面 if (quote != null) 已掊, 这里 bang
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (q.author.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            q.author,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF333333)),
                          ),
                        ),
                      if (q.source != null && q.source!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '《${q.source}》',
                            // 8/4 修 #169 A1: 文字 Colors.grey[600] 暗色不可见
                            style: TextStyle(fontSize: 13, color: AppTheme.hintColor(context)),
                          ),
                        ),
                      Text(
                        '“${q.text}”',
                        // 8/4 修 #169 A1: 名言引用 Colors.grey[800] 暗色不可见, hintColor 亮色够浅
                        style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: AppTheme.hintColor(context), height: 1.5),
                      ),
                    ],
                  ),
                );
              }),
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
                      // 8/4 修 #169 A1: 文字 Colors.grey[600] 暗色不可见
                      style: TextStyle(fontSize: 11, color: AppTheme.hintColor(context)),
                    ),
                    ...llmKeywords!.map((kw) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFC).withValues(alpha: 0.1),
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
            // 7/15 16:56 Q2: hits (RelatedHit) 优先, recent (HistoryItem) 兜底
            if (hits.isNotEmpty)
              ...hits.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    elevation: 0,
                    color: h.fromLlm
                        ? Colors.amber.withValues(alpha: 0.08)
                        : const Color(0xFF7C5CFC).withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: h.externalUrl != null
                          ? () async {
                              try {
                                final uri = Uri.parse(h.externalUrl!);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
                                }
                              } catch (_) {}
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: h.fromLlm ? Colors.amber.shade700 : const Color(0xFF7C5CFC),
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                h.title,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey[600]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ))
            else
              ...recent.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  elevation: 0,
                  color: const Color(0xFF7C5CFC).withValues(alpha: 0.06),
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
                            // 8/4 修 #169 A1: 文字 Colors.grey[600] 暗色不可见
                            style: TextStyle(fontSize: 11, color: AppTheme.hintColor(context)),
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

// 7/15: main.dart 兑底 pool (如果 _streakService 崩了, 不至于 banner 显示不出来)
// 注: 完整 27 条 pool 在 motivation_service.dart 里的 _QuotePool, 这是子集兜底
class _QuotePoolFallback {
  static final zh = <Quote>[
    Quote(text: '竹杖芒鞋轻胜马，谁怕？一蓑烟雨任平生。', author: '苏轼', source: '定风波', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '长风破浪会有时，直挂云帆济沧海。', author: '李白', source: '行路难', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '采菊东篱下，悠然见南山。', author: '陶渊明', source: '饮酒·其五', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '行到水穷处，坐看云起时。', author: '王维', source: '终南别业', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '不畏浮云遮望眼，自缘身在最高层。', author: '王安石', source: '登飞来峰', createdAt: DateTime(2026, 1, 1)),
  ];
  static final en = <Quote>[
    Quote(text: 'The impediment to action advances action.', author: 'Marcus Aurelius', source: 'Meditations', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'We suffer more in imagination than in reality.', author: 'Seneca', source: 'Letters from a Stoic', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'No man is free who is not master of himself.', author: 'Epictetus', source: 'Discourses', createdAt: DateTime(2026, 1, 1)),
  ];
}
