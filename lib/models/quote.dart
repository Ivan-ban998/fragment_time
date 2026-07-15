// lib/models/quote.dart
// 7/15 Brien 拍板: 名言内容结构要带作者/出处/翻译/日期
// 不直接动 ContentItem (那是通用 model), 独立 Quote model
//
// 与 banner / 收藏卡 / 详情页 / 私有 QuoteDetailSheet 一起用

class Quote {
  final String text;            // 主文本 (中文优先)
  final String? textEn;         // 英文翻译 (可选, banner 不显示除非 !isEn 中文失败)
  final String author;          // 作者 (e.g. "苏轼", "Marcus Aurelius")
  final String? authorEn;       // 英文作者 (某些双语版用)
  final String? source;         // 出处 (e.g. "定风波", "Meditations")
  final DateTime createdAt;     // 入库/抓取时间 (用来: 收藏卡展示, 时间线)

  const Quote({
    required this.text,
    required this.author,
    this.textEn,
    this.authorEn,
    this.source,
    required this.createdAt,
  });

  // LLM 给 JSON 字符串时尝试解析
  factory Quote.fromLlmJson(String raw, {required DateTime now}) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw.trim());
    if (match == null) {
      // fallback: 整 raw 当 text
      return Quote(
        text: raw.trim(),
        author: '',
        createdAt: now,
      );
    }
    final body = match.group(0)!;
    String get(String key) {
      final m = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(body);
      if (m != null) return m.group(1)!.trim();
      // 单引号容错
      final m2 = RegExp("'$key'\\s*:\\s*'([^']*)'").firstMatch(body);
      return m2?.group(1)?.trim() ?? '';
    }
    final text = get('text');
    final author = get('author');
    if (text.isEmpty) {
      return Quote(text: raw.trim(), author: '', createdAt: now);
    }
    return Quote(
      text: text,
      author: author.isEmpty ? '' : author,
      source: get('source').isEmpty ? null : get('source'),
      textEn: get('textEn').isEmpty ? null : get('textEn'),
      authorEn: get('authorEn').isEmpty ? null : get('authorEn'),
      createdAt: now,
    );
  }

  // to JSON for SharedPreferences 序列化 (放进 quote_<hash> id 之前先转换)
  Map<String, dynamic> toJson() => {
        'text': text,
        'textEn': textEn,
        'author': author,
        'authorEn': authorEn,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Quote.fromJson(Map<String, dynamic> m) => Quote(
        text: m['text'] ?? '',
        author: m['author'] ?? '',
        textEn: m['textEn'],
        authorEn: m['authorEn'],
        source: m['source'],
        createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
      );
}
