import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../theme/glass_decoration.dart';
import '../services/llm_service.dart';
import '../services/news_service.dart';
import '../services/audio_play_service.dart';
import '../models/models.dart';
import 'content_reader_screen.dart';

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

  @override
  void initState() {
    super.initState();
    // 段 4: 收到 contextQuote 时, 注入欢迎语
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

  @override
  void dispose() {
    _streamTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Timer? _streamTimer;

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _controller.clear();
    });

    // 6/29 段 5: JSON card 模式 — AI 推内容时返回结构化 JSON, sheet 解析渲染
    final systemPrompt = widget.isEn
        ? '''You are a warm, concise AI reading assistant.

RULES:
- If the user asks for a recommendation, return a JSON array (no extra text):
  [{"title":"...","type":"article|audio|video|short","source":"...","duration":"...","url":"..."}]
  Use 1-3 items. No commentary.
- Otherwise return plain text (under 80 words).
- Use the user\'s quote context if provided.

Start your reply with "[" if returning JSON, otherwise plain text.'''
        : '''你是温紫、简洁的 AI 阅读助手。

规则:
- 如果用户要推荐内容, 返回 JSON 数组 (不要额外文字):
  [{"title":"...","type":"article|audio|video|short","source":"...","duration":"...","url":"..."}]
  1-3 条, 不评论。
- 其他情况返回普通文字 (80 字以内)。
- 如果用户传了名言上下文, 可以引用。

如果返回 JSON, 以 "[" 开头; 否则普通文字。''';
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
        setState(() {
          _messages[aiIdx] = _ChatMessage(
            text: widget.isEn
                ? '(LLM error: $e)'
                : '（LLM 错误: $e）',
            isUser: false,
          );
        });
      },
      onDone: () async {
        if (!mounted) return;
        final raw = _messages[aiIdx].text.trim();
        if (raw.isEmpty) {
          setState(() {
            _messages[aiIdx] = _ChatMessage(
              text: widget.isEn ? '(no response)' : '（无回复）',
              isUser: false,
            );
          });
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
        final m = e as Map<String, dynamic>;
        final title = (m['title'] ?? '').toString();
        if (title.isEmpty) continue;
        final type = (m['type'] ?? 'article').toString();
        // 搜真内容 — 取首条匹配, 拿 ContentItem 全字段
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
        out.add(_ContentCard(
          title: title,
          type: type,
          source: realItem?.source ?? (m['source'] ?? '').toString(),
          duration: realItem?.duration ?? (m['duration'] ?? '').toString(),
          url: realItem?.externalUrl ?? (m['url'] ?? '').toString(),
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
            final ContentItem item;
            if (card.realItem != null) {
              item = card.realItem!;
            } else {
              // 兑底 mock ContentItem (没找到真内容)
              item = ContentItem(
                id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
                title: card.title,
                description: card.url.isNotEmpty ? card.url : card.source,
                duration: card.duration.isNotEmpty ? card.duration : '5 min',
                source: card.source.isNotEmpty ? card.source : 'AI',
                sourceType: ContentSource.rss,
                contentType: card.type == 'audio' ? ContentType.audio
                    : card.type == 'video' ? ContentType.video
                    : card.type == 'short' ? ContentType.short
                    : ContentType.article,
                externalUrl: card.url.isNotEmpty ? card.url : null,
                audioUrl: card.audioUrl,
              );
            }
            // 6/29 段 6: audio 类型且有 audioUrl → 直接 AudioPlayService 播
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
