import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../theme/glass_decoration.dart';
import '../services/llm_service.dart';
import '../services/news_service.dart';
import '../services/audio_play_service.dart';
import '../services/tts_service.dart';
import '../services/robot_name_service.dart';
import '../services/history_service.dart';
import '../models/models.dart';
import 'content_reader_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// 6/29 v2: AI 助手聊天 sheet (静态版, 不接 LLM)
/// - 半屏弹起 (isScrollControlled: true)
/// - 玻璃化背景
/// - 段 2 只做: 输入框 + 假回复 (写死字符串)
/// - 段 3 接 LlmService.generateStream 真流式
class AiAssistantScreen extends StatefulWidget {
  final bool isEn;
  final bool isElderlyMode;
  final String? contextQuote; // 6/29 段 4: 从 quote banner 传过来
  final String userTypeName;
  final UserType? userType; // 6/30 10:11: 帮推荐/答疑需要按角色调 LLM
  final Scene? scene; // 7/1: 推荐兑底用 userType + scene 调 NewsService
  final List<HistoryItem>? todayHistory; // 6/30 10:11: 答疑基于今日历史回答

  const AiAssistantScreen({
    super.key,
    required this.isEn,
    required this.isElderlyMode,
    required this.userTypeName,
    this.contextQuote,
    this.userType,
    this.scene,
    this.todayHistory,
  });

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode(); // 6/30 11:01: 点 "自由聊" chip 自动 focus 输入框 + 弹键盘
  final List<_ChatMessage> _messages = [];
  String _dailyGreeting = ''; // 6/30 12:23: sheet 顶部今日总结 (AI 主动提)
  List<String> _contextSuggestions = []; // 6/30 12:40: 基于今日历史的 3 个可点提问


  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadDailyGreeting(); // 6/30 12:23: 顶部总结
  }

  // 6/30 12:23: 顶部总结 — 今日历史主题 + 1 句鼓励
  Future<void> _loadDailyGreeting() async {
    final history = widget.todayHistory ?? const <HistoryItem>[];
    if (history.isEmpty) {
      // 6/30 12:23: 历史为空 → 1 句引导 (不调 LLM, 避免冷启动)
      if (!mounted) return;
      setState(() {
        _dailyGreeting = widget.isEn
            ? 'Pick a scene on Home — I\'ll help you digest what you read.'
            : '去首页选个场景看看，读完来找我帮你理清。';
        _contextSuggestions = [];
      });
      return;
    }
    // 6/30 12:40: 有历史 → 3 个上下文建议 (AI 生成, 5s 超时 fallback 静态)
    final topics = history.take(5).map((h) => h.title).join('、');
    final sys = widget.isEn
        ? '''You are an AI assistant. User opened chat. They read today: $topics.
Suggest 3 short questions (under 15 words each) they'd want to ask. One per line, no numbering, no quotes.'''
        : '''你是 AI 助手。用户刚打开 chat。他今天读了: $topics。
建议 3 个他可能想问的提问 (每条不超过 15 字)。每行一个, 不要编号, 不要引号。''';
    try {
      final buf = StringBuffer();
      await LlmService.chatStream(messages: [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': widget.isEn ? 'Suggest' : '建议'},
      ]).timeout(const Duration(seconds: 5), onTimeout: (sink) {
        sink.close();
      }).forEach((chunk) {
        buf.write(chunk);
      });
      if (!mounted) return;
      final raw = buf.toString().trim();
      // 拆行, 去空, 取前 3
      final suggestions = raw
          .split(RegExp(r'[\n\r]'))
          .map((s) => s.trim().replaceAll(RegExp(r'^[\d\.\-\*\s]+'), ''))
          .where((s) => s.isNotEmpty && s.length <= 30)
          .take(3)
          .toList();
      if (mounted) {
        setState(() {
          _contextSuggestions = suggestions.isNotEmpty
              ? suggestions
              : _staticSuggestions(history, topics);
          _dailyGreeting = '';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contextSuggestions = _staticSuggestions(history, topics);
        _dailyGreeting = '';
      });
    }
  }

  // 6/30 12:40: LLM 失败 fallback 静态 3 个建议
  List<String> _staticSuggestions(List<HistoryItem> history, String topics) {
    final firstTitle = history.first.title;
    return widget.isEn
        ? [
            'Summarize what I read today',
            'Why does "$firstTitle" matter?',
            'What should I read next?',
          ]
        : [
            '总结一下今天读的',
            '为什么《$firstTitle》重要?',
            '下一篇读什么?',
          ];
  }
  static const _historyKey = 'ai_chat_history_v1';
  static const _maxHistory = 30; // 保留最近 30 条

  // 6/29 16:09 Brien 反馈: 关 sheet 重开, 聊天记录丢了
  // 修: SharedPreferences 存最近 30 条消息 (JSON), initState 加载
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) {
        _addWelcome();
        return;
      }
      final list = jsonDecode(raw) as List<dynamic>;
      if (list.isEmpty) {
        _addWelcome();
        return;
      }
      setState(() {
        _messages.clear();
        for (final m in list) {
          final entry = m as Map<String, dynamic>;
          // 6/29 16:23: 复原 cards 字段
          final cardsJson = entry['cards'] as List<dynamic>?;
          List<_ContentCard>? cards;
          if (cardsJson != null) {
            cards = cardsJson.map((c) {
              final cm = c as Map<String, dynamic>;
              return _ContentCard(
                title: cm['title'] as String? ?? '',
                type: cm['type'] as String? ?? 'article',
                source: cm['source'] as String? ?? '',
                duration: cm['duration'] as String? ?? '',
                url: cm['url'] as String? ?? '',
                audioUrl: cm['audioUrl'] as String?,
                realItem: null, // realItem 不存 (构造太重)
              );
            }).toList();
          }
          _messages.add(_ChatMessage(
            text: entry['text'] as String? ?? '',
            isUser: entry['isUser'] as bool? ?? false,
            cards: cards,
          ));
        }
      });
      // 6/29 20:36: 加载历史后滚到底, 看最新消息
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    } catch (_) {
      _addWelcome();
    }
  }

  void _addWelcome() {
    if (widget.contextQuote != null) {
      _messages.add(_ChatMessage(
        text: widget.isEn
            ? 'I see you tapped a quote. Ask me anything about it.'
            : '看到你点的名言了,问吧。',
        isUser: false,
      ));
    } else {
      _messages.add(_ChatMessage(
        text: widget.isEn
            ? 'Hi, I am your AI assistant. What do you want to read today?'
            : '你好,我是你的 AI 助手。今天想看点什么?',
        isUser: false,
      ));
    }
  }

  // 6/29 16:09: 保存聊天历史到 prefs (最近 30 条)
  Timer? _saveDebounce;
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _saveHistory);
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = _messages.length > _maxHistory
          ? _messages.sublist(_messages.length - _maxHistory)
          : _messages;
      final list = recent.map((m) {
        // 6/29 16:23: 存 cards (audioUrl + url + 标题等), realItem 不存
        final cardsJson = m.cards?.map((c) => {
          'title': c.title,
          'type': c.type,
          'source': c.source,
          'duration': c.duration,
          'url': c.url,
          'audioUrl': c.audioUrl,
        }).toList();
        return {
          'text': m.text,
          'isUser': m.isUser,
          if (cardsJson != null) 'cards': cardsJson,
        };
      }).toList();
      await prefs.setString(_historyKey, jsonEncode(list));
    } catch (_) {}
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _saveDebounce?.cancel();
    _saveHistory(); // 6/29 16:09: 保险存盘 (关 sheet)
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Timer? _streamTimer;
  bool _sending = false; // 6/29 17:05: 防双击
  bool _llmRetried = false; // 6/30 12:03: LLM 第一次失败自动重试 1 次, 防死循环

  // 6/29 16:59: 快捷选项卡 — 6 个一键选项, 直接走硬编码真 title (不调 LLM, 免 30s+ 慢)
  // 6/29 17:05: chip 跳过 LLM, 直接 add 真 card, 0 慢
  // 6/29 20:28: 扩到 25 个 — 覆盖 24 桶 6 userType×4 scene 80% 场景, 0 LLM 0 钱 0 token
  static const _quickPrompts = <_QuickPrompt>[
    _QuickPrompt('🇬🇧', 'BBC 英语', 'BBC 6 Minute English', 'audio'),
    _QuickPrompt('🎧', '新概念英语', '新概念英语：5 分钟一段', 'audio'),
    _QuickPrompt('🧘', '5 分钟冥想', '5 分钟办公室冥想', 'audio'),
    _QuickPrompt('🌿', '白噪音', '课间 5 分钟：白噪音 + 闭眼', 'audio'),
    _QuickPrompt('📰', '今日新闻', '得到头条：5 分钟', 'audio'),
    _QuickPrompt('💼', '哈佛商业', '哈佛商业评论：5 分钟', 'audio'),
    _QuickPrompt('📚', '樊登读书', '樊登读书：5 分钟', 'audio'),
    _QuickPrompt('🎓', '睡前英语', '睡前英语故事：5 分钟', 'audio'),
    _QuickPrompt('🔬', '今日科普', '今日科普：3 个奇闻', 'audio'),
    _QuickPrompt('🏛', '中学古诗', '中学必背古诗：5 首', 'audio'),
    _QuickPrompt('📊', 'OKR 入门', '5 分钟读懂：OKR 和 KPI 的区别', 'card'),
    _QuickPrompt('🧠', '深度工作', '深度工作法：5 分钟入门', 'article'),
    _QuickPrompt('💰', '谈加薪', '怎么跟老板谈加薪？3 步走', 'article'),
    _QuickPrompt('🏆', '精益创业', '5 分钟读懂：精益创业 MVP', 'card'),
    _QuickPrompt('📈', '增长黑客', '5 分钟读懂：增长黑客', 'article'),
    _QuickPrompt('👨‍👩‍👧', '正面管教', '5 分钟读懂：正面管教', 'article'),
    _QuickPrompt('👨‍👦', '孩子磨蹭', '孩子写作业磨蹭？3 步搞定', 'article'),
    _QuickPrompt('🏃', '跑步热身', '跑步前后：5 分钟热身', 'video'),
    _QuickPrompt('💪', '眼保健操', '课间 5 分钟：眼保健操 + 拉伸', 'video'),
    _QuickPrompt('😴', '考前放空', '考前 5 分钟放空练习', 'article'),
    _QuickPrompt('🍅', '番茄钟', '番茄钟：学 25 休 5', 'card'),
    _QuickPrompt('📐', '物理入门', '物理入门：牛顿 3 大定律', 'article'),
    _QuickPrompt('🏛', '历史今天', '历史：今天发生了什么？', 'card'),
    _QuickPrompt('🌙', '凌晨冥想', '凌晨 3 点 5 分钟：CEO 冥想', 'audio'),
    _QuickPrompt('🌅', '会议拉伸', '会议室后 5 分钟：拉伸', 'video'),
  ];

  // 6/29 17:05: chip 渲染流程 — 加用户消息 + 调 NewsService.search 加 card (不走 LLM)
  // 6/30 10:11: 能力卡分支: recommend → LLM 真推荐; qa → LLM 基于今日历史; chat → Toast
  Future<void> _sendQuick(_QuickPrompt prompt) async {
    if (_sending) return; // 6/29 17:05: 防双击
    if (prompt.id == 'chat') {
      // 6/30 11:01: 自由聊 — 自动 focus 输入框 + 弹键盘, 不弹 SnackBar 避免挡底部 nav
      _focusNode.requestFocus();
      return;
    }
    if (prompt.id == 'recommend') return _handleRecommend();
    if (prompt.id == 'qa') return _handleQa();
    _sending = true;
    setState(() {
      _messages.add(_ChatMessage(text: prompt.label, isUser: true));
    });
    _scheduleSave();
    // 6/29 17:05: 直接调 NewsService.search 拿真 ContentItem
    ContentItem? realItem;
    try {
      final hits = await NewsService().search(prompt.realTitle);
      if (hits.isNotEmpty) {
        realItem = hits.firstWhere(
          (it) => _matchType(it.contentType, prompt.type),
          orElse: () => hits.first,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    _sending = false; // 6/29 20:16: chip 路径不调 LLM, await 完就释放
    if (realItem == null) {
      setState(() {
        _messages.add(_ChatMessage(
          text: widget.isEn
              ? 'No library match for "${prompt.realTitle}".'
              : '库里没有 "${prompt.realTitle}" 的匹配。',
          isUser: false,
        ));
      });
      _scheduleSave();
      return;
    }
    setState(() {
      _messages.add(_ChatMessage(
        text: widget.isEn ? 'Here you go:' : '为你找到:',
        isUser: false,
        cards: [_ContentCard(
          title: realItem!.title,
          type: prompt.type,
          source: realItem.source,
          duration: realItem.duration,
          url: realItem.externalUrl ?? '',
          audioUrl: realItem.audioUrl,
          realItem: realItem,
        )],
      ));
    });
    _scheduleSave();
  }

  /// 6/30 10:11: 帮我推荐 — LLM 根据 userType 真推荐 3 条, 命中真库渲染 card
  Future<void> _handleRecommend() async {
    if (_sending) return;
    _sending = true;
    final userLabel = widget.userType?.title ?? widget.userTypeName;
    setState(() {
      _messages.add(_ChatMessage(
        text: widget.isEn
            ? 'Recommend something for $userLabel'
            : '为 $userLabel 推荐 3 条',
        isUser: true,
      ));
    });
    _scheduleSave();
    final aiIdx = _messages.length;
    setState(() => _messages.add(_ChatMessage(text: '', isUser: false)));
    _streamTimer?.cancel();
    // 7/1 优化: 兑底 30s → 60s — Ollama 7b cold start 5-58s (puppeteer 实测), 30s 太短总被划为"超时"
    _streamTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      if (_messages[aiIdx].text.isEmpty) {
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn ? '(still thinking...)' : '（还在想, 约 1 分钟内）',
            isUser: false,
          );
        });
      }
    });
    final libTitles = widget.isEn
        ? const [
            'BBC 6 Minute English',
            'New Concept English 5 min',
            'Today Headlines 5 min',
            'Harvard Business Review 5 min',
            'Office Meditation 5 min',
            'Commute Podcast 5 min',
            'Business Headlines 5 min',
            'Bedtime English Stories 5 min',
            '3-Minute Science 5 min',
            'School Poems Recitation 5 min',
            'OKR vs KPI 5 min',
            'Deep Work 5 min',
          ]
        : const [
            'BBC 6 Minute English',
            '新概念英语：5 分钟一段',
            '哈佛商业评论：5 分钟',
            '得到头条：5 分钟',
            '樊登读书：5 分钟',
            '5 分钟办公室冥想',
            '课间 5 分钟：白噪音 + 闭眼',
            '通勤路上：白噪音 + 闭眼',
            '今日科普：3 个奇闻',
            '睡前英语故事：5 分钟',
            '一级市场：5 分钟看融资',
            '商业要闻 5 分钟',
          ];
    final userTypeTag = widget.isEn
        ? (widget.userType?.name ?? 'student')
        : (widget.userType?.title ?? '学生');
    final sys = widget.isEn
        ? '''You are an AI reading assistant. The user is "$userTypeTag".
Recommend 3 items from this library (titles MUST match exactly):
${libTitles.map((t) => '- $t').join('\n')}
Reply ONLY a JSON array, no other text. Example:
[{"title":"BBC 6 Minute English","type":"audio"}]
Pick 3 different titles, vary types (article / audio / video).'''
        : '''你是 AI 阅读助手。用户身份: "$userTypeTag"。
从下面库里推荐 3 条 (标题必须从下面选, 不能编造):
${libTitles.map((t) => '- $t').join('\n')}
只返回 JSON 数组, 1-3 条, 不要其他文字。例:
[{"title":"BBC 6 Minute English","type":"audio"}]
类型选 3 个不同 (article / audio / video 混着来)。''';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': widget.isEn ? 'Recommend 3 for me' : '帮我推荐 3 条'},
    ];
    final buf = StringBuffer();
    LlmService.chatStream(messages: messages).listen(
      (chunk) {
        if (!mounted) return;
        _streamTimer?.cancel();
        buf.write(chunk);
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: buf.toString(),
            isUser: false,
          );
        });
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      },
      onError: (e) {
        if (!mounted) return;
        if (!_llmRetried) {
          // 6/30 12:03: 第一次失败自动重试 1 次 (免用户手点)
          _llmRetried = true;
          setState(() {
            _messages[aiIdx] = _ChatMessage(
              text: widget.isEn ? '(retrying...)' : '（重试中...）',
              isUser: false,
            );
          });
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!mounted) return;
            _sending = false;
            _handleRecommend(); // 重新调, 不重建 stream, _llmRetried 会阻止再次 retry
          });
          return;
        }
        _sending = false;
        _llmRetried = false;
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn
                ? 'LLM is slow. Tap again to retry.'
                : 'LLM 慢, 再点一次重试。',
            isUser: false,
          );
        });
      },
      onDone: () async {
        if (!mounted) return;
        _sending = false;
        _llmRetried = false;
        final raw = buf.toString().trim();
        final cards = await _tryParseCards(raw) ?? <_ContentCard>[];
        if (cards.isEmpty) {
          // 7/1 优化: 兜底给 3 条随机库内容, 不让用户卡住
          final fallbacks = await _fallbackCards();
          if (fallbacks.isEmpty) {
            setState(() {
              _messages[aiIdx] = _ChatMessage(
                text: widget.isEn
                    ? 'No library match. Try again.'
                    : '没命中库, 再点一次。',
                isUser: false,
              );
            });
          } else {
            setState(() {
              _messages[aiIdx] = _ChatMessage(
                text: widget.isEn
                    ? 'Library fallback (try more keywords next time):'
                    : '库里兑底（下次换关键词试试）:',
                isUser: false,
                cards: fallbacks,
              );
            });
          }
          _scheduleSave();
          return;
        }
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn ? 'Recommended for you:' : '为你推荐:',
            isUser: false,
            cards: cards,
          );
        });
        _scheduleSave();
      },
    );
  }

  /// 6/30 10:11: 答疑解惑 — LLM 基于今日历史回答
  Future<void> _handleQa() async {
    if (_sending) return;
    _sending = true;
    setState(() {
      _messages.add(_ChatMessage(
        text: widget.isEn
            ? 'Help me make sense of today'
            : '帮我理清今天读的东西',
        isUser: true,
      ));
    });
    _scheduleSave();
    // 6/30 12:16: 历史为空时不调 LLM (避免冷启动 30s 等), 直接给友好回复
    // 7/1: 保留现有提示 + 附建议性 follow-up (不像之前那样跳出菜单, 避免占用邮箱)
    final history = widget.todayHistory ?? const <HistoryItem>[];
    if (history.isEmpty) {
      if (!mounted) return;
      _sending = false;
      setState(() {
        _messages.add(_ChatMessage(
          text: widget.isEn
              ? 'No read history for today yet. Tap 📚 above to get a recommendation — once you finish one, come back and I\'ll help you make sense of it.'
              : '今天还没有阅读记录。点上方📚 让小 O 推荐一篇, 读完了再来找我帮你理清。',
          isUser: false,
        ));
      });
      _scheduleSave();
      return;
    }
    final aiIdx = _messages.length;
    setState(() => _messages.add(_ChatMessage(text: '', isUser: false)));
    _streamTimer?.cancel();
    // 7/1 优化: 兑底 30s → 60s — Ollama 7b cold start 5-58s (puppeteer 实测), 30s 太短总被划为"超时"
    _streamTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      if (_messages[aiIdx].text.isEmpty) {
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn ? '(still thinking...)' : '（还在想, 约 1 分钟内）',
            isUser: false,
          );
        });
      }
    });
    final historyCtx = history
        .take(8)
        .map((h) => '- ${h.title} (${h.source})')
        .join('\n');
    final sys = widget.isEn
        ? '''You are a warm AI reading assistant. The user has read these items today:
$historyCtx

User just tapped "Help me make sense of today" — give a concise summary, highlight 1-2 connections across items, and suggest 1 next step. Under 80 words. Plain text, no JSON.'''
        : '''你是温和、简洁的 AI 阅读助手。用户今天读了以下内容:
$historyCtx

用户刚点了 "帮我理清今天读的东西" — 简要总结今天主题, 指出 1-2 条内容间的联系, 建议 1 个下一步。80 字以内, 不要 JSON。''';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': widget.isEn ? 'Help me make sense' : '帮我理清'},
    ];
    final buf = StringBuffer();
    LlmService.chatStream(messages: messages).listen(
      (chunk) {
        if (!mounted) return;
        _streamTimer?.cancel();
        buf.write(chunk);
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: buf.toString(),
            isUser: false,
          );
        });
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      },
      onError: (e) {
        if (!mounted) return;
        if (!_llmRetried) {
          // 6/30 12:03: 第一次失败自动重试 1 次 (免用户手点)
          _llmRetried = true;
          setState(() {
            _messages[aiIdx] = _ChatMessage(
              text: widget.isEn ? '(retrying...)' : '（重试中...）',
              isUser: false,
            );
          });
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!mounted) return;
            _sending = false;
            _handleQa();
          });
          return;
        }
        _sending = false;
        _llmRetried = false;
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn
                ? 'LLM is slow. Tap again to retry.'
                : 'LLM 慢, 再点一次重试。',
            isUser: false,
          );
        });
      },
      onDone: () {
        if (!mounted) return;
        _sending = false;
        _llmRetried = false;
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: buf.toString().trim(),
            isUser: false,
          );
        });
        _scheduleSave();
      },
    );
  }

  void _send() {
    if (_sending) return; // 6/29 17:05: 防双击
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _sending = true;
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _controller.clear();
    });
    _scheduleSave(); // 6/29 16:09: debounce save history

    // 6/29 段 5: JSON card 模式 — AI 推内容时返回结构化 JSON, sheet 解析渲染
    final systemPrompt = widget.isEn
        ? '''You are a warm AI reading assistant.

Library titles (use EXACTLY these for recommendations):
- "BBC 6 Minute English" (audio)
- "New Concept English 5 min" (audio)
- "Today Headlines 5 min" (audio)
- "Harvard Business Review 5 min" (audio)
- "Office Meditation 5 min" (audio)
- "Commute Podcast 5 min" (audio)

Rules:
- If user mentions time, topic, type, or asks "what is good" / "recommend" / "any" → reply ONLY a JSON array.
  Examples: User: 5 min English → Reply: [{"title":"BBC 6 Minute English","type":"audio"}]
  User: any meditation? → Reply: [{"title":"Office Meditation 5 min","type":"audio"}]
  User: news today → Reply: [{"title":"Today Headlines 5 min","type":"audio"}]
  No other text. 1-3 items. type: article / audio / video / short.
- Otherwise plain text (under 60 words).'''
        : '''你是温紫、简洁的 AI 阅读助手。

库里现有的真实标题（必须从下面选, 不能编造）:
- 《BBC 6 Minute English》 (audio)
- 《新概念英语：5 分钟一段》 (audio)
- 《哈佛商业评论：5 分钟》 (audio)
- 《得到头条：5 分钟》 (audio)
- 《樊登读书：5 分钟》 (audio)
- 《5 分钟办公室冥想》 (audio)
- 《课间 5 分钟：白噪音 + 闭眼》 (audio)
- 《通勤路上：白噪音 + 闭眼》 (audio)
- 《今日科普：3 个奇闻》 (audio)
- 《睡前英语故事：5 分钟》 (audio)
- 《一级市场：5 分钟看融资》 (audio)
- 《商业要闻 5 分钟》 (audio)

规则:
- 用户提到时间 / 主题 / 类型 / "有什么" / "推荐" / "什么好" → 只返回 JSON 数组, 标题必须从上面选 (不要编造)。
  例子 1: 用户: 5 分钟英语 → 回复: [{"title":"BBC 6 Minute English","type":"audio"}]
  例子 2: 用户: 有什么冥想 → 回复: [{"title":"5 分钟办公室冥想","type":"audio"}]
  例子 3: 用户: 今日新闻 → 回复: [{"title":"得到头条：5 分钟","type":"audio"}]
  不要其他文字。1-3 条。type: article / audio / video / short。
- 其他情况普通文字 (60 字以内)。''';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    // 段 4: quote 上下文
    if (widget.contextQuote != null) {
      messages.add({
        'role': 'system',
        'content': widget.isEn
            ? 'User just tapped this quote: "${widget.contextQuote}". If they ask about it, explain in simple terms.'
            : '用户刚点了这句名言: "${widget.contextQuote}", 如果问这句, 简单解释。',
      });
    }
    // 拿历史 10 条 (避免 prompt 过长)
    final history = _messages
        .where((m) => m.text.isNotEmpty)
        .toList()
        .reversed
        .take(10)
        .toList()
        .reversed;
    for (final m in history) {
      messages.add({
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      });
    }

    // 加空 AI 消息, 流式追加
    final aiIdx = _messages.length;
    setState(() {
      _messages.add(_ChatMessage(text: '', isUser: false));
    });

    // 7/1 优化: 兑底 30s → 60s — Ollama 7b cold start 5-58s, 太短总被划为"超时"
    _streamTimer?.cancel();
    _streamTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      if (_messages[aiIdx].text.isEmpty) {
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn
                ? '(still thinking, ~1 min)'
                : '（还在想, 约 1 分钟内）',
            isUser: false,
          );
        });
      }
    });

    LlmService.chatStream(messages: messages).listen(
      (chunk) {
        if (!mounted) return;
        _streamTimer?.cancel();
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: _messages[aiIdx].text + chunk,
            isUser: false,
          );
        });
        _scheduleSave(); // 6/29 16:09: chunk 收到, debounce save
        // 滚到底 (每 chunk 滚)
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      },
      onError: (e) {
        if (!mounted) return;
        _sending = false; // 6/29 17:05: 错误也释放防双击
        _llmRetried = false; // 6/30 12:03: _send 走手动重试, 重置 flag
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn
                ? 'LLM is slow or unavailable. Send the same message again to retry.'
                : 'LLM 慢或不可用, 重新发一遍即可重试。',
            isUser: false,
          );
        });
        _scheduleSave(); // 6/29 16:17: 错误也存 prefs, 重开能看到
        // 6/29 16:12: SnackBar 提示用户重试
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEn
                ? 'Request timed out. Try again.'
                : '请求超时, 重新发一遍即可。'),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      onDone: () async {
        if (!mounted) return;
        _sending = false; // 6/29 17:05: LLM 完, 释放防双击
        final raw = _messages[aiIdx].text.trim();
        if (raw.isEmpty) {
          setState(() {
            _messages[aiIdx] = _ChatMessage(
              text: widget.isEn ? '(no response)' : '（无回复）',
              isUser: false,
            );
          });
          _scheduleSave();
          return;
        }
        // 6/29 段 5: 尝试解析 JSON card (段 6 调 NewsService.search 找真内容)
        if (raw.startsWith('[')) {
          final cards = await _tryParseCards(raw);
          if (!mounted) return;
          if (cards != null && cards.isNotEmpty) {
            setState(() {
              _messages[aiIdx] = _ChatMessage(
                text: widget.isEn ? 'I found these for you:' : '为你找到这些:',
                isUser: false,
                cards: cards,
              );
            });
            _scheduleSave();
            return;
          }
          // 6/29 16:35: AI 输出了 JSON 但 NewsService 全部找不到, 兑底提示用户
          if (cards != null && cards.isEmpty) {
            setState(() {
              _messages[aiIdx] = _ChatMessage(
                text: widget.isEn
                    ? 'No library match for this. Try different keywords (e.g. "BBC", "冥想", "5 分钟").'
                    : '库里没匹配这些标题, 换个关键词试试 (例如 "BBC", "冥想", "5 分钟")。',
                isUser: false,
              );
            });
            _scheduleSave();
            return;
          }
        }
        // 不是 JSON, 留原文字
      },
    );
  }

  // 6/29 段 6: 解析 AI JSON card + 调 NewsService.search 找真 ContentItem
  Future<List<_ContentCard>?> _tryParseCards(String raw) async {
    try {
      final start = raw.indexOf('[');
      if (start < 0) return null;
      int depth = 0;
      int? end;
      for (int i = start; i < raw.length; i++) {
        if (raw[i] == '[') depth++;
        if (raw[i] == ']') {
          depth--;
          if (depth == 0) { end = i; break; }
        }
      }
      if (end == null) return null;
      final jsonStr = raw.substring(start, end + 1);
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final newsService = NewsService();
      final out = <_ContentCard>[];
      for (final e in list) {
        // 6/29 16:26: 1.5b 偶输出纯字符串数组 ["a","b"] — 兑底
        String title = '';
        String type = 'audio';
        if (e is String) {
          title = e;
        } else if (e is Map<String, dynamic>) {
          title = (e['title'] ?? '').toString();
          type = (e['type'] ?? 'audio').toString(); // 6/29 默认 audio (推轻音乐场景)
        }
        if (title.isEmpty) continue;
        // 搜真内容 — 6/29 16:35: 找不到就不渲染该 card (避免点开错位)
        // 7/1 优化: 模糊匹配兜底 — title 切词后任一 keyword 命中都算
        ContentItem? realItem;
        try {
          final hits = await newsService.search(title);
          if (hits.isNotEmpty) {
            // 优先同类型
            realItem = hits.firstWhere(
              (it) => _matchType(it.contentType, type),
              orElse: () => hits.first,
            );
          } else {
            // L2 fuzzy: title 按空白 + 中文标点切片, 任一 ≥2 字 keyword 命中标题/描述
            final kw = _splitTitleKeywords(title);
            for (final k in kw) {
              if (k.length < 2) continue;
              final fuzzyHits = await newsService.search(k);
              if (fuzzyHits.isNotEmpty) {
                realItem = fuzzyHits.firstWhere(
                  (it) => _matchType(it.contentType, type),
                  orElse: () => fuzzyHits.first,
                );
                break;
              }
            }
          }
        } catch (_) {}
        if (realItem == null) continue; // 6/29 16:35: 过滤掉找不到的 card
        out.add(_ContentCard(
          title: title,
          type: type,
          source: realItem.source, // 7/1: 移掉死循环 null-aware (realItem 已 non-null)
          duration: realItem.duration ?? '',
          url: realItem.externalUrl ?? '',
          audioUrl: realItem.audioUrl,
          realItem: realItem,
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 7/1 优化: 全库拿 3 条随机兑底 (userType + scene 过滤, 不真的纯随机)
  Future<List<_ContentCard>> _fallbackCards() async {
    try {
      final newsService = NewsService();
      final ut = widget.userType ?? UserType.student;
      // 7/1: 显式 navor 避开 dead_null_aware warning
      final Scene scene = widget.scene ?? Scene.learn;
      final pool = await newsService.getRecommendations(ut, scene);
      if (pool.isEmpty) return [];
      pool.shuffle();
      return pool.take(3).map((item) {
        return _ContentCard(
          title: item.title,
          type: item.contentType == ContentType.audio ? 'audio'
              : item.contentType == ContentType.video ? 'video'
              : item.contentType == ContentType.short ? 'short'
              : 'article',
          source: item.source,
          duration: item.duration ?? '',
          url: item.externalUrl ?? '',
          audioUrl: item.audioUrl,
          realItem: item,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // 7/1 优化: title 切片 — 模糊匹配兜底用
  // 例如 "BBC 6 Minute English" → ['BBC', '6', 'Minute', 'English']
  // 例如 "5 分钟办公室冥想" → ['5', '分钟', '办公室冥想']  (中文保留连词)
  List<String> _splitTitleKeywords(String title) {
    final t = title.trim();
    final out = <String>[];
    // 优先按中文标点切: '：' '·' '（' 等
    final parts = t.split(RegExp(r'[\s：·、，。；！？\u3000]+'));
    for (final p in parts) {
      final s = p.trim();
      if (s.isEmpty) continue;
      // 中文短词保留整, 英文长词再切单词
      if (RegExp(r'[一-龥]').hasMatch(s)) {
        out.add(s);
      } else if (s.length > 12) {
        // 长英文词 (e.g. CommutePodcast) 按 Camel 拆
        out.addAll(s.split(RegExp(r'(?=[A-Z])')).where((x) => x.length >= 3));
      } else {
        out.add(s);
      }
    }
    return out;
  }

  // 6/29 段 6: ContentType → AI type 字符串映射
  bool _matchType(ContentType ct, String aiType) {
    switch (aiType) {
      case 'audio': return ct == ContentType.audio;
      case 'video': return ct == ContentType.video;
      case 'short': return ct == ContentType.short;
      default: return ct == ContentType.article;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        // 6/29 10:42: 75% 太低, 跟主屏 banner 重叠; 提到 90%/95%
        height: MediaQuery.of(context).size.height * (widget.isElderlyMode ? 0.95 : 0.90),
        decoration: BoxDecoration(
          color: GlassStyle.sheetBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // 顶部 handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 顶部标题
            Padding(
              padding: EdgeInsets.fromLTRB(20 * scale, 12 * scale, 20 * scale, 8 * scale),
              child: Row(
                children: [
                  Container(
                    width: 36 * scale,
                    height: 36 * scale,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.support_agent,
                      color: Colors.white,
                      size: 20 * scale,
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 6/30 09:52: 跟 RobotNameService 联动, 设置改了机器人名字这里也变
                        ValueListenableBuilder<String>(
                          valueListenable: RobotNameService.notifier,
                          builder: (_, name, __) => Text(
                            name,
                            style: TextStyle(
                              fontSize: 17 * scale,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (widget.contextQuote != null)
                          Text(
                            widget.isEn ? 'Quote context' : '名言上下文',
                            style: TextStyle(
                              fontSize: 11 * scale,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: widget.isEn ? 'Close' : '关闭',
                  ),
                ],
              ),
            ),
            // 6/30 12:23: 顶部今日总结 banner — AI 主动提 (区别于被动聊天)
            // 6/30 12:40 升级: 3 个上下文建议 chip (可点) — C 功能的落地
            if (_contextSuggestions.isNotEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20 * scale, 8 * scale, 20 * scale, 8 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 14 * scale, color: const Color(0xFF7C5CFC)),
                        SizedBox(width: 6 * scale),
                        Text(
                          widget.isEn ? 'Based on today' : '基于今日',
                          style: TextStyle(
                            fontSize: 11 * scale,
                            color: const Color(0xFF7C5CFC),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6 * scale),
                    Wrap(
                      spacing: 6 * scale,
                      runSpacing: 4 * scale,
                      children: _contextSuggestions.map((s) => ActionChip(
                        label: Text(
                          s,
                          style: TextStyle(fontSize: 12 * scale),
                        ),
                        backgroundColor: const Color(0xFF7C5CFC).withOpacity(0.08),
                        side: BorderSide(color: const Color(0xFF7C5CFC).withOpacity(0.3)),
                        onPressed: () {
                          // 点 chip → 直接送到输入框 (用户可改后再发)
                          _controller.text = s;
                          _focusNode.requestFocus();
                        },
                      )).toList(),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            // 消息列表
            // 6/30 10:01: 3 能力卡挪到输入框左边常驻 (见下面 _AbilityChip), 不再空状态居中
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24 * scale),
                        child: Text(
                          widget.isEn
                              ? 'Tap a chip on the left or type below to start.'
                              : '点左边选项卡或直接打字开始。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13 * scale,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.all(16 * scale),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) => _MessageBubble(
                        message: _messages[i],
                        isElderlyMode: widget.isElderlyMode,
                      ),
                    ),
            ),
            // 段 4: contextQuote 显示在输入框上方
            if (widget.contextQuote != null)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16 * scale),
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C5CFC).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF7C5CFC).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.format_quote, color: Color(0xFF7C5CFC), size: 18),
                    SizedBox(width: 8 * scale),
                    Expanded(
                      child: Text(
                        widget.contextQuote!,
                        style: TextStyle(
                          fontSize: 13 * scale,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // 6/29 16:59: 快捷选项卡 — 一键发送真库 prompt
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.withOpacity(0.15)),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickPrompts.map((p) {
                    return Padding(
                      padding: EdgeInsets.only(right: 8 * scale),
                      child: ActionChip(
                        avatar: Text(p.emoji, style: const TextStyle(fontSize: 14)),
                        label: Text(p.label, style: TextStyle(fontSize: 13 * scale)),
                        backgroundColor: const Color(0xFF7C5CFC).withOpacity(0.08),
                        side: BorderSide(
                          color: const Color(0xFF7C5CFC).withOpacity(0.3),
                        ),
                        onPressed: () => _sendQuick(p),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // 输入框
            Container(
              padding: EdgeInsets.all(12 * scale),
              decoration: BoxDecoration(
                color: GlassStyle.sheetInputBg(context),
                border: Border(
                  top: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // 6/30 10:01: 3 个能力卡挪到聊天框左边, 常驻选项卡 (空状态也显示, 不消失)
                    _AbilityChip(
                      emoji: '💬',
                      label: widget.isEn ? 'Free chat' : '自由聊',
                      scale: scale,
                      onTap: () => _sendQuick(_AbilityCardsView.prompts[0]),
                    ),
                    SizedBox(width: 6 * scale),
                    _AbilityChip(
                      emoji: '📚',
                      label: widget.isEn ? 'Recommend' : '帮我推荐',
                      scale: scale,
                      onTap: () => _sendQuick(_AbilityCardsView.prompts[1]),
                    ),
                    SizedBox(width: 6 * scale),
                    _AbilityChip(
                      emoji: '❓',
                      label: widget.isEn ? 'Q&A' : '答疑解惑',
                      scale: scale,
                      onTap: () => _sendQuick(_AbilityCardsView.prompts[2]),
                    ),
                    SizedBox(width: 10 * scale),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode, // 6/30 11:01: 点自由聊 chip 自动获焦
                        style: TextStyle(fontSize: 15 * scale),
                        decoration: InputDecoration(
                          hintText: widget.isEn ? 'Ask anything...' : '问点什么...',
                          hintStyle: TextStyle(
                            fontSize: 14 * scale,
                            color: Colors.grey[500],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.1),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16 * scale,
                            vertical: 10 * scale,
                          ),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    SizedBox(width: 8 * scale),
                    Material(
                      color: const Color(0xFF7C5CFC),
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        onTap: _send,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: EdgeInsets.all(12 * scale),
                          child: Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20 * scale,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final List<_ContentCard>? cards; // 6/29 段 5: AI 推的 card 列表
  _ChatMessage({required this.text, required this.isUser, this.cards});
}

// 6/29 17:05: chip 配置 — emoji + label + 真 title + type
class _QuickPrompt {
  final String emoji;
  final String label;
  final String realTitle;
  final String type;
  final String? id; // 6/30 10:11: 能力卡 ID ('recommend' / 'qa' / null=原始 chip)
  const _QuickPrompt(this.emoji, this.label, this.realTitle, this.type, {this.id});
}

/// 6/30 09:42: 首次/空状态展示 — 3 个能力卡 (自由聊/帮我推荐/答疑解惑)
/// 6/30 10:01: 3 个能力卡 → 输入框左侧常驻选项卡 (不随消息消失)
/// 保留 prompts 常量给 _AbilityChip 复用
class _AbilityCardsView {
  static const prompts = <_QuickPrompt>[
    // 自由聊 — 不接 LLM, 直接走输入框文本路径 (用户在输入框随便问, _send 处理)
    _QuickPrompt('💬', '自由聊', '', 'article', id: 'chat'),
    // 帮我推荐 — 走 LLM, 根据 userType 真推荐 3 条命中库
    _QuickPrompt('📚', '帮我推荐', '', 'article', id: 'recommend'),
    // 答疑解惑 — 走 LLM, 基于今日历史回答
    _QuickPrompt('❓', '答疑解惑', '', 'article', id: 'qa'),
  ];
}

/// 6/30 10:01: 单个能力 chip — 输入框左侧圆形 emoji 按钮 + tooltip
class _AbilityChip extends StatelessWidget {
  final String emoji;
  final String label;
  final double scale;
  final VoidCallback onTap;

  const _AbilityChip({
    required this.emoji,
    required this.label,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = 36.0 * scale;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFF7C5CFC).withOpacity(0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF7C5CFC).withOpacity(0.3),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              emoji,
              style: TextStyle(fontSize: 18 * scale),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentCard {
  final String title;
  final String type; // article | audio | video | short
  final String source;
  final String duration;
  final String url;
  final String? audioUrl; // 6/29 段 6: 真播音乐用
  final ContentItem? realItem; // 6/29 段 6: 搜到的真 ContentItem (跳转 reader 用)
  _ContentCard({
    required this.title,
    required this.type,
    required this.source,
    required this.duration,
    required this.url,
    this.audioUrl,
    this.realItem,
  });
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isElderlyMode;

  const _MessageBubble({required this.message, required this.isElderlyMode});

  @override
  Widget build(BuildContext context) {
    final scale = isElderlyMode ? 1.3 : 1.0;
    final isUser = message.isUser;
    // 6/29 段 5: 有 cards 走列卡渲染
    if (message.cards != null && message.cards!.isNotEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 6 * scale),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.text.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: 6 * scale, left: 4),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 12 * scale,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ...message.cards!.map((c) => _CardTile(card: c, scale: scale)),
            ],
          ),
        ),
      );
    }
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4 * scale),
        padding: EdgeInsets.symmetric(
          horizontal: 14 * scale,
          vertical: 10 * scale,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF7C5CFC)
              : Colors.grey.withOpacity(0.15),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18 * scale),
            topRight: Radius.circular(18 * scale),
            bottomLeft: Radius.circular(isUser ? 18 * scale : 4 * scale),
            bottomRight: Radius.circular(isUser ? 4 * scale : 18 * scale),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 14 * scale,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final _ContentCard card;
  final double scale;
  const _CardTile({required this.card, required this.scale});

  IconData get _typeIcon {
    switch (card.type) {
      case 'audio': return Icons.headphones;
      case 'video': return Icons.play_circle_outline;
      case 'short': return Icons.flash_on;
      default: return Icons.article_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 6 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C5CFC).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // 6/29 段 6: 优先用 NewsService.search 找的真 ContentItem
            // 6/29 12:30 Brien 反馈: 兑底 mock 给出 AI 编的 URL (蜻蜓 FM 错的 URL), 错位内容
            // 修: 找不到真内容 → SnackBar 提示, 不跳 reader 避免 AI 编 URL 进去
            if (card.realItem == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '库里没有 "${card.title}" 的匹配内容, 换个关键词试试。',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }
            final item = card.realItem!;
            // 6/29 15:55: audio 三层 fallback — audioUrl 真播 → TTS 读 → externalUrl 跳原文
            if (card.type == 'audio' && (card.audioUrl?.isNotEmpty ?? false)) {
              AudioPlayService().play(item);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '♪ ' + (card.title.length > 30
                        ? card.title.substring(0, 30) + '…'
                        : card.title),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            // 没 audioUrl → 有 externalUrl 跳原文, 没 URL 才 TTS 读
            if (card.type == 'audio' && (item.externalUrl?.isNotEmpty ?? false)) {
              final uri = Uri.parse(item.externalUrl!);
              launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('♫ 跳 ' + (item.source.isNotEmpty ? item.source : '原文')),
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            if (card.type == 'audio') {
              // 6/29 16:29: 兑底 — 没 audioUrl 没 externalUrl, TTS 读标题
              final ttsText = item.title;
              if (ttsText.isNotEmpty && kIsWeb) {
                TtsService.instance.speak(ttsText);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🔊 TTS 读: ' + (item.title.length > 24
                        ? item.title.substring(0, 24) + '…'
                        : item.title)),
                    duration: const Duration(seconds: 2),
                  ),
                );
                return;
              }
            }
            if (card.type == 'audio' && (item.externalUrl?.isNotEmpty ?? false)) {
              // 跳原文 (喜马拉雅/B 站等)
              final uri = Uri.parse(item.externalUrl!);
              launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('♫ ' + (item.source.isNotEmpty ? item.source : '打开原文')),
                  duration: const Duration(seconds: 2),
                ),
              );
              return;
            }
            // 非 audio 跳 content reader
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ContentReaderScreen(
                item: item,
                isElderlyMode: false,
                isEn: false,
              ),
            ));
          },
          child: Padding(
            padding: EdgeInsets.all(10 * scale),
            child: Row(
              children: [
                Container(
                  width: 36 * scale,
                  height: 36 * scale,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFC).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcon, size: 18 * scale, color: const Color(0xFF7C5CFC)),
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.title,
                        style: TextStyle(
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2 * scale),
                      Text(
                        '${card.source} · ${card.duration}',
                        style: TextStyle(
                          fontSize: 11 * scale,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 18 * scale),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
