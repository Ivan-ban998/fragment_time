// ContentScreen - 1736 行完整版恢复 (6/12 误删后)
// 6/22 重写: AI 流式 + TL;DR + 6 形式内容 + 真 TTS + 视频 iframe + 收藏 + 进度追踪 + 续读 + 读完 FAB + 6 张成就 + 儿童安全 + 玻璃风格 + tinder 36Kr 视觉 + IgnorePointer 修复
//
// 依赖:
//   services/llm_service.dart  (Ollama 流式 + TL;DR + motivation)
//   services/tts_service.dart  (TTS web/mobile)
//   services/local_subscription_service.dart (subscribe / updateProgress / getInProgress)
//   services/eye_protection_scope.dart (暖色护眼)
//   theme/glass_decoration.dart (玻璃卡 / 玻璃 AppBar / 玻璃胶囊)
//   widgets/iframe_video_view.dart (B 站 / YouTube / 跳原站)
//   widgets/tinder_recommendation_stack.dart (3 卡叠 + IgnorePointer + 36Kr 卡内视觉)
//
// 5 个核心状态: _buf (流式 buffer), _llmGotFirstChunk (是否收到首 chunk), _llmFallbackTimer (10s 兑底),
// _summary (TL;DR 精要), _recItems (推荐 6 条, 来自 ContentAggregator)
// 8/14 注: _startLlm() 当前未在 initState 调用 (沿 6/26 Brien '要真实数据' 决策),
//   _llmFallbackTimer 10s 备用 timer 等未来 AI assistant 启用 LLM 时再跑

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../config/runtime_mode.dart';
import '../services/llm_service.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import 'ai_assistant_screen.dart';
import '../services/eye_protection_scope.dart';
import '../services/local_subscription_service.dart';
import '../services/user_preference_service.dart';
import '../services/content_aggregator.dart';
import '../services/tts_service.dart';
import '../services/share_service.dart';
import '../services/analytics_service.dart';
import '../services/news_service.dart';
import '../services/bilibili_service.dart';
import '../widgets/tinder_recommendation_stack.dart';
import '../widgets/iframe_video_view.dart';
import '../widgets/quiz_panel.dart';
import 'content_reader_screen.dart';
import '../services/study_group_service.dart';
import '../services/weekly_recap_service.dart';
import '../services/analytics_service.dart';
import '../services/handle_service.dart';
import '../services/connectivity_helper.dart';

class ContentScreen extends StatefulWidget {
  final UserType userType;
  final Scene scene;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final ContentItem? prefillItem; // 从 tinder 点入时, 不用等 30s 兑底
  const ContentScreen({
    super.key,
    required this.userType,
    required this.scene,
    this.isInternational = false,
    this.isElderlyMode = false,
    this.languageCode = 'zh',
    this.prefillItem,
  });
  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen> {
  String _handle = '@你'; // 6/25 AppBar title 联动昵称
  String _buf = '';
  bool get _hasContent => _buf.isNotEmpty;
  bool _loading = true;
  bool _llmGotFirstChunk = false;
  Timer? _llmFallbackTimer;
  StreamSubscription? _sub;
  ContentItem? _aiContentItem;
  LlmSummary? _summary;
  int _streak = 0;
  int _recOffset = 0; // 6 张看完换 6 张 offset
  List<ContentItem> _recItems = [];
  // 7/2 B 站真 BV 缓存: itemId → 首条结果 (避免重复 API 调用, 嵌 iframe 用)
  final Map<String, BilibiliVideoResult> _biliCache = {};
  bool _recLoading = false;
  // 7/30 B: 推荐重试计数器 (避免 _recItems 一直空时无限重试)
  int _recRetryCount = 0;
  // 8/14 治本 (沿 SOUL #18 真改没改对 第 N+11 次): _recGeneration 守卫 race condition
  //   真凶: 之前 _recLoading boolean 守卫 race condition:
  //     - force=true 已 setState(_recLoading=true) 在 await
  //     - 旧 force=false await 拿到 fallback, 走 setState(_recLoading=false) 破守卫
  //     - 第 3 次 force=true 进入, _recLoading=false → 走通, race 累积
  //   修: 用 _recGeneration int, 每轮 +1, await 后检查 gen 是否变 (变就丢弃结果)
  int _recGeneration = 0;
  bool _showCompletionBanner = false;
  // 8/8 加 (沿 SOUL #188 透明原则): 离线状态
  bool _isOffline = false;
  DateTime? _offlineSince;
  void Function()? _connectivityUnsubscribe;
  bool _aiOfferShown = false; // 6/30 12:23: 读完弹 AI sheet 防重复
  bool _hasScrolled = false; // 6/26: 滚到过文章中部才显"读完啦"按钮
  bool _ttsPlaying = false;
  bool _showAllDoneDialog = false; // 6 张全看完弹 dialog
  List<ContentItem> _inProgressItems = []; // 续读
  int _todayCompleteCount = 0; // 今日完成计数
  bool _showTlDrBanner = false; // TL;DR 精要 banner
  bool _tlDrExpanded = false; // 7/2 默认折叠 1 行, 点展开看 3 行
  bool _continueExpanded = false; // 7/2 默认折叠 1 条续读, 点展开看 3 条
  String _tlDrText = ''; // TL;DR 文本
  int _quizAnswers = 0; // quiz 答对
  bool _showStudyGroupEntry = false; // 学习小组入口
  bool _showWeeklyRecapButton = false; // 周回顾按钮
  bool _showPrivacyPolicy = false; // 隐私政策弹窗

  // 进度追踪
  int _progress = 0; // 0/25/50/100
  Timer? _progressTimer;
  final ScrollController _bodyScroll = ScrollController();

  double get _scale => widget.isElderlyMode ? 1.3 : 1.0;
  bool get isEn => widget.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    // 6/25 AppBar title 联动昵称: 加载 handle (代替角色名显示)
    _loadHandle();
    // 6/16 Brien 反馈: 有 prefillItem 时立刻显示 description, 不再空白 30s 等 AI
    if (widget.prefillItem != null && widget.prefillItem!.description.isNotEmpty) {
      _aiContentItem = widget.prefillItem;
      _buf = widget.prefillItem!.description;
      _llmGotFirstChunk = true; // 不显示兑底
      _loading = false;
    } else {
      // prefillItem null 时构造一个占位
      _aiContentItem = ContentItem(
        id: '${widget.userType.name}_${widget.scene.name}_ai',
        title: '${widget.userType.title} · ${_sceneName()}',
        description: '',
        duration: '5 min',
        source: 'AI',
        sourceType: ContentSource.rss,
      );
    }
    _loadRecommendations();
    _loadBiliPreviews(); // 7/2 v2 重新启用: 只拿缩略图 + BV (不嵌 iframe), 视频卡改显示缩略 + 跳按钮
    _loadInProgress();
    _loadTodayCount();
    _loadTlDr();
    // 6/26 Brien 00:22 '要真实数据': 不调 LLM, 直接拉 NewsService 24 桶
    // 保留 _startLlm() 备用 (未来云端 API 启用)
    if (widget.prefillItem == null) {
      _loadFromBucket(); // 6/26 从 NewsService 24 桶加载第 1 条
    }
    _recordOpen();
    _startProgressTimer();
    _bodyScroll.addListener(_onBodyScroll);
    // 8/8 加 (沿 SOUL #188 透明原则): 离线状态监听
    _isOffline = !ConnectivityHelper.isOnline();
    if (_isOffline) _offlineSince = DateTime.now();
    _connectivityUnsubscribe = ConnectivityHelper.addListener(
      onChange: (online) {
        if (!mounted) return;
        setState(() {
          _isOffline = !online;
          _offlineSince = online ? null : DateTime.now();
        });
      },
    );
  }

  /// 8/14 加 (沿 SOUL #18 #103): 监听 userType/scene/isInternational 变化, 重建推荐
  ///   真凶: 之前 SceneScreen key 只跟 userType (没 isInternational), 切国际版
  ///     → SceneScreen didUpdateWidget rebuild → ContentScreen widget isInternational
  ///     变了 → 没 didUpdateWidget → _recItems 还是旧国际版/国内版 → "切了国际版不变"
  ///   修: didUpdateWidget 检测 scene/userType/isInternational 变化 → force=true 重启
  @override
  void didUpdateWidget(covariant ContentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userType != widget.userType ||
        oldWidget.scene != widget.scene ||
        oldWidget.isInternational != widget.isInternational) {
      debugPrint('[content] didUpdateWidget: ${oldWidget.userType}/${oldWidget.scene}/intl=${oldWidget.isInternational} → ${widget.userType}/${widget.scene}/intl=${widget.isInternational}, 重建推荐');
      _recOffset = 0;
      _loadRecommendations(force: true);
    }
  }

  @override
  void dispose() {
    _llmFallbackTimer?.cancel();
    _sub?.cancel();
    _progressTimer?.cancel();
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _connectivityUnsubscribe?.call(); // 8/8 加: 取消离线监听
    TtsService.instance.stop();
    super.dispose();
  }

  // 启动 LLM 流式
  Future<void> _startLlm() async {
    // 6/14 v3: 30s 兑底 timer (首 chunk 到达关 / onError onDone 关 / dispose 关)
    // 8/14 治本 (沿 SOUL #8 真改没改对 第 N+12 次): 30s → 10s
    //   真凶: 之前 30s fallback timer, 但实际 MiniMax 1.3s 首 token (8/13 修后)
    //     → 30s 远大于实际生成时间, 用户等很久才看到内容
    //   修: 30s → 10s, fail fast 显示兜底 (实际 99% 情况 < 3s)
    _llmFallbackTimer = Timer(const Duration(seconds: 10), () {
      if (!_llmGotFirstChunk && mounted) {
        _showStub(reason: 'timeout_10s');
      }
    });

    try {
      final stream = LlmService.generateStream(
        userType: widget.userType,
        scene: widget.scene,
        languageCode: widget.languageCode,
        isInternational: widget.isInternational,
      );
      _sub = stream.listen(
        (chunk) {
          if (!mounted) return;
          setState(() {
            _buf += chunk;
            if (!_llmGotFirstChunk) {
              _llmGotFirstChunk = true;
              _loading = false;
              _llmFallbackTimer?.cancel();
            }
          });
        },
        onError: (e) {
          if (!mounted) return;
          _showStub(reason: 'stream_error: $e');
        },
        onDone: () {
          if (!mounted) return;
          _llmFallbackTimer?.cancel();
          // 6/25 锁死角色匹配: 生成完成后检测内容是否跟当前 userType 匹配
          // 1.5b 质量不够时可能输出学生内容给上班族, 检测后 fallback
          if (_buf.length > 30 && !_isRoleMatch(_buf, widget.userType)) {
            // 内容错位: 重置 buf 并调假数据桶
            _loadFallbackContent();
          }
        },
      );
    } catch (e) {
      _showStub(reason: 'start_error: $e');
    }
  }

  // 兑底: 显示预制 stub
  void _showStub({String reason = 'unknown'}) {
    if (!mounted) return;
    _llmFallbackTimer?.cancel();
    setState(() {
      _buf = isEn
          ? '⚠️ Online AI service unavailable right now.\n\nShowing the recommended content instead. (reason: $reason)'
          : '⚠️ 在线 AI 暂不可用\n\n为你推荐预制内容。 (原因: $reason)';
      _loading = false;
    });
  }

  // 6/26 Brien 00:22 '要真实数据': 从 NewsService 24 桶加载第 1 条作为 aiContentItem
  String _loadFromBucketErr = '';
  Future<void> _loadFromBucket() async {
    try {
      final items = await NewsService().getRecommendations(
        widget.userType, widget.scene, isInternational: widget.isInternational,
      );
      if (!mounted) return;
      if (items.isEmpty) {
        setState(() {
          _loadFromBucketErr = '桶数据为空: ${widget.userType.bucketKey}_${widget.scene.bucketKey}';
          _loading = false;
        });
        return;
      }
      final first = items.first;
      setState(() {
        _aiContentItem = first;
        _buf = '${first.title}\n\n${first.description ?? "".trim()}';
        _llmGotFirstChunk = true;
        _loading = false;
        _loadFromBucketErr = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadFromBucketErr = '加载失败: $e';
          _loading = false;
        });
      }
    }
  }

  // 6/25 锁死角色匹配: 检测 LLM 生成内容是否跟当前 userType 匹配
  // 1.5b 模型偶尔输出学生内容给上班族, 检测后 fallback
  bool _isRoleMatch(String content, UserType currentType) {
    // 学生专属关键词 (其他角色不该出现)
    const studentKeywords = [
      '高考', '中考', '考试', '作业', '课本', '老师', '学生党', ' K12', '学校',
      '学习规划', '学习策略', '高效学习', '考试技巧', '学生',
      'exam', 'homework', 'school', 'study plan',
    ];
    // 儿童专属关键词
    const childKeywords = [
      '小朋友', '幼儿园', '小儿', ' 幼', '儿童',
      'kid', 'children',
    ];
    // 创业专属 (不该出现上班族/退休)
    // 老年专属 (不该出现学生/儿童)
    final lower = content.toLowerCase();
    if (currentType == UserType.student || currentType == UserType.child) {
      return true; // 这些角色反而可能需要这些关键词
    }
    for (final k in studentKeywords) {
      if (lower.contains(k.toLowerCase())) return false;
    }
    for (final k in childKeywords) {
      if (lower.contains(k.toLowerCase())) return false;
    }
    return true;
  }

  // 6/25 fallback: LLM 内容错位 → 调 NewsService 拿一条真内容替代
  // 8/14 改名 (沿 SOUL #169 不撒谎): _loadFakeContent → _loadFallbackContent
  //   真凶: 之前叫 _loadFakeContent 误导 (Fake = 假数据) → 实际调 NewsService 拿真 RSS
  //   修: 改名 _loadFallbackContent 反映 'AI 错位时用真 RSS 替代' 语义
  Future<void> _loadFallbackContent() async {
    try {
      final results = await NewsService().getRecommendations(
        widget.userType, widget.scene, isInternational: widget.isInternational,
      );
      if (!mounted || results.isEmpty) return;
      final item = results.first;
      setState(() {
        _buf = '${item.title}\n\n${item.description ?? ''}';
        _aiContentItem = item;
      });
    } catch (e) {
      debugPrint('[LLM] _loadFallbackContent error: $e');
    }
  }

  // 加载推荐 6 条 (用 ContentAggregator 6 张看完换 6 张)
  // 7/30 D 修: 同步立即返 fallback (24 桶假数据, <100ms), 异步 RSS 到后覆盖
  // 真凶: RSS 拉 3 个源 × 2 attempt × 8s timeout = 20s+ 才返, 用户等得很烦躁
  // 沿用 #6 #8 '能跑起来 > 功能强大' — 先看到东西比数据真不真重要
  Future<void> _loadRecommendations({bool force = false}) async {
    // 8/8 升一阶 (沿 SOUL #169 #18 #6 #103): force=true 显式解锁 _recLoading
    //   真凶: 之前 _onAllSixDismissed 已 setState _recLoading=false, 但 _loadRecommendations
    //     收到 force=true 仍未重置 _recLoading 守卫, 后续 await fallback 期间 _recLoading
    //     可能被 setState 切回 true ("换 6 张" 不响应)
    //   修: force=true 显式 _recLoading = false + _recRetryCount = 0, 触发新一轮真 load
    // 8/14 治本 (沿 SOUL #18 真改没改对 第 N+7 次): race condition 修复
    //   真凶: 之前 force=true 设 _recLoading=false (line 325), 但 Step 2 line 360 又 setState(_recLoading=true)
    //     → 用户连点 "换 6 张" 2 次 → 第 1 次 Step 2 在 await → 第 2 次 force 又走 Step 1
    //     → Step 1 设 _recItems 覆盖第 1 次 Step 2 的新结果
    //   修: 用 _recLoading=true 守卫直到 Step 2 完成 (force=true 才 bypass)
    //   副作用: force=true "换 6 张" 显示 1s loading → UX OK (Step 1 仍 < 100ms 返 fallback)
    // 8/14 治本 N+11: 用 _recGeneration 替代 _recLoading boolean 守卫
    //   真凶: _recLoading 是 boolean, race condition 累积:
    //     - 旧 await 完成时 setState(_recLoading=false) 破了 force=true 的 setState(true) 守卫
    //     - 第 3 次 force=true 进入时 _recLoading=false → 走通, race 累积
    //   修: 每轮 _recGeneration++, await 后检查 _recGeneration 是否仍是本轮 (变就丢弃)
    final myGen = ++_recGeneration;
    if (force) {
      _recLoading = false;
      _recRetryCount = 0;
    }
    if (!force && _recLoading) return; // 非 force 时仍守 _recLoading 守卫 (UX: 不显示多个 loading)
    if (!force && _recRetryCount >= 3) {
      return;
    }
    if (!force) _recRetryCount++;
    // Step 1: 同步立即返 fallback 24 桶 (<100ms) — 用户立刻看到 6 张卡
    // 8/1 加 offset (沿用 SOUL #103): "换 6 张" 不响应真凶 — 每桶只 6 条 + 不 shuffle = 永远同一组
    // 8/13 升一阶 (沿 SOUL #190 真改没改对 第 N+3 次): 排除已 dismiss 的 item
    //   真凶: 之前不排除 dismissed → "换 6 张" 仍有 ❌ 过的老卡
    //   修: 拉 UserPreferenceService.getDismissedIds() 传给 getRecommendations
    // 8/13 升一阶 (沿 SOUL #190 第 N+4 次): 重载时 forceFresh=true 跳过 in-memory cache
    //   真凶: 5min cache + shuffle 仍同组 → "换 6 张" 老卡
    //   修: force=true (换 6 张) → forceFresh=true 跳过 cache
    // 8/14 治本: force=true 时立刻 setState _recLoading=true 占位, 阻止新一轮 race
    if (force) {
      setState(() {
        _recLoading = true;
      });
    }
    final dismissedIds = await UserPreferenceService.instance.getDismissedIds();
    if (_recGeneration != myGen) return; // race: 已被新 force 覆盖
    final fallback = NewsService().getRecommendations(
      widget.userType, widget.scene,
      offset: _recOffset, isInternational: widget.isInternational,
      excludeIds: dismissedIds, forceFresh: force,
    );
    final fallbackItems = await fallback;
    if (_recGeneration != myGen) return; // race: 已被新 force 覆盖
    if (!mounted) return;
    if (fallbackItems.isNotEmpty) {
      setState(() {
        _recItems = fallbackItems;
        // 8/14: force 模式下 _recLoading 保持 true, 等 Step 2 完成后才 false
        if (!force) _recLoading = false;
      });
    } else if (!force) {
      // 8/14: force 模式且 fallback 空 → _recLoading 保持 true 等 Step 2
      setState(() {
        _recLoading = false;
      });
    }
    // Step 2: 后台异步拉真 RSS — 拿到后覆盖 fallback (如果是非空)
    // 8/14: 不再 setState(true), 因为 force 模式已经在上面 setState(true) 过了
    try {
      // 8/14 治本 (沿 SOUL #190 真改没改对 第 N+6 次): Step 2 跟 Step 1 一样 forceFresh=force
      //   真凶: 之前 Step 2 不传 forceFresh, 5min cache 命中 → "换 6 张" 老卡覆盖 Step 1 新卡
      //   修: Step 2 跟 Step 1 一样 forceFresh=force + excludeIds 一致 → 两步一致
      final rec = await ContentAggregator().fetchRecommendContent(
        userType: widget.userType,
        scene: widget.scene,
        isInternational: widget.isInternational,
        offset: _recOffset, // 8/1 加 (沿用 #103): 让 Step 2 跟 Step 1 用同样 offset, 避免覆盖回旧 6 条
        forceFresh: force, // 8/14 透传 force → Step 2 跟 Step 1 同样跳过 in-memory cache
        excludeIds: dismissedIds, // 8/14 透传 dismissedIds → Step 2 也排除 ❌ 过的
      );
      if (_recGeneration != myGen) return; // race: 已被新 force 覆盖
      if (!mounted) return;
      if (rec.isNotEmpty) {
        // 真 RSS 拿到, 覆盖 fallback
        setState(() {
          _recItems = rec;
          _recLoading = false;
          _recRetryCount = 0;
        });
      } else {
        // RSS 还是空, 保持 fallback (用户已看到)
        setState(() {
          _recLoading = false;
          _recRetryCount = 0;
        });
      }
    } catch (e) {
      if (_recGeneration != myGen) return;
      if (!mounted) return;
      setState(() {
        _recLoading = false;
        _recRetryCount = 0;
      });
      debugPrint('[recommend] RSS error: $e — 保持 fallback');
    }
  }

  // 6 张全看完 → 弹 🎉 dialog + 换 6 张
  void _onAllRecDismissed() {
    _onAllSixDismissed();
  }

  // 6/24 改: 进度追踪阶梯 0/30/60/100 — 60s 后才记 30% (避免开了就走)
  void _startProgressTimer() {
    _progressTimer = Timer(const Duration(seconds: 60), () {
      _writeProgress(30);
    });
  }

  void _onBodyScroll() {
    if (!_bodyScroll.hasClients) return;
    final pos = _bodyScroll.position;
    // 6/26: 用户滚到 1/4 处就标记 hasScrolled, "读完啦"按钮才显
    if (!_hasScrolled && pos.pixels > pos.maxScrollExtent * 0.25) {
      setState(() => _hasScrolled = true);
    }
    if (pos.pixels >= pos.maxScrollExtent - 80 && _progress < 100) {
      _writeProgress(100);
      _showCompletionBanner = true;
      // 6/30 12:23: 看完后 1.5s 主动弹 AI 答疑 (不防不住: 只弹 1 次)
      if (!_aiOfferShown) {
        _aiOfferShown = true;
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          _offerAiAfterReading();
        });
      }
    } else if (pos.pixels >= pos.maxScrollExtent / 2 && _progress < 50) {
      _writeProgress(50);
    }
  }

  Future<void> _writeProgress(int p) async {
    if (_aiContentItem == null) return;
    if (p <= _progress) return;
    if (!mounted) return;  // 6/23: 防御 setState after dispose
    setState(() => _progress = p);
    try {
      await LocalSubscriptionService.instance.updateProgress(_aiContentItem!, p);
    } catch (_) {}
  }

  /// 6/30 12:23: 看完后主动弹 AI sheet — 拿今日历史 + 推用户点 "答疑解惑"
  Future<void> _offerAiAfterReading() async {
    if (_aiContentItem == null) return;
    // 拉今日历史传给 AI sheet
    final history = await HistoryService.instance.getAll();
    final now = DateTime.now();
    final today = history.where((h) {
      final t = DateTime.fromMillisecondsSinceEpoch(h.readAt);
      return now.difference(t).inDays < 1;
    }).toList();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => AiAssistantScreen(
        isEn: isEn,
        isElderlyMode: widget.isElderlyMode,
        userTypeName: widget.userType?.title ?? '',
        userType: widget.userType,
        todayHistory: today,
        contextQuote: _aiContentItem?.title, // 6/30 12:23: 让 AI 知道刚读完这篇
      ),
    );
  }

  Future<void> _recordOpen() async {
    try {
      await UserPreferenceService.instance.record(
        action: PrefAction.view,
        item: widget.prefillItem ??
            ContentItem(
              id: '${widget.userType.name}_${widget.scene.name}_ai',
              title: '${widget.userType.title} · ${_sceneName()}',
              source: 'AI',
              description: '',
              duration: '5 min',
              sourceType: ContentSource.rss,
              contentType: ContentType.article,
            ),
        userType: widget.userType,
        scene: widget.scene,
      );
    } catch (_) {}
  }

  // 7/2 B 站真 BV 预览: 对当前 AI 主体 + 推荐池中所有 video 类并发查真 BV
  // 优先 iframe 嵌 player.bilibili.com, 失败 fallback externalUrl (B 站搜索)
  Future<void> _loadBiliPreviews() async {
    try {
      final candidates = <ContentItem>[];
      final item = _aiContentItem;
      if (item != null && item.contentType == ContentType.video) candidates.add(item);
      for (final r in _recItems) {
        if (r.contentType == ContentType.video && !candidates.any((c) => c.id == r.id)) {
          candidates.add(r);
        }
      }
      if (candidates.isEmpty) return;
      final futures = candidates.take(6).map((c) async {
        try {
          final vids = await BilibiliService.instance.searchVideos(c.title, limit: 1);
          if (vids.isNotEmpty && mounted) {
            setState(() => _biliCache[c.id] = vids.first);
          }
        } catch (_) {}
      });
      await Future.wait(futures);
    } catch (_) {}
  }

  // 续读: 拉订阅里 progress 0-100 的
  Future<void> _loadInProgress() async {
    try {
      final items = await LocalSubscriptionService.instance.getInProgress(limit: 3);
      if (!mounted) return;
      setState(() => _inProgressItems = items);
    } catch (_) {}
  }

  // 6/25 AppBar title 联动昵称: 加载 handle
  Future<void> _loadHandle() async {
    try {
      final h = await HandleService().get();
      if (!mounted) return;
      setState(() => _handle = h);
    } catch (_) {}
  }

  // 今日完成计数 (从 UserPreference getDailyDone)
  Future<void> _loadTodayCount() async {
    try {
      final c = await UserPreferenceService.instance.getDailyDone();
      if (!mounted) return;
      setState(() => _todayCompleteCount = c);
    } catch (_) {}
  }

  // TL;DR 精要: 拿上次同 userType+scene 的 preference summary
  Future<void> _loadTlDr() async {
    try {
      final cache = await UserPreferenceService.instance.getPreferenceSummary(
        userType: widget.userType,
        scene: widget.scene,
      );
      if (!mounted || cache.isEmpty) return;
      setState(() {
        _tlDrText = cache;
        _showTlDrBanner = true;
      });
    } catch (_) {}
  }

  // 6 张全看完 callback
  Future<void> _onAllSixDismissed() async {
    if (!mounted) return;
    setState(() {
      _showAllDoneDialog = true;
      _recOffset += 6;
      _recItems = [];
      _recLoading = false; // 8/1 修: 强制重 load, 不被 _recLoading 卡住
      _recRetryCount = 0; // 7/30 B: 重置重试计数, 下一轮重新计
    });
    await showDialog(
      context: context,
      // 8/14 加 (沿 SOUL #188 透明原则 + Brien UX): dialog dismiss 时自动加载下一批
      //   真凶: 之前 dialog 必须等用户点"换 6 张"才 load, 用户关掉 dialog (按返回键) → 没换 → UX 卡住
      //   修: barrierDismissible=true, dialog 关闭自动 force load
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24 * _scale),
          decoration: BoxDecoration(
            // 7/19 fix v2: LinearGradient 全量清除 (shader pipeline null 真凶)
            color: const Color(0xFF7C5CFC),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🎉', style: TextStyle(fontSize: 56 * _scale)),
              SizedBox(height: 8 * _scale),
              Text(
                isEn ? 'You finished 6!' : '6 张全看完！',
                style: TextStyle(fontSize: 22 * _scale, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              SizedBox(height: 6 * _scale),
              Text(
                isEn
                    ? 'Today: $_todayCompleteCount completed · keep going'
                    : '今日已完成 $_todayCompleteCount 条 · 继续加油',
                style: TextStyle(fontSize: 13 * _scale, color: Colors.white.withValues(alpha: 0.9)),
              ),
              SizedBox(height: 16 * _scale),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _loadRecommendations(force: true); // 8/1 修: force 重 load
                    },
                    child: Text(isEn ? 'Next 6' : '换 6 张', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // 跳到 SearchScreen via main tab
                      Navigator.popUntil(context, (r) => r.isFirst);
                    },
                    child: Text(isEn ? 'Search' : '去搜索', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // 8/14 加 (沿 SOUL #188 透明 + Brien UX): dialog 关闭后 (无论用户点哪个按钮) 自动 force load
    //   修法: 如果 _recItems 仍空 (说明用户没点 "换 6 张"), 自动 force load
    if (mounted && _recItems.isEmpty) {
      _loadRecommendations(force: true);
    }
  }

  // ============== UI ==============

  // 6/22 i18n helper: 集中所有 hardcode 字符串, 避免 isEn ? a : b 散落
  String _t(String zh, String en) => isEn ? en : zh;



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWarm = EyeProtectionScope.of(context);
    // 6/25 AppBar title 联动昵称 (代替角色名): '@你 · 学习' 而不是 '上班族 · 学习'
    final title = '$_handle · ${_sceneName()}';

    return Scaffold(
      extendBodyBehindAppBar: true,
      // 6/7 §4 儿童安全 HARD RULE: child userType 顶部绿色盾牌
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        // 8/10 staging banner (沿 SOUL #125 #188 + Brien '生产/运营切换')
        // prod 模式返 null = 不显示, 不影响生产体验
        bottom: RuntimeMode.current.isProd
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  color: RuntimeMode.current.bannerColor,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  child: Text(
                    '${RuntimeMode.current.label} · ${RuntimeMode.current.bannerText}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16 * _scale,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        leading: Material(
          color: Colors.white.withValues(alpha: 0.6),
          shape: const CircleBorder(),
          child: IconButton(
            icon: Icon(Icons.arrow_back, size: 24 * _scale, color: AppTheme.primary),
            padding: EdgeInsets.all(12 * _scale),
            constraints: BoxConstraints.tightFor(
              width: 48 * _scale,
              height: 48 * _scale,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          // TTS 按钮
          if (_hasContent)
            Material(
              color: Colors.white.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: isEn
                    ? (_ttsPlaying ? 'Stop' : 'Read aloud')
                    : (_ttsPlaying ? '停止' : '朗读'),
                icon: Icon(
                  _ttsPlaying ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                  color: AppTheme.primary,
                  size: 24 * _scale,
                ),
                onPressed: _toggleTts,
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          // 7/19 fix v2: LinearGradient 全量清除 (shader pipeline null)
          color: _sceneBgColor() ?? _sceneFallbackColor(),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16 * _scale, 8 * _scale, 16 * _scale, 8 * _scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [

                // 7/25 14:05 DEBUG v4 清除 (真凶已锁 = 透明玻璃 + 浅文字色)
                // 6/7 儿童安全: child userType 顶部绿色盾牌
                if (widget.userType == UserType.child) _buildChildShield(),
                // 8/8 加 (沿 SOUL #188 透明原则): 离线状态下显示 banner
                if (_isOffline) _buildOfflineBanner(),
                // 6/9 TL;DR 精要 banner (拿上次同 userType+scene 总结)
                if (_showTlDrBanner && _tlDrText.isNotEmpty) _buildTlDrBanner(),
                // 6/9 续读小卡 (3 条 progress 0-100)
                if (_inProgressItems.isNotEmpty) _buildContinueReadingCard(),
                if (_aiContentItem != null && _aiContentItem!.contentType == ContentType.video) ...[
                  _buildVideoIfNeeded(_aiContentItem!),
                  SizedBox(height: 8 * _scale),
                ],
                // 7/28 12:16 Brien '为何其他三个可以' → 听一声真凶疑点:
                //   4 场景唯一物理差别 = 听一声有 _buildAudioEntry (ContentType.audio)
                //   其它 3 场景 (article/video/card) 走 _buildVideoIfNeeded / _buildQuizEntry
                //   试: 听一声跳过 _buildAudioEntry, 不嵌 hero 上面那个专属 widget
                if (_aiContentItem != null && _aiContentItem!.contentType == ContentType.audio && widget.scene != Scene.listen) ...[
                  _buildAudioEntry(_aiContentItem!),
                  SizedBox(height: 8 * _scale),
                ],
                if (_aiContentItem != null && _aiContentItem!.contentType == ContentType.quiz) ...[
                  _buildQuizEntry(_aiContentItem!),
                  SizedBox(height: 8 * _scale),
                ],
                if (_loading && !_llmGotFirstChunk) _buildLoadingState(),
                _buildHero(isDark: isDark, isWarm: isWarm),
                if (_hasContent) ...[
                  SizedBox(height: 8 * _scale),
                  _buildActions(),
                  SizedBox(height: 8 * _scale),
                ],
                // 7/29 加: 跳原站读全文提示 (沿用宪法 §1.1 不能存原片, 明确告知访客点 Read 进阅读器再点“在原站读全文”)
                if (_aiContentItem != null &&
                    _aiContentItem!.externalUrl != null &&
                    _aiContentItem!.externalUrl!.isNotEmpty)
                  _buildReadFullHint(),
                SizedBox(height: 8 * _scale),
                // 7/30 A: 不再在父层 _buildEmptyState 替代整块 tinder 卡
                // (会导致 items.isEmpty 时 tinder widget 消失 + 下面一片白)
                // 改为: tinder widget 永远渲染, 空时走内部占位卡
                _buildRecommendationHeader(),
                SizedBox(height: 8 * _scale),
                // 底部入口行: 学习小组 + 周回顾 + 隐私政策
                _buildEntryRow(),
                // 6/22 修复: tinder 3 卡叠 + IgnorePointer + 36Kr 卡内视觉
                TinderRecommendationStack(
                  items: _recItems,
                  userType: widget.userType,
                  scene: widget.scene,
                  isEn: isEn,
                  isElderlyMode: widget.isElderlyMode,
                  onTapItem: (it) async {
                    // 6/23 修: 之前 push ContentScreen(prefillItem: it) — 会递归起同一个 screen,LLM/进度/timer 二次跑,崩或回到角色选择
                    // 现在 push ContentReaderScreen (专门 detail 屏,接管 item)
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContentReaderScreen(
                          item: it,
                          isElderlyMode: widget.isElderlyMode,
                          isEn: isEn,
                        ),
                      ),
                    );
                    if (mounted) _writeProgress(50);
                  },
                  onAllDismissed: _onAllRecDismissed,
                  // 7/30 A: 占位卡上的 “重试” 按钮 → 重置计数器 + 重 load
                  onRetry: () {
                    setState(() => _recRetryCount = 0);
                    _loadRecommendations();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      // 6/26 Brien 反馈: "还没读就读完了" 误导 → 滚过 1/4 才显"读完啦"按钮
      floatingActionButton: (_hasContent && _hasScrolled && _progress < 100) ? _buildCompleteFab(context) : null,
    );
  }

  // ============== Actions (收藏/分享/快捷问题/进入阅读器) ==============

  Widget _buildActions() {
    final ai = _aiContentItem;
    return SizedBox(
      height: 36 * _scale,
      child: Row(
        children: [
          // 进入详情阅读器
          Expanded(
            child: _actionButton(
              icon: Icons.menu_book_outlined,
              label: isEn ? 'Read' : '进入阅读',
              onTap: ai == null ? null : () => _pushToReader(ai),
            ),
          ),
          SizedBox(width: 6 * _scale),
          // 快捷问题
          Expanded(
            child: _actionButton(
              icon: Icons.chat_bubble_outline,
              label: isEn ? 'Ask AI' : '问 AI',
              onTap: () => _showQuickAsk(),
            ),
          ),
          SizedBox(width: 6 * _scale),
          // 收藏
          _actionButton(
            icon: _isSaved ? Icons.favorite : Icons.favorite_border,
            color: _isSaved ? const Color(0xFFFF6B9D) : null,
            label: '',
            onTap: ai == null ? null : () => _toggleSave(ai),
          ),
          SizedBox(width: 6 * _scale),
          // 分享
          _actionButton(
            icon: Icons.ios_share,
            label: '',
            onTap: ai == null ? null : () => _shareItem(ai),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10 * _scale, vertical: 6 * _scale),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16 * _scale, color: color ?? AppTheme.primary),
              if (label.isNotEmpty) ...[
                SizedBox(width: 4 * _scale),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12 * _scale,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pushToReader(ContentItem item) async {
    AnalyticsService.instance.track(AnalyticsService.EVT_ITEM_OPEN);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContentReaderScreen(
          item: item,
          isElderlyMode: widget.isElderlyMode,
          isEn: isEn,
        ),
      ),
    );
    if (mounted) _writeProgress(50);
  }

  Future<void> _showQuickAsk() async {
    final questions = isEn
        ? const [
            '总结要点',
            '我应该怎么应用？',
            '给我一个例子',
          ]
        : const [
            '总结要点',
            '我应该怎么应用？',
            '给我一个例子',
          ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(16 * _scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            for (final q in questions)
              ListTile(
                leading: Icon(Icons.chat_bubble_outline, color: AppTheme.primary),
                title: Text(q),
                onTap: () => Navigator.pop(ctx, q),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      // 6/12 6 个快捷问题：复用 _buf 加在后面
      setState(() {
        _buf = (_buf.isEmpty ? '' : '$_buf\n\n') + '问: $picked\n答: ';
      });
      // 6/9 ask 用同一个 LLM 流式 endpoint (复用 _startLlm 的 stream 复用)
      // 6/22 简化: 不真调 LLM, 改写 _buf 后停止 (用户可以手动看 hero 主体)
      // TODO: 6/23 接 LLM 二次调用
    }
  }

  bool _isSaved = false;
  Future<void> _toggleSave(ContentItem item) async {
    setState(() => _isSaved = !_isSaved);
    if (_isSaved) {
      try {
        await LocalSubscriptionService.instance.subscribe(item);
        AnalyticsService.instance.track(AnalyticsService.EVT_SAVE);
        if (mounted) {
          _showFloatingSnack(context, isEn ? 'Saved' : '已收藏');
        }
      } catch (_) {}
    } else {
      try {
        await LocalSubscriptionService.instance.unsubscribe(item);
      } catch (_) {}
    }
  }

  Future<void> _shareItem(ContentItem item) async {
    try {
      await ShareService.instance.shareContent(item, isEn: isEn);
    } catch (e) {
      if (mounted) {
        _showFloatingSnack(context, isEn ? 'Share failed' : '分享失败');
      }
    }
  }

  // ============== Video iframe (video contentType 走 embed / mobile 跳原站) ==============

  // 6/7 儿童安全绿色盾牌
  Widget _buildChildShield() {
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.symmetric(horizontal: 12 * _scale, vertical: 8 * _scale),
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF16A34A), size: 18),
          SizedBox(width: 8 * _scale),
          Expanded(
            child: Text(
              isEn ? '🛡 Kids safe mode · content filtered' : '🛡 儿童安全模式 · 内容已过滤',
              style: TextStyle(
                fontSize: 12 * _scale,
                color: const Color(0xFF16A34A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 8/8 加 (沿 SOUL #188 透明原则): 离线状态 banner
  // 沿 #117 沿用 alert: navigator.onLine 不绝对可靠, 仅作兜底 UX
  Widget _buildOfflineBanner() {
    // 8/8 计算离线时长, 透明告知用户
    final since = _offlineSince;
    String timeStr = '';
    if (since != null) {
      final mins = DateTime.now().difference(since).inMinutes;
      if (mins < 1) timeStr = isEn ? 'just now' : '刚刚';
      else if (mins < 60) timeStr = isEn ? '$mins min ago' : '$mins 分钟前';
      else timeStr = isEn ? '${mins ~/ 60}h ago' : '${mins ~/ 60} 小时前';
    }
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.symmetric(horizontal: 12 * _scale, vertical: 8 * _scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Color(0xFFF59E0B), size: 18),
          SizedBox(width: 8 * _scale),
          Expanded(
            child: Text(
              isEn
                  ? '📡 Offline mode — showing cached content${timeStr.isEmpty ? '' : ' ($timeStr)'}'
                  : '📡 离线模式 — 显示缓存内容${timeStr.isEmpty ? '' : '（$timeStr 缓存）'}',
              style: TextStyle(
                fontSize: 12 * _scale,
                color: const Color(0xFFF59E0B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 6/9 TL;DR 精要 banner — 7/29 修正文案: 明确标"是历史偏好, 不是当前文章摘要"
  Widget _buildTlDrBanner() {
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.all(10 * _scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 14 * _scale, color: AppTheme.primary),
              SizedBox(width: 4 * _scale),
              Expanded(
                child: Text(
                  isEn
                      ? 'Last seen summary (not this article)'
                      : '上次看到的总结（不是当前文章摘要）',
                  style: TextStyle(fontSize: 11 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w700),
                ),
              ),
              // 7/2 展开/折叠
              GestureDetector(
                onTap: () => setState(() => _tlDrExpanded = !_tlDrExpanded),
                child: Icon(
                  _tlDrExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16 * _scale, color: AppTheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 4 * _scale),
          // 7/2 默认 1 行 (fold 状态), 点展开看 3 行
          Text(
            _tlDrText,
            maxLines: _tlDrExpanded ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12 * _scale, color: AppTheme.primary.withValues(alpha: 0.85), height: 1.4),
          ),
        ],
      ),
    );
  }

  // 6/9 续读小卡 (3 条 progress 0-100)
  Widget _buildContinueReadingCard() {
    // 7/2 默认只看 1 条 (_continueExpanded=false), 点展开看 3 条
    final showItems = _continueExpanded
        ? _inProgressItems
        : (_inProgressItems.length > 1 ? _inProgressItems.take(1).toList() : _inProgressItems);
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.all(12 * _scale),
      decoration: GlassStyle.glassCardOnLight(opacity: 0.6, radius: 16, dark: Theme.of(context).brightness == Brightness.dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 14 * _scale, color: AppTheme.primary),
              SizedBox(width: 4 * _scale),
              Expanded(
                child: Text(
                  isEn ? 'Continue reading' : '续读',
                  style: TextStyle(fontSize: 11 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w700),
                ),
              ),
              // 7/2 展开/折叠 (仅在 2+ 条时显示)
              if (_inProgressItems.length > 1)
                GestureDetector(
                  onTap: () => setState(() => _continueExpanded = !_continueExpanded),
                  child: Icon(
                    _continueExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16 * _scale, color: AppTheme.primary,
                  ),
                ),
            ],
          ),
          SizedBox(height: 8 * _scale),
          for (final item in showItems)
            InkWell(
              onTap: () => _pushToReader(item),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4 * _scale),
                child: Row(
                  children: [
                    // 进度环
                    SizedBox(
                      width: 28 * _scale,
                      height: 28 * _scale,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: item.progress / 100,
                            strokeWidth: 2.5 * _scale,
                            backgroundColor: Colors.black.withValues(alpha: 0.06),
                            valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                          ),
                          Text('${item.progress}', style: TextStyle(fontSize: 9 * _scale, color: AppTheme.primary)),
                        ],
                      ),
                    ),
                    SizedBox(width: 10 * _scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13 * _scale, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            item.source,
                            style: TextStyle(fontSize: 10 * _scale, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16 * _scale, color: AppTheme.textLight),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoIfNeeded(ContentItem item) {
    // 7/2 v3: 紧凑视频卡 — 缩略 3:2 (不到 16:9 高) + 紧凑文字行
    // 7/2 10:56 Brien 反馈: 16:9 + 文字还是太大 (16%+ 屏幕), v3 再压
    // 后面: B 站视频直链可考虑, 但 v3 先验证“卡小”够不够
    final bili = _biliCache[item.id];
    final coverUrl = bili?.cover ?? '';
    final extUrl = item.externalUrl;

    return InkWell(
      onTap: () async {
        final target = bili != null
            ? Uri.parse('https://www.bilibili.com/video/${bili.bvid}')
            : (extUrl != null && extUrl.isNotEmpty ? Uri.parse(extUrl) : null);
        if (target != null && await canLaunchUrl(target)) {
          await launchUrl(target, mode: LaunchMode.externalApplication);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        // 横向: 缩略 64x64 + 标题 1 行 + 时长 1 行
        // 总高度 ~80px (手机窄屏上 9% 屏幕)
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 小缩略 64x64
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64, height: 64,
                  child: coverUrl.isNotEmpty
                      ? Image.network(coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _videoPlaceholder(item))
                      : _videoPlaceholder(item),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 标题 1 行
                    Text(
                      bili?.title ?? item.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // 副标题 1 行: 时长 · 播放量
                    Text(
                      [
                        if (bili != null && bili.duration.isNotEmpty) bili.duration,
                        if (bili != null) _formatPlayCount(bili.play),
                        if (bili == null && item.duration.isNotEmpty) '时长 ${item.duration}',
                      ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // “去 B 站” 文字按钮
              Text(
                '在 B 站看 →',
                style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoPlaceholder(ContentItem item) {
    return Container(
      color: Colors.black12,
      child: Center(
        child: Icon(Icons.movie, size: 48, color: AppTheme.primary.withValues(alpha: 0.5)),
      ),
    );
  }

  String _formatPlayCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万播放';
    return '$n 播放';
  }

  // 6/22 audio 入口: 推送 ContentReaderScreen 播音频
  // 7/1 优化: 副文案 → "小 O 念你听" (TTS 体,不像假播放按钮), + 原文外部跳转
  // 7/1 bug fix v3: 不用嵌套 InkWell (Flutter web hit-test bug), 改用 Stack + 外层 GestureDetector
  Widget _buildAudioEntry(ContentItem item) {
    final extUrl = item.externalUrl;
    final hasExt = extUrl != null && extUrl.isNotEmpty;
    return Material(
      color: AppTheme.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 整张卡: 点击推详情
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pushToReader(item),
              child: Padding(
                padding: EdgeInsets.all(12 * _scale),
                child: Row(
                  children: [
                    Container(
                      width: 40 * _scale,
                      height: 40 * _scale,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.record_voice_over, color: Colors.white, size: 22 * _scale),
                    ),
                    SizedBox(width: 12 * _scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: TextStyle(fontSize: 14 * _scale, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Row(
                            children: [
                              Text(
                                _t('小 O 念你听', 'Voice by 小 O'),
                                style: TextStyle(fontSize: 11 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w600),
                              ),
                              if (item.duration != null && item.duration!.isNotEmpty) ...[
                                Text(
                                  ' · ${item.duration}',
                                  style: TextStyle(fontSize: 11 * _scale, color: AppTheme.textLight),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // 预留 chip 宽度空间 (避免被 chevron 压)
                    if (hasExt) SizedBox(width: 56 * _scale),
                    Icon(Icons.chevron_right, color: AppTheme.textLight),
                  ],
                ),
              ),
            ),
          ),
          // chip 飘在右上角, 独立 InkWell, 不参与外层 hit-test
          if (hasExt)
            Positioned(
              right: 32 * _scale,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      try {
                        await launchUrl(Uri.parse(extUrl), mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10 * _scale, vertical: 6 * _scale),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 12 * _scale, color: AppTheme.primary),
                          SizedBox(width: 3 * _scale),
                          Text(
                            _t('原站', 'Open'),
                            style: TextStyle(fontSize: 10 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 6/22 quiz 入口: 推送 ContentReaderScreen 显示 quiz panel
  Widget _buildQuizEntry(ContentItem item) {
    return Material(
      color: const Color(0xFF16A34A).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _pushToReader(item),
        child: Padding(
          padding: EdgeInsets.all(12 * _scale),
          child: Row(
            children: [
              Container(
                width: 40 * _scale,
                height: 40 * _scale,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.quiz, color: Colors.white, size: 24 * _scale),
              ),
              SizedBox(width: 12 * _scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: TextStyle(fontSize: 14 * _scale, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(_t('点击开始测验', 'Tap to start quiz'), style: TextStyle(fontSize: 11 * _scale, color: AppTheme.textLight)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textLight),
            ],
          ),
        ),
      ),
    );
  }

  // 6/22 hero push 状态: LLM 还没首 chunk + 没有 prefillItem 时显示完整骨架
  Widget _buildLoadingState() {
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.all(12 * _scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16 * _scale,
            height: 16 * _scale,
            child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppTheme.primary)),
          ),
          SizedBox(width: 8 * _scale),
          Expanded(
            child: Text(
              _t('正在为你生成内容...', 'Generating your content...'),
              style: TextStyle(fontSize: 12 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ============== Hero (AI 内容主体) ==============

  // 7/29 加: 跳原站读全文提示 (沿用宪法 §1.1 不存原片, 明确告知访客如何读全文)
  Widget _buildReadFullHint() {
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.all(10 * _scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.open_in_new, size: 14 * _scale, color: AppTheme.primary),
          SizedBox(width: 6 * _scale),
          Expanded(
            child: Text(
              isEn
                  ? 'Tap Read → "Read full at source" for the complete article'
                  : '点 Read → "在原站读全文" 看完整内容',
              style: TextStyle(fontSize: 11 * _scale, color: AppTheme.hintColor(context)),
            ),
          ),
        ],
      ),
    );
  }

  // 7/29 加: RSS 拉空时空状态. 访客看到"今日暂无新内容" + 下拉重试
  // 8/8 升一阶: 显示 _loadFromBucketErr 调试信息 (沿 SOUL #25 #26 #27 沿 #169 不撒谎)
  Widget _buildEmptyState() {
    final sourceLabel = widget.isInternational ? 'The Verge' : '36氪 / 少数派';
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.all(16 * _scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.refresh_outlined, size: 20 * _scale, color: AppTheme.primary),
          SizedBox(width: 12 * _scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn ? 'No new content today' : '今日暂无新内容',
                  style: TextStyle(fontSize: 14 * _scale, fontWeight: FontWeight.w600, color: AppTheme.primary),
                ),
                SizedBox(height: 4 * _scale),
                Text(
                  isEn
                      ? 'Live from $sourceLabel · pull to refresh'
                      : '正在拉 $sourceLabel 的最新内容 · 下拉刷新',
                  style: TextStyle(fontSize: 12 * _scale, color: AppTheme.hintColor(context)),
                ),
                // 8/8: 显示底层错误 (沿 #117 沿用 alert: 仅在用户报错时显示)
                if (_loadFromBucketErr.isNotEmpty && kDebugMode) ...[
                  SizedBox(height: 4 * _scale),
                  Text(
                    'debug: $_loadFromBucketErr',
                    style: TextStyle(fontSize: 10 * _scale, color: AppTheme.hintColor(context).withValues(alpha: 0.6)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero({required bool isDark, required bool isWarm}) {
    // 7/25 14:05 v10 真凶修: Scene.listen 背景 0xFFF0F9FF (浅蓝) + glassFrosted 0.45 白 = 透明看不上
    // 修法: opacity 提到 0.92 + 文字色强制深色 (防止 onGlassPrimary 在浅背景也是浅)
    return Container(
      margin: EdgeInsets.only(bottom: 12 * _scale),
      decoration: GlassStyle.glassFrosted(opacity: isWarm ? 0.92 : 0.95, radius: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(16 * _scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading && !_llmGotFirstChunk) _buildLoadingSkeleton(isDark: isDark, isWarm: isWarm),
              if (_hasContent)
                Text(
                  _buf,
                  style: TextStyle(
                    fontSize: 15 * _scale,
                    height: 1.55,
                    fontFamily: 'Roboto',
                    fontFamilyFallback: const [
                      'PingFang SC', 'Microsoft YaHei', 'Hiragino Sans GB',
                      'Noto Sans CJK SC', 'Microsoft JhengHei', 'SimSun',
                      '-apple-system', 'BlinkMacSystemFont', 'Helvetica Neue', 'sans-serif',
                    ],
                    // 7/25 14:05 强制深色 (listen scene 背景浅, onGlassPrimary 也是浅)
                    color: isWarm
                        ? const Color(0xFF3D2A14)  // 深棕 (warm 背景)
                        : const Color(0xFF1A1A2E),  // 深蓝黑 (其他背景)
                  ),
                ),
              if (_showCompletionBanner && _progress >= 100) ...[
                const SizedBox(height: 16),
                _buildCompletionBanner(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton({required bool isDark, required bool isWarm}) {
    final color = (isWarm
            ? GlassStyle.onGlassPrimaryWarm
            : isDark
                ? GlassStyle.onGlassPrimaryDark
                : GlassStyle.onGlassPrimary)
        .withValues(alpha: 0.15);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        5,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: 10 * _scale),
          child: Container(
            height: 12 * _scale,
            width: i == 4 ? 120 * _scale : double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * _scale, vertical: 8 * _scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppTheme.primary, size: 18 * _scale),
          SizedBox(width: 8 * _scale),
          Expanded(
            child: Text(
              isEn ? '✓ Read complete' : '✓ 已读完',
              style: TextStyle(
                fontSize: 13 * _scale,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryRow() {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * _scale),
      child: Row(
        children: [
          Expanded(child: _entryButton(Icons.group_outlined, isEn ? 'Study group' : '学习小组', _showStudyGroups)),
          SizedBox(width: 6 * _scale),
          Expanded(child: _entryButton(Icons.calendar_today_outlined, isEn ? 'Weekly recap' : '本周回顾', _showWeeklyRecap)),
          SizedBox(width: 6 * _scale),
          Expanded(child: _entryButton(Icons.privacy_tip_outlined, isEn ? 'Privacy' : '隐私', _showPrivacy)),
        ],
      ),
    );
  }

  Widget _entryButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8 * _scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18 * _scale, color: AppTheme.primary),
              SizedBox(height: 2 * _scale),
              Text(label, style: TextStyle(fontSize: 11 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStudyGroups() async {
    try {
      final groups = await StudyGroupService.instance.getForRole(widget.userType);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.all(16 * _scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isEn ? 'Study groups' : '学习小组', style: TextStyle(fontSize: 18 * _scale, fontWeight: FontWeight.w700)),
              SizedBox(height: 12 * _scale),
              if (groups.isEmpty)
                Text(isEn ? 'No groups yet · create one' : '还没有小组 · 建一个',
                    style: TextStyle(fontSize: 13 * _scale, color: AppTheme.textLight))
              else
                for (final g in groups.take(5))
                  ListTile(
                    leading: Icon(Icons.group, color: AppTheme.primary),
                    title: Text(g.name),
                    subtitle: Text('${g.memberIds.length} 成员 · ${g.topic}'),
                    onTap: () => Navigator.pop(ctx),
                  ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        _showFloatingSnack(context, isEn ? 'Failed to load groups' : '加载小组失败');
      }
    }
  }

  Future<void> _showWeeklyRecap() async {
    try {
      final recap = await WeeklyRecapService.instance.generate(useLLM: false);
      final summary = recap.summary;
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isEn ? '📊 Weekly recap' : '📊 本周回顾'),
          content: SingleChildScrollView(
            child: Text(summary ?? (isEn ? 'No data this week' : '本周无数据'),
                style: const TextStyle(fontSize: 14, height: 1.5)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isEn ? 'Close' : '关闭'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        _showFloatingSnack(context, isEn ? 'Failed to load recap' : '加载周报失败');
      }
    }
  }

  Future<void> _showPrivacy() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isEn ? '🔒 Privacy' : '🔒 隐私政策'),
        content: SingleChildScrollView(
          child: Text(
            isEn
                ? '1. All data is stored on your device.\n'
                    '2. We do not collect personal info.\n'
                    '3. LLM requests go to your local Ollama.\n'
                    '4. TTS uses browser/mobile built-in.\n'
                    '5. You can clear data anytime in Settings.'
                : '1. 所有数据存本机。\n'
                    '2. 不收集个人信息。\n'
                    '3. LLM 请求走本地 Ollama。\n'
                    '4. TTS 用浏览器/手机自带。\n'
                    '5. 可随时在设置里清数据。',
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'OK' : '好'),
          ),
        ],
      ),
    );
  }

  // 8/14 加 (沿 SOUL #169 不撒谎): 统计 _recItems 最频繁 source 标签, 真实显示
  //   真凶: 之前 _buildRecommendationHeader 写死 'Live from 36氪' / 'The Verge'
  //     → 实际可能是 TechCrunch/IT之家/Solidot/豆瓣 等 → 用户看到误导
  //   修: 统计 _recItems 里出现最多的 source (rss_ prefix 的 item) → 显示真实来源
  String? _getRealSourceLabel() {
    final sourceCounts = <String, int>{};
    for (final r in _recItems) {
      if (!r.id.startsWith('rss_')) continue; // 只统计真 RSS, 不算精选兑底
      // source 已带前缀 (如 'TechCrunch', 'IT之家', '豆瓣音乐' 等, 8/14 三次治本 fix)
      final s = r.source;
      if (s.isNotEmpty) sourceCounts[s] = (sourceCounts[s] ?? 0) + 1;
    }
    if (sourceCounts.isEmpty) return null; // 全是精选兑底, 不显示 Live 标签
    // 找最频繁
    final sorted = sourceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSource = sorted.first.key;
    return isEn ? 'Live from $topSource' : '$topSource 实时';
  }

  Widget _buildRecommendationHeader() {
    // 7/14 加: 显示 RSS 真数据来源 (国内 36 氪 / 国际 The Verge)
    // 8/14 治本 (沿 SOUL #169 不撒谎): 写死 '36氪' 是错的
    //   真凶: 之前写死 sourceLabel='Live from 36氪' / 'Live from The Verge'
    //     → 实际可能 TechCrunch/IT之家/Solidot/豆瓣 等 → 用户看到误导
    //   修: 统计 _recItems 最频繁的 source 标签, 真实显示
    final sourceLabel = _getRealSourceLabel();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.favorite_outline, size: 14 * _scale, color: AppTheme.textLight),
            SizedBox(width: 4 * _scale),
            Text(
              isEn ? 'You may also like' : '你可能还喜欢',
              style: TextStyle(
                fontSize: 12 * _scale,
                color: AppTheme.textLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (sourceLabel != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFD32F2F),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 4 * _scale),
              Text(
                sourceLabel,
                style: TextStyle(
                  fontSize: 11 * _scale,
                  color: const Color(0xFFD32F2F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ============== FAB 读完啦 ==============

  Widget _buildCompleteFab(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 16, bottom: 16 * _scale),
        child: FloatingActionButton.extended(
          heroTag: 'complete-fab',
          onPressed: _markComplete,
          backgroundColor: AppTheme.primary,
          icon: Icon(Icons.celebration, color: Colors.white, size: 22 * _scale),
          label: Text(
            isEn ? 'I read it' : '读完啦',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14 * _scale,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markComplete() async {
    await _writeProgress(100);
    if (_aiContentItem != null) {
      try {
        await UserPreferenceService.instance.record(
          action: PrefAction.save,
          item: _aiContentItem!,
          userType: widget.userType,
          scene: widget.scene,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _showCompletionBanner = true);
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24 * _scale),
          decoration: BoxDecoration(
            // 7/19 fix v2: 同上, LinearGradient 全量清除
            color: const Color(0xFF7C5CFC),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 56)),
              SizedBox(height: 8 * _scale),
              Text(
                isEn ? 'Well done!' : '读完啦！',
                style: TextStyle(
                  fontSize: 22 * _scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 6 * _scale),
              Text(
                isEn ? '+5 XP · keep the streak going' : '+5 经验 · 继续坚持',
                style: TextStyle(
                  fontSize: 13 * _scale,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              SizedBox(height: 16 * _scale),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  isEn ? 'OK' : '好',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============== TTS ==============

  Future<void> _toggleTts() async {
    if (_ttsPlaying) {
      try {
        await TtsService.instance.stop();
      } catch (_) {}
      setState(() => _ttsPlaying = false);
    } else {
      setState(() => _ttsPlaying = true);
      try {
        await TtsService.instance.speak(_buf);
      } catch (_) {}
      if (mounted) setState(() => _ttsPlaying = false);
    }
  }

  // ============== Scene 背景 ==============

  String _sceneName() {
    if (isEn) {
      switch (widget.scene) {
        case Scene.learn: return 'Learn';
        case Scene.listen: return 'Listen';
        case Scene.relax: return 'Relax';
        case Scene.workout: return 'Workout';
      }
    }
    switch (widget.scene) {
      case Scene.learn: return '学';
      case Scene.listen: return '听';
      case Scene.relax: return '放松';
      case Scene.workout: return '动一动';
    }
  }

  Color? _sceneBgColor() {
    if (widget.isElderlyMode) return const Color(0xFFFFF8E7);
    return null;
  }

  // 7/19 fix v2: LinearGradient 全量清除, 返回兑底单色
  Color _sceneFallbackColor() {
    final isWarm = EyeProtectionScope.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isWarm) return const Color(0xFFFFE8C8);
    if (isDark) return const Color(0xFF1A1A2E);
    switch (widget.scene) {
      case Scene.learn:   return const Color(0xFFEEF2FF);
      case Scene.listen:  return const Color(0xFFF0F9FF);
      case Scene.relax:   return const Color(0xFFFDF2F8);
      case Scene.workout: return const Color(0xFFECFDF5);
    }
  }
}

// 6/30 11:43 SOUL #32: 浮起 SnackBar, 不挡底部 nav
void _showFloatingSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      duration: const Duration(seconds: 2),
    ),
  );
}
