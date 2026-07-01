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
// 5 个核心状态: _buf (流式 buffer), _llmGotFirstChunk (是否收到首 chunk), _llmFallbackTimer (30s 兑底),
// _summary (TL;DR 精要), _recItems (推荐 6 条, 来自 ContentAggregator)

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
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
import '../widgets/tinder_recommendation_stack.dart';
import '../widgets/iframe_video_view.dart';
import '../widgets/quiz_panel.dart';
import 'content_reader_screen.dart';
import '../services/study_group_service.dart';
import '../services/weekly_recap_service.dart';
import '../services/analytics_service.dart';
import '../services/handle_service.dart';

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
  bool _recLoading = false;
  bool _showCompletionBanner = false;
  bool _aiOfferShown = false; // 6/30 12:23: 读完弹 AI sheet 防重复
  bool _hasScrolled = false; // 6/26: 滚到过文章中部才显"读完啦"按钮
  bool _ttsPlaying = false;
  bool _showAllDoneDialog = false; // 6 张全看完弹 dialog
  List<ContentItem> _inProgressItems = []; // 续读
  int _todayCompleteCount = 0; // 今日完成计数
  bool _showTlDrBanner = false; // TL;DR 精要 banner
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
  }

  @override
  void dispose() {
    _llmFallbackTimer?.cancel();
    _sub?.cancel();
    _progressTimer?.cancel();
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    TtsService.instance.stop();
    super.dispose();
  }

  // 启动 LLM 流式
  Future<void> _startLlm() async {
    // 6/14 v3: 30s 兑底 timer (首 chunk 到达关 / onError onDone 关 / dispose 关)
    _llmFallbackTimer = Timer(const Duration(seconds: 30), () {
      if (!_llmGotFirstChunk && mounted) {
        _showStub(reason: 'timeout_30s');
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
            _loadFakeContent();
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
  Future<void> _loadFromBucket() async {
    try {
      final items = await NewsService().getRecommendations(widget.userType, widget.scene);
      if (!mounted || items.isEmpty) return;
      final first = items.first;
      setState(() {
        _aiContentItem = first;
        _buf = '${first.title}\n\n${first.description ?? "".trim()}';
        _llmGotFirstChunk = true;
        _loading = false;
      });
    } catch (e) {
      debugPrint('_loadFromBucket error: $e');
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

  // 6/25 fallback: LLM 内容错位 → 调 NewsService 假数据桶
  Future<void> _loadFakeContent() async {
    try {
      final results = await NewsService().getRecommendations(widget.userType, widget.scene);
      if (!mounted || results.isEmpty) return;
      final item = results.first;
      setState(() {
        _buf = '${item.title}\n\n${item.description ?? ''}';
        _aiContentItem = item;
      });
    } catch (e) {
      debugPrint('[LLM] _loadFakeContent error: $e');
    }
  }

  // 加载推荐 6 条 (用 ContentAggregator 6 张看完换 6 张)
  Future<void> _loadRecommendations() async {
    if (_recLoading) return;
    setState(() => _recLoading = true);
    try {
      final rec = await ContentAggregator().fetchRecommendContent(
        userType: widget.userType,
        scene: widget.scene,
        isInternational: widget.isInternational,
      );
      if (!mounted) return;
      setState(() {
        _recItems = rec;
        _recLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _recLoading = false);
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
    });
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24 * _scale),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
                style: TextStyle(fontSize: 13 * _scale, color: Colors.white.withOpacity(0.9)),
              ),
              SizedBox(height: 16 * _scale),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _loadRecommendations();
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
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16 * _scale,
            fontWeight: FontWeight.w600,
            color: AppTheme.primary,
          ),
        ),
        leading: Material(
          color: Colors.white.withOpacity(0.6),
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
              color: Colors.white.withOpacity(0.6),
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
          gradient: _sceneBgColor() == null ? _sceneBgGradient : null,
          color: _sceneBgColor(),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 * _scale, 8 * _scale, 16 * _scale, 8 * _scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 6/7 儿童安全: child userType 顶部绿色盾牌
                if (widget.userType == UserType.child) _buildChildShield(),
                // 6/9 TL;DR 精要 banner (拿上次同 userType+scene 总结)
                if (_showTlDrBanner && _tlDrText.isNotEmpty) _buildTlDrBanner(),
                // 6/9 续读小卡 (3 条 progress 0-100)
                if (_inProgressItems.isNotEmpty) _buildContinueReadingCard(),
                if (_aiContentItem != null && _aiContentItem!.contentType == ContentType.video) ...[
                  _buildVideoIfNeeded(_aiContentItem!),
                  SizedBox(height: 8 * _scale),
                ],
                if (_aiContentItem != null && _aiContentItem!.contentType == ContentType.audio) ...[
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
                SizedBox(height: 8 * _scale),
                if (_recItems.isNotEmpty) ...[
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
                  ),
                ],
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
      color: Colors.white.withOpacity(0.6),
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
                color: Colors.black.withOpacity(0.2),
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
        color: const Color(0xFF16A34A).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.4), width: 1),
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

  // 6/9 TL;DR 精要 banner
  Widget _buildTlDrBanner() {
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.all(12 * _scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 14 * _scale, color: AppTheme.primary),
              SizedBox(width: 4 * _scale),
              Text(
                isEn ? 'TL;DR · from last time' : 'TL;DR · 上次总结',
                style: TextStyle(fontSize: 11 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          SizedBox(height: 4 * _scale),
          Text(
            _tlDrText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13 * _scale, color: AppTheme.primary.withOpacity(0.85), height: 1.4),
          ),
        ],
      ),
    );
  }

  // 6/9 续读小卡 (3 条 progress 0-100)
  Widget _buildContinueReadingCard() {
    return Container(
      margin: EdgeInsets.only(bottom: 8 * _scale),
      padding: EdgeInsets.all(12 * _scale),
      decoration: GlassStyle.glassCardOnLight(opacity: 0.6, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 14 * _scale, color: AppTheme.primary),
              SizedBox(width: 4 * _scale),
              Text(
                isEn ? 'Continue reading' : '续读',
                style: TextStyle(fontSize: 11 * _scale, color: AppTheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          SizedBox(height: 8 * _scale),
          for (final item in _inProgressItems)
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
                            backgroundColor: Colors.black.withOpacity(0.06),
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
    final embedUrl = buildVideoEmbedUrl(item);
    if (embedUrl == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: IframeVideoView(
        embedUrl: embedUrl,
        externalUrl: item.externalUrl,
        aspectRatio: 16 / 9,
      ),
    );
  }

  // 6/22 audio 入口: 推送 ContentReaderScreen 播音频
  // 7/1 优化: 副文案 → "小 O 念你听" (TTS 体,不像假播放按钮), + 原文外部跳转
  Widget _buildAudioEntry(ContentItem item) {
    final extUrl = item.externalUrl;
    final hasExt = extUrl != null && extUrl.isNotEmpty;
    return Material(
      color: AppTheme.primary.withOpacity(0.1),
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
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                // 7/1: 从 play_arrow 改为 record_voice_over (TTS 提示)
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
              // 7/1: 加外部链接 chip (有源 URL 时) — 一键开原站
              if (hasExt)
                GestureDetector(
                  onTap: () async {
                    try {
                      await launchUrl(Uri.parse(extUrl), mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                  child: Container(
                    margin: EdgeInsets.only(right: 4 * _scale),
                    padding: EdgeInsets.symmetric(horizontal: 8 * _scale, vertical: 4 * _scale),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
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
              Icon(Icons.chevron_right, color: AppTheme.textLight),
            ],
          ),
        ),
      ),
    );
  }

  // 6/22 quiz 入口: 推送 ContentReaderScreen 显示 quiz panel
  Widget _buildQuizEntry(ContentItem item) {
    return Material(
      color: const Color(0xFF16A34A).withOpacity(0.1),
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
        color: AppTheme.primary.withOpacity(0.05),
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

  Widget _buildHero({required bool isDark, required bool isWarm}) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(bottom: 12 * _scale),
        decoration: GlassStyle.glassFrosted(opacity: isWarm ? 0.4 : 0.55, radius: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SingleChildScrollView(
            controller: _bodyScroll,
            padding: EdgeInsets.all(16 * _scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loading && !_llmGotFirstChunk) _buildLoadingSkeleton(isDark: isDark, isWarm: isWarm),
                if (_hasContent)
                  Text(
                    _buf,
                    style: TextStyle(
                      fontSize: 15 * _scale,
                      height: 1.55,
                      color: isWarm
                          ? GlassStyle.onGlassPrimaryWarm
                          : isDark
                              ? GlassStyle.onGlassPrimaryDark
                              : GlassStyle.onGlassPrimary,
                    ),
                  ),
                if (_showCompletionBanner && _progress >= 100) ...[
                  SizedBox(height: 16 * _scale),
                  _buildCompletionBanner(),
                ],
              ],
            ),
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
        .withOpacity(0.15);
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
        color: AppTheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1),
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
      color: Colors.white.withOpacity(0.6),
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

  Widget _buildRecommendationHeader() {
    return Row(
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
            gradient: const LinearGradient(
              colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
                  color: Colors.white.withOpacity(0.9),
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

  LinearGradient get _sceneBgGradient {
    final isWarm = EyeProtectionScope.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isWarm) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE8C8), Color(0xFFFFD9A0)],
      );
    }
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
      );
    }
    switch (widget.scene) {
      case Scene.learn:
        return const LinearGradient(
          colors: [Color(0xFFE0E7FF), Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case Scene.listen:
        return const LinearGradient(
          colors: [Color(0xFFE0F2FE), Color(0xFFF0F9FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case Scene.relax:
        return const LinearGradient(
          colors: [Color(0xFFFCE7F3), Color(0xFFFDF2F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case Scene.workout:
        return const LinearGradient(
          colors: [Color(0xFFD1FAE5), Color(0xFFECFDF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
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
