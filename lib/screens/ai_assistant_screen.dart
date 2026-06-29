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

  const AiAssistantScreen({
    super.key,
    required this.isEn,
    required this.isElderlyMode,
    required this.userTypeName,
    this.contextQuote,
  });

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  static const _historyKey = 'ai_chat_history_v1';
  static const _maxHistory = 30; // 保留最近 30 条

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

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
    super.dispose();
  }

  Timer? _streamTimer;
  bool _sending = false; // 6/29 17:05: 防双击

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
  Future<void> _sendQuick(_QuickPrompt prompt) async {
    if (_sending) return; // 6/29 17:05: 防双击
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

    // 兑底 30s (6/14 v3 LLM keepalive 模式)
    _streamTimer?.cancel();
    _streamTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (_messages[aiIdx].text.isEmpty) {
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn
                ? '(LLM slow, retrying...)'
                : '（LLM 慢, 重试中...）',
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
        ContentItem? realItem;
        try {
          final hits = await newsService.search(title);
          if (hits.isNotEmpty) {
            // 优先同类型
            realItem = hits.firstWhere(
              (it) => _matchType(it.contentType, type),
              orElse: () => hits.first,
            );
          }
        } catch (_) {}
        if (realItem == null) continue; // 6/29 16:35: 过滤掉找不到的 card
        out.add(_ContentCard(
          title: title,
          type: type,
          source: realItem?.source ?? '',
          duration: realItem?.duration ?? '',
          url: realItem?.externalUrl ?? '',
          audioUrl: realItem?.audioUrl,
          realItem: realItem,
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
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
                        Text(
                          widget.isEn ? 'AI Assistant' : 'AI 助手',
                          style: TextStyle(
                            fontSize: 17 * scale,
                            fontWeight: FontWeight.w700,
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
            const Divider(height: 1),
            // 消息列表
            Expanded(
              child: ListView.builder(
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
                    Expanded(
                      child: TextField(
                        controller: _controller,
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
  const _QuickPrompt(this.emoji, this.label, this.realTitle, this.type);
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
