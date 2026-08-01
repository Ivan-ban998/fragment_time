import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:ui';
import '../models/models.dart';
import '../models/quote.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/tts_service.dart';
import '../services/local_subscription_service.dart';
import '../services/history_service.dart';
import '../widgets/iframe_video_view.dart';
import '../widgets/quiz_panel.dart';
import '../services/share_service.dart';
import '../services/study_group_service.dart';
import '../services/handle_service.dart';
import '../services/llm_service.dart';
import '../services/news_service.dart';
import '../widgets/inline_read_view.dart';
import 'ai_assistant_screen.dart';
import '../services/quote_related_engine.dart';
import 'in_app_webview_screen.dart';

class ContentReaderScreen extends StatefulWidget {
  final ContentItem item;
  final bool isElderlyMode;
  final bool isEn;
  // 7/15 17:19 Q2 修: userType/scene 可选传入 (兑底 officeWorker/learn)
  // 用法: ContentReaderScreen(item: it, userType: ut, scene: Scene.learn)
  // Hero 卡/quote 详情 不传时 关联算法兑底 (没原本 userType 信息)
  final UserType? userType;
  final Scene? scene;

  const ContentReaderScreen({
    super.key,
    required this.item,
    this.isElderlyMode = false,
    this.isEn = false,
    this.userType,
    this.scene,
  });

  @override
  State<ContentReaderScreen> createState() => _ContentReaderScreenState();
}

class _ContentReaderScreenState extends State<ContentReaderScreen> {
  final TtsService _tts = TtsService.instance;
  final LocalSubscriptionService _subService = LocalSubscriptionService.instance;
  bool _ttsAvailable = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  bool _isSubscribed = false;

  // 6/14 详情页完成:scroll 到底自动标记 + 轻成就 banner
  final ScrollController _scrollCtrl = ScrollController();
  bool _markCompleteDone = false;
  bool _showAchievementBanner = false;
  bool _isCompleted = false; // 进页面时已有 progress=100

  // 6/24 v7: HUD 计时 — 顶角显示阅读时长
  late DateTime _openTime;
  Timer? _hudTimer;
  String _hudText = '0:00';

  // 6/25 C: AI 摘要折叠区（手动按钮调 Ollama, 30s 兌底）
  String? _aiSummary;
  bool _aiSummaryLoading = false;
  bool _aiSummaryFailed = false;

  // 6/25 A: 站内直接读全文 (展开状态 + 兑底 iframe 加载状态)
  bool _showInlineRead = false;
  bool _inlineReadTimeout = false;

  @override
  void initState() {
    super.initState();
    _openTime = DateTime.now();
    _initTts();
    _checkSubscribed();
    _recordHistory();
    _scrollCtrl.addListener(_onScroll);
    // 6/14 进页时若已 100 -> 显示"已读完"banner
    _isCompleted = widget.item.progress >= 100;
    // 6/24 v7: HUD 计时 — 每秒更新
    _hudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final elapsed = DateTime.now().difference(_openTime);
        _hudText = _formatDuration(elapsed);
      });
    });
    // 6/24 修: post-frame 查短文章 (maxScrollExtent=0), 进页面立即 mark
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkShortArticle();
    });
    // 6/25: AI 摘要自动生成 (取代手动点击按钮)
    // 6/26 Brien 00:44: 1.5b 仍输出'5 个教育误解' 等学生内容
    // → 改成从 NewsService 24 桶加载 (不调 LLM, 角色匹配)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSummaryFromBucket();
    });
  }

  // 6/24 v7: 格式化时长 (mm:ss 或 hh:mm:ss)
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:$m:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // 6/24 修: 短文章检 (不用 scroll, 文章本身就能全显)
  void _checkShortArticle() {
    if (!mounted || _markCompleteDone) return;
    if (!_scrollCtrl.hasClients) return;
    try {
      final pos = _scrollCtrl.position;
      if (pos.maxScrollExtent <= 0) {
        _markCompleteDone = true;
        _markComplete();
      }
    } catch (_) {
      // 动画中 / dispose 后, 静默
    }
  }

  Future<void> _recordHistory() async {
    // 6/7 步骤 2：记录阅读历史（只本地）
    if (widget.item.id.isEmpty) return;
    await HistoryService.instance.add(widget.item);
  }

  @override
  void dispose() {
    _tts.stop();
    _markCompleteTimer?.cancel();
    _hudTimer?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  // 6/25 C: AI 摘要 (Ollama, 30s 兌底, 失败可重试)
  // 6/25 注: child HARD RULE 由 LlmService.generateRaw 后续接入 (现为 stub, 留 TODO)
  Future<void> _generateAiSummary() async {
    if (_aiSummaryLoading) return;
    setState(() {
      _aiSummaryLoading = true;
      _aiSummaryFailed = false;
    });
    final langHint = widget.isEn ? 'Respond in English.' : '中文回答.';
    final prompt = '请为以下文章生成 3-5 句中文摘要, 不超过 150 字, 不要重复标题.\n'
        '$langHint\n'
        '标题: ${widget.item.title}\n'
        '描述: ${widget.item.description}\n'
        '延伸: ${_getExtendedContent()}\n\n'
        '摘要:';
    try {
      final result = await LlmService.generateRaw(prompt, isEn: widget.isEn)
                    .timeout(const Duration(seconds: 120));
      if (!mounted) return;
      setState(() {
        _aiSummary = result.trim();
        _aiSummaryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiSummaryLoading = false;
        _aiSummaryFailed = true;
      });
    }
  }

  // 6/26 Brien 00:44 修: 1.5b 仍输出学生内容 — 摘要从 NewsService 24 桶加载 (不调 LLM)
  // 注: ContentReaderScreen 只接 item, 不知道 userType/scene
  // → 用 item 标题前缀 'student_learn_1' 等解析出 userType + scene
  Future<void> _loadSummaryFromBucket() async {
    try {
      // 简单实现: 24 桶全部加载, 排除当前 article
      // TODO: 优化 — ContentScreen 跳转时传 userType+scene 进 widget
      final allBuckets = <String>[];
      for (final ut in UserType.values) {
        for (final s in Scene.values) {
          allBuckets.add('${ut.bucketKey}_${s.bucketKey}');
        }
      }
      List<ContentItem> candidates = [];
      for (final key in allBuckets) {
        // 直接调 NewsService 内部 _allContent, 但没暴露 — 改用 6x4 = 24 次
        final results = await NewsService().getRecommendations(_inferType(), _inferScene());
        candidates.addAll(
            results.where((it) => it.id != widget.item.id).toList());
        if (candidates.isNotEmpty) break; // 拿到 1 桶就够
      }
      if (!mounted || candidates.isEmpty) return;
      final next = candidates.first;
      final summary = '${next.title}\n\n${next.description ?? "".trim()}';
      if (!mounted) return;
      setState(() {
        _aiSummary = summary;
        _aiSummaryLoading = false;
        _aiSummaryFailed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiSummaryLoading = false;
        _aiSummaryFailed = true;
      });
    }
  }

  // 6/26: 简单推 userType (item.id 前缀或 sourceType)
  UserType _inferType() {
    // id 格式: 'student_learn_1' / 'officeWorker_relax_2' / 'encourage_2024-01-01'
    final id = widget.item.id;
    if (id.startsWith('student')) return UserType.student;
    if (id.startsWith('officeWorker')) return UserType.officeWorker;
    if (id.startsWith('entrepreneur')) return UserType.entrepreneur;
    if (id.startsWith('parent')) return UserType.parent;
    if (id.startsWith('senior')) return UserType.senior;
    if (id.startsWith('child')) return UserType.child;
    return UserType.student; // fallback
  }

  Scene _inferScene() {
    final id = widget.item.id;
    if (id.contains('_learn')) return Scene.learn;
    if (id.contains('_listen')) return Scene.listen;
    if (id.contains('_relax')) return Scene.relax;
    if (id.contains('_workout')) return Scene.workout;
    return Scene.learn;
  }

  // 6/14 scroll 到底 -> 写 progress=100 + 弹成就 banner 3s
  // 6/24 修: try-catch + Timer 防卡死
  void _onScroll() {
    if (_markCompleteDone) return;
    if (!_scrollCtrl.hasClients) return;
    try {
      final pos = _scrollCtrl.position;
      // 距离底 <= 80px 算"到底"（避免 1px 抖动）
      if (pos.pixels >= pos.maxScrollExtent - 80) {
        _markCompleteDone = true;
        _markComplete();
      }
    } catch (_) {
      // position 出错, 静默
    }
  }

  Timer? _markCompleteTimer;
  Future<void> _markComplete() async {
    try {
      await LocalSubscriptionService.instance.updateProgress(widget.item, 100);
      if (!mounted) return;
      setState(() => _showAchievementBanner = true);
      // 6/25 v17: 不 3s 淺出, 常驻底部, 用户手动 X 关
      _markCompleteTimer?.cancel();
    } catch (e) {
    }
  }

  Future<void> _initTts() async {
    final ok = await _tts.isAvailable();
    if (mounted) setState(() => _ttsAvailable = ok);
  }

  Future<void> _checkSubscribed() async {
    // 6/11 修复：读 service 的 isSubscribed (用 title+source 判定)
    // 旧实现用 id 判定，但 service 之前没存 id (_itemToJson 缺 id)
    // 造成 "收藏后退出重进 → 不显示实心"
    final isSub = await _subService.isSubscribed(item);
    if (!mounted) return;
    setState(() {
      _isSubscribed = isSub;
    });
  }

  bool _isDemo(ContentItem it) {
    if (it.id.startsWith('ai_')) return false;
    if (it.id.startsWith('fallback_') || it.id.startsWith('intl_fallback_')) return true;
    final url = it.externalUrl;
    if (url == null || url.isEmpty) return false;
    return url.contains('zhihu.com/search') ||
        url.contains('36kr.com/search') ||
        url.contains('ximalaya.com/search') ||
        url.contains('spotify.com/search') ||
        url.contains('podcasts.apple.com');
  }

  bool _needsVpn(ContentItem it) {
    final url = it.externalUrl ?? '';
    if (url.contains('podcasts.apple.com')) return false;
    return url.contains('youtube.com') ||
        url.contains('youtu.be') ||
        url.contains('spotify.com') ||
        url.contains('netflix.com') ||
        url.contains('hulu.com');
  }

  Future<void> _toggleSubscribe() async {
    if (_isSubscribed) {
      await _subService.unsubscribe(item);
      if (mounted) {
        setState(() => _isSubscribed = false);
        _showFloatingSnack(
          context,
          isEn ? 'Removed from Saved' : '已移除收藏',
        );
      }
    } else {
      await _subService.subscribe(item);
      if (mounted) {
        setState(() => _isSubscribed = true);
        _showFloatingSnack(
          context,
          isEn ? 'Added to Saved' : '已收藏',
        );
      }
    }
  }

  double get scale => widget.isElderlyMode ? 1.3 : 1.0;
  bool get isEn => widget.isEn;
  ContentItem get item => widget.item;

  String get _fullText {
    return '${item.title}。${item.description ?? ''} ${_getExtendedContent()}';
  }

  Future<void> _togglePlay() async {
    if (_isSpeaking && !_isPaused) {
      await _tts.pause();
      setState(() {
        _isPaused = true;
      });
    } else if (_isPaused) {
      await _tts.resume();
      setState(() {
        _isPaused = false;
      });
    } else {
      await _tts.speak(_fullText);
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    }
  }

  Future<void> _stop() async {
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _isPaused = false;
    });
  }

  // 6/10 加: 加入到学习小组的弹框
  Future<void> _showAddToGroupDialog(BuildContext context) async {
    // 需动态 import 避免 build-time cycle (这里在同文件直接引用)
    final groups = await StudyGroupService.instance.getAll();
    // 只显示当前内容 category 相关的 (简化为显示所有)
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isEn ? 'Add to which group?' : '加入哪个小组？'),
        children: [
          ...groups.map((g) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, g.id),
                child: Row(
                  children: [
                    const Icon(Icons.groups, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(g.name, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              )),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(isEn ? 'No groups. Create one first.' : '没小组。先去建一个。'),
            ),
          // 6/12 加: 在弹窗内直接创建小组（不再跳转）
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '__create__'),
            child: Row(
              children: [
                const Icon(Icons.add_circle_outline, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(isEn ? 'Create new group' : '创建新小组',
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    // 6/12 弹窗内创建小组
    String? targetGroupId = selected;
    if (selected == '__create__') {
      final newId = await _showQuickCreateGroupDialog(context);
      if (newId == null || !mounted) return;
      targetGroupId = newId;
    }
    await StudyGroupService.instance.addContent(targetGroupId, item.id);
    final allGroups = await StudyGroupService.instance.getAll();
    final g = allGroups.firstWhere((x) => x.id == targetGroupId,
        orElse: () => allGroups.first);
    if (!mounted) return;
    _showFloatingSnack(context, isEn ? 'Added to ${g.name}' : '已加入 ${g.name}');
  }

  // 6/12 加: 快速创建小组弹窗（不要求选角色 / handle）
  Future<String?> _showQuickCreateGroupDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final topicCtrl = TextEditingController();
    final isEn = widget.isEn;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'New Study Group' : '创建学习小组'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: isEn ? 'Name' : '小组名',
                  hintText: isEn ? 'e.g. OKR Weekly' : '如：OKR 周复盘',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: topicCtrl,
                decoration: InputDecoration(
                  labelText: isEn ? 'Topic (optional)' : '主题（可选）',
                  hintText: isEn ? 'what you read together' : '一起读什么',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(isEn ? 'Cancel' : '取消')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) {
                _showFloatingSnack(ctx, isEn ? 'Name required' : '要填小组名');
                return;
              }
              final myHandle = await HandleService().get();
              final g = await StudyGroupService.instance.create(
                name: nameCtrl.text.trim(),
                topic: topicCtrl.text.trim(),
                allowedRoles: UserType.values.toSet(), // 默认全角色
                myHandle: myHandle,
              );
              if (ctx.mounted) Navigator.pop(ctx, g.id);
            },
            child: Text(isEn ? 'Create' : '创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 6/19 修: AppBar 玻璃背景 + 0.8 elevation, 返 回头箭头能看清
        backgroundColor: Colors.white.withOpacity(0.85),
        foregroundColor: AppTheme.primary,
        elevation: 0.5,
        // 6/19 修: leading 返 回头加圆形背景 + 深色, 杏橘背景下能看见
        leading: Material(
          color: Colors.white.withOpacity(0.6),
          shape: const CircleBorder(),
          child: IconButton(
            icon: Icon(Icons.arrow_back, size: 24 * scale, color: AppTheme.primary),
            // 6/14 v4 老人模式: 按钮点击区 48→64
            padding: EdgeInsets.all(12 * scale),
            constraints: BoxConstraints.tightFor(width: 48 * scale, height: 48 * scale),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconForSource(item.source), size: 18 * scale, color: AppTheme.primary),
            SizedBox(width: 8 * scale),
            Text(item.source, style: TextStyle(fontSize: 14 * scale, color: AppTheme.textLight)),
          ],
        ),
        actions: [
          // 6/25 v17: HUD 计时 移到右下角浮窗 (避免 AppBar 重叠), AppBar 只保留其他 action
          // 6/8 加：分享按钮
          IconButton(
            icon: Icon(Icons.share, size: 24 * scale),
            padding: EdgeInsets.all(12 * scale),
            constraints: BoxConstraints.tightFor(width: 48 * scale, height: 48 * scale),
            tooltip: isEn ? 'Share as card' : '生成卡片分享',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await ShareService.instance.shareContent(item, isEn: isEn);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? (isEn ? 'Card saved' : '已生成卡片')
                        : (isEn ? 'Copied to clipboard' : '已复制到剪贴板'),
                  ),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _isSubscribed ? Icons.bookmark : Icons.bookmark_outline,
              size: 24 * scale,
              color: _isSubscribed ? AppTheme.primary : null,
            ),
            padding: EdgeInsets.all(12 * scale),
            constraints: BoxConstraints.tightFor(width: 48 * scale, height: 48 * scale),
            tooltip: _isSubscribed
                ? (isEn ? 'Saved' : '已收藏')
                : (isEn ? 'Save' : '收藏'),
            onPressed: _toggleSubscribe,
          ),
          // 6/10 加: 加入我的小组
          IconButton(
            icon: Icon(Icons.group_add, size: 24 * scale),
            padding: EdgeInsets.all(12 * scale),
            constraints: BoxConstraints.tightFor(width: 48 * scale, height: 48 * scale),
            tooltip: isEn ? 'Add to study group' : '加入我的学习小组',
            onPressed: () async {
              await _showAddToGroupDialog(context);
            },
          ),
          if (item.externalUrl != null)
            IconButton(
              icon: Icon(Icons.open_in_browser, size: 24 * scale),
              padding: EdgeInsets.all(12 * scale),
              constraints: BoxConstraints.tightFor(width: 48 * scale, height: 48 * scale),
              tooltip: isEn ? 'Open original' : '打开原文',
              onPressed: () async {
                // 7/29 改: 从 url_launcher 外部浏览器 → in-app webview (沿用宪法 §1.1 不存原片)
                // 留住用户, 不跳出 app. 沿用 #103 #113: webview 失败有 fallback 提示用户
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InAppWebViewScreen(url: item.externalUrl!, title: item.title),
                ));
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // 7/15 Q4: quote 类型走特殊 layout (Hero 风) — 大字 quote + 作者 + 出处
          // 不跑 _isDemo / _needsVpn / AI 摘要 / 视频 iframe / TTS 等通用 block
          if (item.id.startsWith('quote_'))
            _QuoteReadLayout(
              item: item,
              scale: scale,
              isEn: isEn,
              userType: widget.userType,
              scene: widget.scene,
            ),
          if (!item.id.startsWith('quote_'))
          SingleChildScrollView(
            controller: _scrollCtrl,
            padding: EdgeInsets.all(20 * scale),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 6/12 加: 演示数据 banner（不骗试用者）
            if (_isDemo(item))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isEn
                            ? 'Curated sample. "Open original" goes to the source platform\'s search results.'
                            : '示例内容，手工挑选的；"去原站"会跳到该平台的搜索结果。',
                        style: TextStyle(fontSize: 12 * scale, color: Colors.brown.shade700),
                      ),
                    ),
                  ],
                ),
              )
            // 6/12: VPN 提示（海外平台才需要）
            else if (_needsVpn(item))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_lock, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isEn
                            ? 'External platform. You may need a VPN to open it.'
                            : '海外平台，打开可能需要梯子。',
                        style: TextStyle(fontSize: 12 * scale, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            // Title
            Text(
              item.title,
              style: TextStyle(
                fontSize: 22 * scale,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            ),
            SizedBox(height: 12 * scale),
            // Meta info
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.source,
                    style: TextStyle(fontSize: 12 * scale, color: AppTheme.primary),
                  ),
                ),
                SizedBox(width: 12 * scale),
                Icon(Icons.access_time, size: 14 * scale, color: AppTheme.textLight),
                SizedBox(width: 4 * scale),
                Text(
                  item.duration,
                  style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight),
                ),
                // 7/1: audio 类型给 "原站" 外跳按钮 (TTS 听不下, 去原站听真音频)
                if (item.contentType == ContentType.audio &&
                    item.externalUrl != null &&
                    item.externalUrl!.isNotEmpty) ...[
                  SizedBox(width: 8 * scale),
                  GestureDetector(
                    onTap: () async {
                      try {
                        await launchUrl(
                          Uri.parse(item.externalUrl!),
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {}
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 12 * scale, color: AppTheme.primary),
                          SizedBox(width: 3 * scale),
                          Text(
                            isEn ? 'Original' : '原站',
                            style: TextStyle(fontSize: 11 * scale, color: AppTheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _PriceBadgeWidget(item: item, scale: scale),
              ],
            ),
            SizedBox(height: 20 * scale),
            // 视频小窗（6/7 多形式：仅 video 类型显示）
            _buildVideoPlayer(),
            Divider(height: 1 * scale),
            SizedBox(height: 20 * scale),
            // 6/11 B2: 测一测（仅 article / video 有意义）
            // 6/29 15:55: audio 跳过 — QuizPanel 基于 description AI 出题, 跟音频内容无关会错位
            if (item.contentType == ContentType.article ||
                item.contentType == ContentType.video)
              Padding(
                padding: EdgeInsets.only(bottom: 20 * scale),
                child: QuizPanel(
                  item: item,
                  scale: scale,
                  languageCode: isEn ? 'en' : 'zh',
                ),
              ),
            // 6/29 15:55: AI 摘要 + Main content + 延伸阅读 — audio 不显示 (description 太短会错位)
            if (item.contentType != ContentType.audio) ...[
            Container(
              padding: EdgeInsets.all(16 * scale),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(8 * scale),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_awesome, size: 20 * scale, color: AppTheme.primary),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEn ? 'AI Summary' : 'AI 摘要',
                          style: TextStyle(
                            fontSize: 11 * scale,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4 * scale),
                        Text(
                          _getSummaryText(),
                          style: TextStyle(fontSize: 13 * scale, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24 * scale),
            // Main content
            Text(
              item.description,
              style: TextStyle(
                fontSize: 16 * scale,
                height: 1.8,
                color: AppTheme.textDark,
              ),
            ),
            SizedBox(height: 16 * scale),
            // 6/25 A: 站内直接读全文按钮 (web 端 iframe, mobile 不支持)
            if (item.externalUrl != null)
              _buildInlineReadButton(),
            SizedBox(height: 16 * scale),
            // 6/25 A: 展开后的 inline read 区域 (点击后才加载, 避免一进页就调外网)
            if (_showInlineRead && item.externalUrl != null)
              _buildInlineReadSection(),
            SizedBox(height: 24 * scale),
            // 6/25 B: 延伸阅读分区（之前跟 description 混一起无区分）
            Container(
              padding: EdgeInsets.all(14 * scale),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu_book_outlined, size: 16 * scale, color: AppTheme.primary),
                      SizedBox(width: 6 * scale),
                      Text(
                        isEn ? 'Extended preview' : '延伸阅读',
                        style: TextStyle(
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10 * scale),
                  Text(
                    _getExtendedContent(),
                    style: TextStyle(
                      fontSize: 15 * scale,
                      height: 1.8,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16 * scale),
            // 6/25 C: AI 摘要折叠区 (手动点, 30s 兌底, 失败可重试)
            _buildAiSummarySection(),
            ],
            SizedBox(height: 32 * scale),
            // TTS 播放栏（6/7 新加）
            if (_ttsAvailable)
              Container(
                padding: EdgeInsets.all(12 * scale),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    IconButton.filled(
                      onPressed: _togglePlay,
                      // 6/14 v4 老人模式: 64x64
                      padding: EdgeInsets.all(12 * scale),
                      constraints: BoxConstraints.tightFor(width: 56 * scale, height: 56 * scale),
                      icon: Icon(
                        _isSpeaking && !_isPaused
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 28 * scale,
                      ),
                    ),
                    SizedBox(width: 8 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isSpeaking
                                ? (_isPaused
                                    ? (isEn ? 'Paused' : '已暂停')
                                    : (isEn ? 'Reading...' : '正在朗读...'))
                                : (isEn ? 'Listen to this article' : '听文章'),
                            style: TextStyle(
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2 * scale),
                          Text(
                            isEn
                                ? 'AI-generated voice • Browser TTS'
                                : 'AI 朗读 · 浏览器原生语音',
                            style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ),
                    if (_isSpeaking)
                      IconButton(
                        onPressed: _stop,
                        icon: Icon(Icons.stop, color: AppTheme.textLight),
                      ),
                  ],
                ),
              ),
            // 7/1: 朗读进度条 (4px 高, TtsService.progress ValueNotifier 0..1)
            ValueListenableBuilder<double>(
              valueListenable: TtsService.progress,
              builder: (_, value, __) => Padding(
                padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                child: LinearProgressIndicator(
                  value: _isSpeaking ? value : 0,
                  minHeight: 4 * scale,
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary.withOpacity(0.7)),
                ),
              ),
            ),
            SizedBox(height: 24 * scale),
            // 付费内容提示（6/7 新加）
            if (item.priceType == ContentPriceType.paid || item.priceType == ContentPriceType.membership)
              Container(
                padding: EdgeInsets.all(16 * scale),
                margin: EdgeInsets.only(bottom: 16 * scale),
                decoration: BoxDecoration(
                  color: item.priceType.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: item.priceType.color.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: item.priceType.color, size: 24 * scale),
                    SizedBox(width: 12 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEn
                                ? '${item.priceType.label} content'
                                : '${item.priceType.label}内容',
                            style: TextStyle(
                              fontSize: 14 * scale,
                              fontWeight: FontWeight.bold,
                              color: item.priceType.color,
                            ),
                          ),
                          SizedBox(height: 4 * scale),
                          Text(
                            isEn
                                ? 'You are reading a preview. The full version is on ${item.source}.'
                                : '当前为预览片段，完整内容请前往${item.source}阅读。',
                            style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Divider(height: 1 * scale),
            SizedBox(height: 16 * scale),
            // Copyright
            Center(
              child: Text(
                isEn
                    ? 'Content source: ${item.source} | All rights belong to original creators'
                    : '内容来源：${item.source} | 内容版权归属原作者',
                style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 32 * scale),
            // Open original button
            if (item.externalUrl != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: EdgeInsets.symmetric(vertical: 14 * scale),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(item.externalUrl!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
                    }
                  },
                  icon: Icon(Icons.open_in_new, color: Colors.white, size: 20 * scale),
                  label: Text(
                    item.priceType == ContentPriceType.free
                        ? (isEn ? 'Read Full on ${item.source}' : '去${item.source}阅读完整内容')
                        : (isEn ? 'Subscribe / Buy on ${item.source}' : '去${item.source}订阅/购买'),
                    style: TextStyle(color: Colors.white, fontSize: 15 * scale),
                  ),
                ),
              ),
            // 6/25 Brien 反馈 手机上 '读完了' 跟下面内容重叠 → 加底部 padding (banner 60px + 40px 安全距离)
// 6/26 Brien 00:33 '读完了, 还是重叠' → 100*scale 不够, 加到 140 (banner + 80 安全距离)
            SizedBox(height: 140 * scale),
          ],
        ),
      ),
    // 6/25 v17: banner 移到常驻底部 — 避开 AppBar (避 HUD 重叠) + 不 3s 淺出
    // "读完了" 常驻底部
    if (_isCompleted && !_showAchievementBanner)
      Positioned(
        bottom: 16,
        left: 16,
        right: 16,
        child: _buildAlreadyReadBanner(),
      ),
    // 成就完成 banner 常驻底部 (不淺出, 用户手动点 X 关)
    if (_showAchievementBanner)
      Positioned(
        bottom: 16,
        left: 16,
        right: 16,
        child: _buildAchievementBanner(),
      ),
    // 6/25 v17: HUD 计时 — 从 AppBar 移到右下角浮窗
    // 6/25 修: 跟底部 '读完了' / 成就 banner 重叠 → 移到顶部右上 AppBar 下
    Positioned(
      top: 70,
      right: 16,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              _hudText,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    ),
  ],
    ),
  );
  }

  Widget _buildInlineReadButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          setState(() {
            _showInlineRead = !_showInlineRead;
            _inlineReadTimeout = false;
          });
          // 展开后启动 8s 兌底 timer (浏览器 iframe onError 不可靠)
          if (_showInlineRead) {
            Future.delayed(const Duration(seconds: 8), () {
              if (!mounted) return;
              // 8s 后仍在显示状态且未超时 → 不动 (默认 iframe ok)
              // 要让用户主动跳走: 额外提供 "去原站" 按钮在 _buildInlineReadSection 里
            });
          }
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
          padding: EdgeInsets.symmetric(vertical: 12 * scale),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(
          _showInlineRead ? Icons.expand_less : Icons.article_outlined,
          size: 18 * scale,
          color: AppTheme.primary,
        ),
        label: Text(
          _showInlineRead
              ? (widget.isEn ? 'Hide full article' : '收起全文')
              : (widget.isEn ? 'Read full article in-app' : '站内读全文'),
          style: TextStyle(fontSize: 14 * scale, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _buildInlineReadSection() {
    if (_inlineReadTimeout) {
      return Container(
        padding: EdgeInsets.all(16 * scale),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                widget.isEn
                    ? 'Inline read unavailable. Click below to open in browser.'
                    : '站内读不可用, 点下方按钮在浏览器打开。',
                style: TextStyle(fontSize: 13 * scale),
              ),
            ),
            TextButton(
              onPressed: () => _openExternal(item.externalUrl!),
              child: Text(widget.isEn ? 'Open' : '打开'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 600,
          child: InlineReadView(url: item.externalUrl!),
        ),
        SizedBox(height: 8 * scale),
        // 兑底: "去原站读" 按钮 (iframe 加载不出或反爬时可点)
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => _openExternal(item.externalUrl!),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text(
                widget.isEn ? 'Open in browser' : '在浏览器打开',
                style: TextStyle(fontSize: 12 * scale),
              ),
            ),
            SizedBox(width: 8 * scale),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showInlineRead = false;
                  _inlineReadTimeout = false;
                });
              },
              icon: const Icon(Icons.close, size: 14),
              label: Text(
                widget.isEn ? 'Close' : '关闭',
                style: TextStyle(fontSize: 12 * scale),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openExternal(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
    }
  }

  Widget _buildAiSummarySection() {
    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16 * scale, color: AppTheme.primary),
              SizedBox(width: 6 * scale),
              Text(
                widget.isEn ? 'AI Summary' : 'AI 摘要',
                style: TextStyle(
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          if (_aiSummaryLoading)
            Row(
              children: [
                SizedBox(
                  width: 14 * scale,
                  height: 14 * scale,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Text(
                    widget.isEn
                        ? 'Generating... (first run may take 30-60s)'
                        : '生成中... (首次启动需 30-60 秒)',
                    style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
                  ),
                ),
              ],
            )
          else if (_aiSummaryFailed)
            Row(
              children: [
                Icon(Icons.error_outline, size: 16 * scale, color: Colors.orange),
                SizedBox(width: 6 * scale),
                Text(
                  widget.isEn ? 'Summary unavailable' : '摘要暂不可用',
                  style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
                ),
                SizedBox(width: 8 * scale),
                TextButton(
                  onPressed: _generateAiSummary,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    widget.isEn ? 'Retry' : '重试',
                    style: TextStyle(fontSize: 13 * scale, color: AppTheme.primary),
                  ),
                ),
              ],
            )
          else if (_aiSummary != null)
            Text(
              _aiSummary!,
              style: TextStyle(
                fontSize: 14 * scale,
                height: 1.7,
                color: AppTheme.textDark,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _generateAiSummary,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.auto_awesome, size: 14 * scale, color: AppTheme.primary),
              label: Text(
                widget.isEn ? 'Generate AI Summary' : '生成 AI 摘要',
                style: TextStyle(fontSize: 13 * scale, color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final embedUrl = buildVideoEmbedUrl(item);
    if (embedUrl == null) {
      // 6/9 修：videoId=null（BV1example1 stub）但有 externalUrl → 跳原站
      if (item.contentType == ContentType.video && item.externalUrl != null) {
        return _buildExternalVideoLink(item.externalUrl!);
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IframeVideoView(embedUrl: embedUrl, externalUrl: item.externalUrl),
        ),
        SizedBox(height: 8 * scale),
        Row(
          children: [
            Icon(item.contentType.icon, size: 14 * scale, color: AppTheme.textLight),
            SizedBox(width: 4 * scale),
            Text(
              isEn
                  ? 'Embedded player • ${item.videoPlatform?.name ?? ''}'
                  : '嵌播放 · ${item.videoPlatform?.name ?? ''}',
              style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
            ),
            Spacer(),
            if (item.externalUrl != null)
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(item.externalUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
                  }
                },
                icon: Icon(Icons.open_in_new, size: 14 * scale),
                label: Text(
                  isEn ? 'Open on ${item.source}' : '去${item.source}看',
                  style: TextStyle(fontSize: 12 * scale),
                ),
              ),
          ],
        ),
        SizedBox(height: 16 * scale),
      ],
    );
  }

  // 6/14 详情页完成:"已读完" banner（重入时显示）
  // 7/20 12:24 Brien "听一听还挂" → 真凶: BackdropFilter shader 在 Flutter 3.27.4 canvaskit 触发 null check
  // 修法: 去掉 BackdropFilter + ImageFilter.blur, 用纯 Container + 高不透明色模拟玻璃
  Widget _buildAlreadyReadBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 18 * scale, color: GlassStyle.accent),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              isEn ? 'Finished reading · scroll to re-mark' : '已读完 · 滑到底可重新标记',
              style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }

  // 6/14 详情页完成:scroll 到底 3 秒淡出成就 banner
  // 7/20 12:24 同步去 BackdropFilter (跟 _buildAlreadyReadBanner 同原因)
  Widget _buildAchievementBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events, size: 18 * scale, color: GlassStyle.accent),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              isEn ? '🎉 Marked as read · 100%' : '🎉 已标记为读完 · 100%',
              style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w700, color: AppTheme.textDark),
            ),
          ),
          // 6/25 v17: 手动 X 关 banner
          GestureDetector(
            onTap: () => setState(() => _showAchievementBanner = false),
            child: Icon(Icons.close, size: 18 * scale, color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }

  IconData _iconForSource(String source) {
    switch (source) {
      case '36kr': return Icons.business_center;
      case 'zhihu': return Icons.forum;
      case 'spotify': return Icons.music_note;
      case 'youtube': return Icons.play_circle_outline;
      case 'apple': return Icons.podcasts;
      case 'ximalaya': return Icons.headphones;
      case 'lizhiFM': return Icons.mic;
      case 'rss': return Icons.rss_feed;
      default: return Icons.article_outlined;
    }
  }

  String _getSummaryText() {
    final summaries = isEn
        ? [
            'This article discusses key insights that challenge conventional thinking. Based on trending data, this piece has been bookmarked by thousands of readers in your community.',
            'Community pick: This content resonates with ${item.source} users who share similar interests. Key takeaways can be absorbed in about 3 minutes.',
            'Trending in your network: This article has been widely shared. Core thesis: small consistent actions lead to big changes over time.',
          ]
        : [
            '本文探讨了核心观点，挑战传统认知。结合热度数据，这篇文章已被同温层数千人收藏。',
            '社区精选：这篇文章与同兴趣圈层产生共鸣，核心要点约3分钟可以消化。',
            '在你关注的圈子里很热：这篇文章被广泛传阅，核心启示：小的坚持积累带来大改变。',
          ];
    final hash = item.title.hashCode.abs();
    return summaries[hash % summaries.length];
  }

  String _getExtendedContent() {
    if (isEn) {
      return 'This is a simulated extended preview of the article content. In a production version, this would fetch the actual article text from the source platform or a cached version.\n\n'
          'The full article would discuss the topic in depth, providing additional context, examples, and insights that build upon the brief description already shown.\n\n'
          'Readers typically spend 5-10 minutes on this type of content, making it perfect for 碎片时间 consumption.';
    } else {
      return '这里是文章内容的模拟预览。在生产环境中，这里会显示从平台获取的真实文章正文。\n\n'
          '完整文章会深入讨论话题，提供更多背景、案例和洞察。\n\n'
          '读者通常在这类内容上花费5-10分钟，非常适合碎片时间阅读。';
    }
  }

  Widget _buildExternalVideoLink(String url) {
    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        // 7/19 fix v2: LinearGradient 全量清除
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.play_circle_filled, size: 48 * scale, color: AppTheme.primary),
          SizedBox(height: 8 * scale),
          Text(
            isEn ? 'Tap to open video in browser' : '点此在浏览器打开视频',
            style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600, color: AppTheme.primary),
          ),
          SizedBox(height: 4 * scale),
          Text(
            url,
            style: TextStyle(fontSize: 10 * scale, color: AppTheme.textLight),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 12 * scale),
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: Text(isEn ? 'Open' : '打开'),
          ),
        ],
      ),
    );
  }
}


// 6/9 价格徽章
class _PriceBadgeWidget extends StatelessWidget {
  final ContentItem item;
  final double scale;
  const _PriceBadgeWidget({required this.item, required this.scale});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        color: item.priceType.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        item.priceNote ?? item.priceType.label,
        style: TextStyle(fontSize: 11 * scale, color: item.priceType.color, fontWeight: FontWeight.w500),
      ),
    );
  }
}


// 6/30 11:48 SOUL #32: 浮起 SnackBar, 不挡底部 nav
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


// 7/15 Q4: Quote 详情页 layout (跟 Hero / banner 同款紫色渐变 + 圆 avatar + 作者出处)
// 复用 _DailyEncouragementBanner 视觉, 但去 onTap 等动效
class _QuoteReadLayout extends StatelessWidget {
  final ContentItem item;
  final double scale;
  final bool isEn;
  // 7/15 17:19: 跟 widget.item.userType/scene 同源 (Hero 详情 page)
  final UserType? userType;
  final Scene? scene;

  const _QuoteReadLayout({
    required this.item,
    required this.scale,
    required this.isEn,
    this.userType,
    this.scene,
  });

  String _authorInit() {
    final t = item.title;
    if (t.isEmpty) return '✦';
    return t.characters.first;
  }

  // 从 description 解析 quote text + source (7/15 banner save 格式: "quote — 《source》")
  (String, String?) _parse() {
    final desc = item.description ?? '';
    final idx = desc.indexOf(' — ');
    if (idx > 0) {
      return (desc.substring(0, idx), desc.substring(idx + 3));
    }
    return (desc, null);
  }

  @override
  Widget build(BuildContext context) {
    final (text, sourceRaw) = _parse();
    final source = sourceRaw != null && sourceRaw.startsWith('《') && sourceRaw.endsWith('》')
        ? sourceRaw.substring(1, sourceRaw.length - 1)
        : sourceRaw;
    final d = item.lastReadAt ?? DateTime.now();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20 * scale, 80 * scale, 20 * scale, 20 * scale), // top 给 AppBar 让位
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部紫色 Hero (跟收藏页 hero 卡同款)
          Container(
            decoration: BoxDecoration(
              // 7/19 fix v2: LinearGradient 全量清除
              color: const Color(0xFF7C5CFC),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C5CFC).withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: EdgeInsets.all(24 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72 * scale,
                      height: 72 * scale,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _authorInit(),
                        style: TextStyle(color: Colors.white, fontSize: 28 * scale, fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox(width: 16 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 作者 (title)
                          Text(
                            item.title,
                            style: TextStyle(color: Colors.white, fontSize: 22 * scale, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (source != null && source.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 4 * scale),
                              child: Text(
                                '《${source}》',
                                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14 * scale),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20 * scale),
                // quote 全文 (大 italic)
                Text(
                  '“${text}”',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18 * scale,
                    fontStyle: FontStyle.italic,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 16 * scale),
                // 底部: 收藏时间
                Row(
                  children: [
                    Icon(Icons.bookmark, color: Colors.white.withOpacity(0.7), size: 14 * scale),
                    SizedBox(width: 6 * scale),
                    Text(
                      '《收藏于 ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}》',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11 * scale),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 20 * scale),
          // 下面加分隔线 + "在 quote 详情" 提示 (将来加 Q2 关联阅读, 现在先空)
          Container(
            padding: EdgeInsets.all(16 * scale),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEn ? 'Reading time: ${item.duration}' : '阅读时长: ${item.duration}',
                    style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20 * scale),

          // 7/15 16:44 修回: TTS 朗读 quote 全文 (听一句)
          // 听 button (跟通用内容详情页同步, 复用 TtsService)
          _QuoteTtsSection(quoteText: text, scale: scale, isEn: isEn),
          SizedBox(height: 16 * scale),

          // 7/15 16:44 修回: AI 摘要 (LLM 调用, 30s 兌底)
          _QuoteAiSummarySection(quoteText: text, author: item.title, scale: scale, isEn: isEn),
          SizedBox(height: 16 * scale),

          // 7/31 A: 作者生平 + 历史背景 (7b 调, 7s 返)
          _QuoteHistorySection(quoteText: text, author: item.title, source: source, scale: scale, isEn: isEn),
          SizedBox(height: 16 * scale),

          // 7/31 B: 延伸思考 / 现代应用 (7b 调, 7s 返)
          _QuoteExtendedSection(quoteText: text, author: item.title, scale: scale, isEn: isEn),
          SizedBox(height: 16 * scale),

          // 7/31 H3 demo Phase 1: UI 占位卡片 (沿用 #6 #8 能跑起来 > 等完美)
          //   完整实现等 Brien 拍 API key + quota 后再接 (沿用 #113 不可逆公开配置)
          _QuoteH3VideoSection(quoteText: text, author: item.title, scale: scale, isEn: isEn),
          SizedBox(height: 16 * scale),

          // 7/15 16:56 Q2: 真接关联阅读 (Hero 详情页底部) — 跟 banner sheet 同源算法
          // 17:19: userType/scene 从 ContentReaderScreen 透传进来 (兑底 officeWorker/learn)
          // 7/31 C: QuoteRelatedEngine prompt 升级 (补 5 条 LLM 兜底)
          _QuoteRelatedSection(
            quoteText: text,
            author: item.title,
            source: source,
            scale: scale,
            isEn: isEn,
            userType: userType,
            scene: scene,
          ),
          SizedBox(height: 16 * scale),  // 喂内边距到问 AI 按钮
          SizedBox(height: 24 * scale),

          // 底部: 问 AI 按钮 (复用 banner 那条)
          // 7/31 沿用 #6 #8 #103: 用户点 = “让 AI 解释这句”, AI 应主动回答,
          //   不是只弹聊天界面让用户自己打问题. autoAskQuote=true 后 AI 自动生成解释
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.black54,
                  builder: (_) => AiAssistantScreen(
                    isEn: isEn,
                    isElderlyMode: false,
                    userTypeName: 'you',
                    contextQuote: text,
                    scene: null,
                    autoAskQuote: true,
                  ),
                );
              },
              icon: Icon(Icons.support_agent, size: 18 * scale, color: const Color(0xFF7C5CFC)),
              label: Text(
                isEn ? 'Ask AI about this quote' : '问 AI 这句什么意思',
                style: TextStyle(color: const Color(0xFF7C5CFC), fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 12 * scale),
                side: BorderSide(color: const Color(0xFF7C5CFC).withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 7/15 16:44 修回: TTS 朗读 (复用 TtsService)
// 状态机 (跟通用详情页同步)
class _QuoteTtsSection extends StatefulWidget {
  final String quoteText;
  final double scale;
  final bool isEn;
  const _QuoteTtsSection({required this.quoteText, required this.scale, required this.isEn});
  @override
  State<_QuoteTtsSection> createState() => _QuoteTtsSectionState();
}
class _QuoteTtsSectionState extends State<_QuoteTtsSection> {
  bool _speaking = false;
  bool _paused = false;
  bool _checking = true;
  bool _available = false;
  @override
  void initState() {
    super.initState();
    TtsService.instance.isAvailable().then((v) {
      if (mounted) setState(() { _available = v; _checking = false; });
    });
  }
  Future<void> _toggle() async {
    if (_speaking && !_paused) {
      await TtsService.instance.pause();
      setState(() => _paused = true);
    } else if (_paused) {
      await TtsService.instance.resume();
      setState(() => _paused = false);
    } else {
      await TtsService.instance.speak(widget.quoteText);
      setState(() { _speaking = true; _paused = false; });
    }
  }
  Future<void> _stop() async {
    await TtsService.instance.stop();
    setState(() { _speaking = false; _paused = false; });
  }
  @override
  void dispose() { TtsService.instance.stop(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_checking) return const SizedBox.shrink();
    if (!_available) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(12 * widget.scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          IconButton.filled(
            onPressed: _toggle,
            padding: EdgeInsets.all(12 * widget.scale),
            constraints: BoxConstraints.tightFor(width: 56 * widget.scale, height: 56 * widget.scale),
            icon: Icon(
              _speaking && !_paused ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 28 * widget.scale,
            ),
          ),
          SizedBox(width: 8 * widget.scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _speaking ? (_paused ? (widget.isEn ? 'Paused' : '已暂停') : (widget.isEn ? 'Reading...' : '正在朗读...')) : (widget.isEn ? 'Listen to this quote' : '听这句名言'),
                  style: TextStyle(fontSize: 13 * widget.scale, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2 * widget.scale),
                Text(
                  widget.isEn ? 'Browser TTS · tap to play' : '浏览器原生语音 - 点击试听',
                  style: TextStyle(fontSize: 11 * widget.scale, color: AppTheme.textLight),
                ),
              ],
            ),
          ),
          if (_speaking)
            IconButton(
              onPressed: _stop,
              icon: Icon(Icons.stop, color: AppTheme.textLight),
            ),
        ],
      ),
    );
  }
}

// 7/31 A: 作者生平 + 历史背景 (沿用 #6 #8 能跑起来 > 等完美)
class _QuoteHistorySection extends StatefulWidget {
  final String quoteText;
  final String author;
  final String? source;
  final double scale;
  final bool isEn;
  const _QuoteHistorySection({
    required this.quoteText,
    required this.author,
    required this.scale,
    required this.isEn,
    this.source,
  });
  @override
  State<_QuoteHistorySection> createState() => _QuoteHistorySectionState();
}
class _QuoteHistorySectionState extends State<_QuoteHistorySection> {
  String? _history;
  bool _loading = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _generate();
  }
  Future<void> _generate() async {
    if (_loading || _history != null) return;
    setState(() { _loading = true; _failed = false; });
    final src = widget.source != null ? '、出自《${widget.source}》' : '';
    // 7/31 沿用 #121: 7b 在 NAS CPU 上 30s timeout 太短（实测 31s）, 改 60s
    // 沿用 #107: prompt 加不确定时只说不知道, 避免 7b 瞎编
    final prompt = widget.isEn
        ? 'Author: ${widget.author}${src}. Quote: "${widget.quoteText}".\n\nIn 80 words or fewer, briefly introduce the author\'s background and the historical context of this quote. If you are not sure about this specific quote or author, say "I am not familiar with this specific quote" — DO NOT make up facts. Reply in English.'
        : '作者: ${widget.author}${src}\n名言: "${widget.quoteText}"\n\n用 80 字以内介绍这位作者的生平和这句名言的历史背景, 不要复述名言本身, 直接回答。\n\n如果你是 7b 小模型, 不熟悉这句或这位作者, 只说 "我对这句不熟悉, 换个试试" — 不要编造事实。';
    try {
      final result = await LlmService.generateRaw(prompt, isEn: widget.isEn)
        .timeout(const Duration(seconds: 60), onTimeout: () => widget.isEn ? '(History unavailable - timeout)' : '（历史背景暂不可用）');
      if (!mounted) return;
      setState(() { _history = result.trim(); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }
  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Container(
      padding: EdgeInsets.all(14 * s),
      decoration: BoxDecoration(
        color: AppTheme.secondary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.secondary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_edu, size: 16 * s, color: AppTheme.secondary),
              SizedBox(width: 6 * s),
              Text(
                widget.isEn ? 'History & Background' : '作者与历史',
                style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600, color: AppTheme.secondary),
              ),
            ],
          ),
          SizedBox(height: 10 * s),
          if (_loading)
            Row(
              children: [
                SizedBox(width: 14 * s, height: 14 * s, child: const CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10 * s),
                Expanded(child: Text(widget.isEn ? 'Loading...' : '加载中...', style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight))),
              ],
            )
          else if (_failed)
            Text(widget.isEn ? 'Unavailable' : '暂不可用', style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight))
          else if (_history != null)
            Text(_history!, style: TextStyle(fontSize: 13 * s, height: 1.6, color: AppTheme.textDark)),
        ],
      ),
    );
  }
}

// 7/31 B: 延伸思考 / 现代应用 (沿用 #6 #8)
class _QuoteExtendedSection extends StatefulWidget {
  final String quoteText;
  final String author;
  final double scale;
  final bool isEn;
  const _QuoteExtendedSection({
    required this.quoteText,
    required this.author,
    required this.scale,
    required this.isEn,
  });
  @override
  State<_QuoteExtendedSection> createState() => _QuoteExtendedSectionState();
}
class _QuoteExtendedSectionState extends State<_QuoteExtendedSection> {
  String? _extended;
  bool _loading = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _generate();
  }
  Future<void> _generate() async {
    if (_loading || _extended != null) return;
    setState(() { _loading = true; _failed = false; });
    // 7/31 沿用 #121: timeout 30s → 60s (7b 实测 31s, 边界 fail)
//   沿用 #107: 加不确定约束, 避免 7b 瞎编
    final prompt = widget.isEn
        ? 'Quote by ${widget.author}: "${widget.quoteText}".\n\nGive 3 brief reflections on how this quote applies to modern life or work (under 100 words total). Use bullet points. If you are not familiar with this specific quote, say so — DO NOT make up reflections.'
        : '名言作者: ${widget.author}\n名言: "${widget.quoteText}"\n\n用 100 字以内给出 3 个对现代生活或工作的延伸思考, 用项目符号列出。\n\n如果你是 7b 小模型不熟悉, 只说 "我对这句不熟悉" — 不要编造。';
    try {
      final result = await LlmService.generateRaw(prompt, isEn: widget.isEn)
        .timeout(const Duration(seconds: 60), onTimeout: () => widget.isEn ? '(Extended reflection unavailable - timeout)' : '（延伸思考暂不可用）');
      if (!mounted) return;
      setState(() { _extended = result.trim(); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }
  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Container(
      padding: EdgeInsets.all(14 * s),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates, size: 16 * s, color: Colors.amber.shade800),
              SizedBox(width: 6 * s),
              Text(
                widget.isEn ? 'Modern Reflections' : '延伸思考',
                style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600, color: Colors.amber.shade800),
              ),
            ],
          ),
          SizedBox(height: 10 * s),
          if (_loading)
            Row(
              children: [
                SizedBox(width: 14 * s, height: 14 * s, child: const CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10 * s),
                Expanded(child: Text(widget.isEn ? 'Loading...' : '加载中...', style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight))),
              ],
            )
          else if (_failed)
            Text(widget.isEn ? 'Unavailable' : '暂不可用', style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight))
          else if (_extended != null)
            Text(_extended!, style: TextStyle(fontSize: 13 * s, height: 1.6, color: AppTheme.textDark)),
        ],
      ),
    );
  }
}

// 7/31 H3 demo Phase 1: UI 占位卡片 (沿用 #6 #8 能跑起来 > 等完美)
//   完整接 MiniMax H3 API 等 Brien 拍 key + quota 后 (沿用 #113 不可逆公开配置)
//   plan: fragment_time_good/docs/H3-demo-plan.md
class _QuoteH3VideoSection extends StatefulWidget {
  final String quoteText;
  final String author;
  final double scale;
  final bool isEn;
  const _QuoteH3VideoSection({
    required this.quoteText,
    required this.author,
    required this.scale,
    required this.isEn,
  });
  @override
  State<_QuoteH3VideoSection> createState() => _QuoteH3VideoSectionState();
}
class _QuoteH3VideoSectionState extends State<_QuoteH3VideoSection> {
  bool _generating = false;
  void _onTapGenerate() {
    // 7/31 Phase 1: 占位交互 — 点击后提示用户 H3 API key 未接
    //   后续 Phase 2 接 API key + proxy 后, 改为调 h3_proxy 真生成
    setState(() { _generating = true; });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() { _generating = false; });
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(widget.isEn ? 'AI Video (coming soon)' : 'AI 解读视频 (即将上线)'),
          content: Text(
            widget.isEn
                ? 'This is a placeholder. MiniMax H3 video generation will be enabled once the API key + proxy are configured (per docs/H3-demo-plan.md).'
                : '这是占位卡片。MiniMax H3 视频生成需等 API key + proxy 接入后启用 (见 docs/H3-demo-plan.md)。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(widget.isEn ? 'OK' : '好的'),
            ),
          ],
        ),
      );
    });
  }
  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Container(
      padding: EdgeInsets.all(14 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF7C5CFC).withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C5CFC).withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_creation_outlined, size: 16, color: Color(0xFF7C5CFC)),
              SizedBox(width: 6 * s),
              Text(
                widget.isEn ? 'AI Video (15s)' : 'AI 解读视频 (15s)',
                style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600, color: const Color(0xFF7C5CFC)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.isEn ? 'Coming soon' : '即将上线',
                  style: TextStyle(fontSize: 10 * s, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * s),
          Text(
            widget.isEn
                ? 'MiniMax H3 will generate a 15-second video interpretation for this quote (image + voice + motion).'
                : 'MiniMax H3 将为这句名言生成 15 秒视频解读 (画面 + 人声 + 动作)。',
            style: TextStyle(fontSize: 12 * s, height: 1.5, color: AppTheme.textLight),
          ),
          SizedBox(height: 10 * s),
          OutlinedButton.icon(
            onPressed: _generating ? null : _onTapGenerate,
            icon: _generating
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_circle_outline, size: 18),
            label: Text(_generating
                ? (widget.isEn ? 'Generating...' : '生成中...')
                : (widget.isEn ? 'Preview (placeholder)' : '预览 (占位)')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7C5CFC),
              side: BorderSide(color: const Color(0xFF7C5CFC).withOpacity(0.4)),
              padding: EdgeInsets.symmetric(vertical: 8 * s),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// 7/15 16:44 修回: AI 摘要 (调 Ollama, 30s 兌底)
class _QuoteAiSummarySection extends StatefulWidget {
  final String quoteText;
  final String author;
  final double scale;
  final bool isEn;
  const _QuoteAiSummarySection({required this.quoteText, required this.author, required this.scale, required this.isEn});
  @override
  State<_QuoteAiSummarySection> createState() => _QuoteAiSummarySectionState();
}
class _QuoteAiSummarySectionState extends State<_QuoteAiSummarySection> {
  String? _summary;
  bool _loading = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _generate();
  }
  Future<void> _generate() async {
    if (_loading || _summary != null) return;
    setState(() { _loading = true; _failed = false; });
    final prompt = widget.isEn
        ? '\${widget.author}: "“widget.quoteText”\n\nBriefly explain what this quote means (max 100 words). Reply in English.'
        : '作者: \${widget.author}\n名言: "\${widget.quoteText}"\n\n用 80 字以内解释这句名言的意思, 不要复述, 不要标题, 直接回答。';
    try {
      final result = await LlmService.generateRaw(prompt, isEn: widget.isEn)
        .timeout(const Duration(seconds: 30), onTimeout: () => widget.isEn ? '(AI summary timeout — exceeds 30s. Ollama cold start may need ~60s for first request.)' : '（AI 摘要超时 - 超过 30s。 Ollama 冷启动首请求需约 60s。）');
      if (!mounted) return;
      setState(() { _summary = result.trim(); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14 * widget.scale),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16 * widget.scale, color: AppTheme.primary),
              SizedBox(width: 6 * widget.scale),
              Text(
                widget.isEn ? 'AI Summary' : 'AI 摘要',
                style: TextStyle(fontSize: 13 * widget.scale, fontWeight: FontWeight.w600, color: AppTheme.primary),
              ),
            ],
          ),
          SizedBox(height: 10 * widget.scale),
          if (_loading)
            Row(
              children: [
                SizedBox(width: 14 * widget.scale, height: 14 * widget.scale, child: const CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10 * widget.scale),
                Expanded(
                  child: Text(
                    widget.isEn ? 'Generating... (first run may take 30-60s)' : '生成中... (首次启动需 30-60 秒)',
                    style: TextStyle(fontSize: 12 * widget.scale, color: AppTheme.textLight),
                  ),
                ),
              ],
            )
          else if (_failed)
            Row(
              children: [
                Icon(Icons.error_outline, size: 16 * widget.scale, color: Colors.orange),
                SizedBox(width: 6 * widget.scale),
                Expanded(
                  child: Text(
                    widget.isEn ? 'Summary unavailable — Ollama offline?' : 'AI 摘要失败 - Ollama 可能离线',
                    style: TextStyle(fontSize: 12 * widget.scale, color: AppTheme.textLight),
                  ),
                ),
              ],
            )
          else if (_summary != null)
            Text(
              _summary!,
              style: TextStyle(fontSize: 13 * widget.scale, height: 1.6, color: AppTheme.textDark),
            )
          else
            Text(
              widget.isEn ? 'Tap to generate' : '点击生成分析',
              style: TextStyle(fontSize: 12 * widget.scale, color: AppTheme.textLight),
            ),
        ],
      ),
    );
  }
}


// 7/15 16:56 Q2 A: Hero 详情页关联阅读区 (用 QuoteRelatedEngine 桶搜 + LLM 补)
class _QuoteRelatedSection extends StatefulWidget {
  final String quoteText;
  final String author;
  final String? source;
  final double scale;
  final bool isEn;
  // 7/15 17:19: userType/scene 传入 (兑底)
  final UserType? userType;
  final Scene? scene;

  const _QuoteRelatedSection({
    required this.quoteText,
    required this.author,
    required this.source,
    required this.scale,
    required this.isEn,
    this.userType,
    this.scene,
  });

  @override
  State<_QuoteRelatedSection> createState() => _QuoteRelatedSectionState();
}

class _QuoteRelatedSectionState extends State<_QuoteRelatedSection> {
  late Future<List<RelatedHit>> _future;
  // 7/15: 读 widget 上的 userType/scene
  UserType? get _parentUserType => widget.userType;
  Scene? get _parentScene => widget.scene;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RelatedHit>> _load() async {
    final quote = Quote(
      text: widget.quoteText,
      author: widget.author,
      source: widget.source,
      createdAt: DateTime.now(),
    );
    // 7/15 17:19: 外面传入 userType/scene, 兑底 officeWorker/learn
    final userType = _parentUserType ?? UserType.officeWorker;
    final scene = _parentScene ?? Scene.learn;
    return QuoteRelatedEngine.findRelated(
      quote: quote,
      userType: userType,
      scene: scene,
      isEn: widget.isEn,
      limit: 5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_stories, size: 16 * s, color: AppTheme.primary),
            SizedBox(width: 6 * s),
            Text(
              widget.isEn ? 'Related to this quote' : '跟这句相关的',
              style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700, color: AppTheme.textDark),
            ),
          ],
        ),
        SizedBox(height: 10 * s),
        FutureBuilder<List<RelatedHit>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Container(
                padding: EdgeInsets.all(16 * s),
                child: Row(
                  children: [
                    SizedBox(width: 14 * s, height: 14 * s, child: const CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10 * s),
                    Text(widget.isEn ? 'Finding related...' : '正在找相关的...', style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight)),
                  ],
                ),
              );
            }
            final hits = snapshot.data ?? [];
            if (hits.isEmpty) {
              return Container(
                padding: EdgeInsets.all(16 * s),
                decoration: BoxDecoration(
                  color: AppTheme.textLight.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_off, size: 16 * s, color: AppTheme.textLight),
                    SizedBox(width: 8 * s),
                    Expanded(
                      child: Text(
                        widget.isEn ? 'No related reading found. Try ↻ to swap quote.'
                            : '还没找到相关的延伸阅读, 试试 ↻ 换一句。',
                        style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: hits.map((h) => _RelatedHitCard(
                hit: h,
                scale: s,
                isEn: widget.isEn,
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
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _RelatedHitCard extends StatelessWidget {
  final RelatedHit hit;
  final double scale;
  final bool isEn;
  final VoidCallback? onTap;

  const _RelatedHitCard({
    required this.hit,
    required this.scale,
    required this.isEn,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Material(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(12 * s),
            child: Row(
              children: [
                Container(
                  width: 8 * s,
                  height: 8 * s,
                  decoration: BoxDecoration(
                    color: hit.fromLlm ? Colors.amber.shade700 : AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 10 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.title,
                        style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2 * s),
                      Text(
                        hit.fromLlm
                            ? (isEn ? 'AI suggest' : 'AI 推荐')
                            : hit.source,
                        style: TextStyle(fontSize: 11 * s, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios, size: 12 * s, color: AppTheme.textLight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
