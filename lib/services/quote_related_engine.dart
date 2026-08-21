// lib/services/quote_related_engine.dart
// 7/15 16:56 Q2 Brien 反馈: 名言延伸内容强关联
// A 路径: Hero 详情页底部 / B 路径: banner + Hero 问 AI sheet 都用

import '../models/models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/quote.dart';
import 'content_aggregator.dart';
import 'llm_service.dart';

// 关联搜索结果 (单条命中)
class RelatedHit {
  final String title;       // 短标题 (e.g. "苏轼《定风波》原文注释")
  final String source;      // 内容来源 (e.g. "知乎" / "搜索结果")
  final String? externalUrl; // 跳转链接 (无 = 走搜索 page)
  final int score;          // 关联度 (大 = 越相关)
  final bool fromLlm;       // 是 LLM 补的还是桶里搜的

  RelatedHit({
    required this.title,
    required this.source,
    this.externalUrl,
    required this.score,
    this.fromLlm = false,
  });
}

class QuoteRelatedEngine {
  static final ContentAggregator _aggregator = ContentAggregator();

  /// 7/15 主入口: 给一条 quote + 当前 userType, 返回 top N 关联条目
  /// 算法:
  ///   1. 从 24 桶搜 + author/source/keyword 权重打分
  ///   2. LLM 补 1-3 条 (30s 兌底, 失败就只用桶的结果)
  ///   3. 合并按 score 排, 取 top N
  static Future<List<RelatedHit>> findRelated({
    required Quote quote,
    required UserType userType,
    required Scene scene,
    required bool isEn,
    int limit = 6,
  }) async {
    final hits = <RelatedHit>[];
    final seen = <String>{};

    // 阶段 1: 桶搜 (ContentAggregator.searchContent 自动跑 24 桶)
    final query = _buildQuery(quote);
    if (query.isNotEmpty) {
      try {
        final fromBucket = await _aggregator.searchContent(query);
        for (final c in fromBucket) {
          final key = c.title;
          if (seen.contains(key)) continue;
          int bucketScore = _bucketScore(quote, c);
          if (bucketScore <= 0) continue;
          hits.add(RelatedHit(
            title: c.title,
            source: c.source,
            externalUrl: c.externalUrl,
            score: bucketScore,
          ));
          seen.add(key);
        }
      } catch (e) { debugPrint('[quote_related_engine] err'); /* 桶搜失败就跳过 */ }
    }

    // 阶段 2: LLM 补 1-3 条 (短标题列表, JSON 解析)
    final llmHits = await _llmSupplement(quote, userType, scene, isEn);
    for (final h in llmHits) {
      if (seen.contains(h.title)) continue;
      hits.add(h);
      seen.add(h.title);
    }

    // 阶段 3: 按 score 降序, 取 top N
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  // 7/15 helper: query 拼接 (author + source + 标题简化的 1-2 字)
  static String _buildQuery(Quote q) {
    final parts = <String>[];
    if (q.author.isNotEmpty) parts.add(q.author);
    if (q.source != null && q.source!.isNotEmpty) {
      final s = q.source!.replaceAll(RegExp(r'[^\\u4e00-\\u9fff\\w\\s]'), ' ').trim();
      final firstTwo = s.split(' ').first;
      if (firstTwo.length >= 2 && firstTwo.length <= 6) parts.add(firstTwo);
    }
    if (q.text.isNotEmpty) {
      final first4 = q.text.length > 4 ? q.text.substring(0, 4) : q.text;
      parts.add(first4);
    }
    return parts.join(' ');
  }

  // 7/15 helper: 对一条 桶里搜到的 ContentItem 打分
  static int _bucketScore(Quote q, ContentItem c) {
    int score = 0;
    // 同作者 (+50)
    if (q.author.isNotEmpty &&
        (c.source.toLowerCase().contains(q.author.toLowerCase()) ||
            c.title.toLowerCase().contains(q.author.toLowerCase()))) {
      score += 50;
    }
    // 标题/描述 出现关键词 (+30)
    final keywords = <String>[];
    if (q.author.isNotEmpty) keywords.add(q.author);
    if (q.source != null) keywords.add(q.source!);
    final queryWords = q.text.split(RegExp(r'\\s+')).where((w) => w.length >= 2).take(3);
    keywords.addAll(queryWords);
    bool kwHit = false;
    for (final k in keywords) {
      if (c.title.toLowerCase().contains(k.toLowerCase()) ||
          (c.description.toLowerCase().contains(k.toLowerCase()))) {
        kwHit = true;
        break;
      }
    }
    if (kwHit) score += 30;
    // userType 弱匹配 (+5)
    score += 5;
    return score;
  }

  // 7/15 helper: LLM 补 3 条短标题 (30s 兌底)
  static Future<List<RelatedHit>> _llmSupplement(
    Quote q, UserType userType, Scene scene, bool isEn,
  ) async {
    try {
      final prompt = isEn
          ? 'Quote: "${q.text}" by ${q.author} (${q.source ?? "—"})\n'
              'User context: ${userType.name} in ${scene.name}.\n\n'
              'Recommend 5 short article titles (in English, each max 12 words) that might be related to this quote.\n'
              'Mix types: 2 articles, 2 books, 1 modern essay. Return ONLY JSON: {"hits": [{"title": "...", "reason": "..."}, ...]}'
          : '名言: "${q.text}" by ${q.author} (${q.source ?? "—"})\n'
              '用户角色: ${userType.name}, 场景: ${scene.name}。\n\n'
              '推荐 5 个跟这句名言相关的短标题 (中文, 每个不超过 18 字), 用户可能想进一步阅读的。\n'
              '混合类型: 2 篇文章、2 本书、1 个现代短篇。仅返回 JSON: {"hits": [{"title": "...", "reason": "..."}, ...]}';
      final raw = await LlmService.generateRaw(prompt, isEn: isEn)
          .timeout(const Duration(seconds: 30), onTimeout: () => '');
      if (raw.isEmpty) return [];
      final results = <RelatedHit>[];
      final m = RegExp(r'\{[\\s\\S]*\}').firstMatch(raw);
      if (m == null) return [];
      final body = m.group(0)!;
      final entryRe = RegExp(r'"title"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"');
      for (final em in entryRe.allMatches(body)) {
        var t = em.group(1)!;
        t = t.replaceAll(r'\\"', '"').replaceAll(r'\\n', '\\n');
        if (t.isEmpty) continue;
        results.add(RelatedHit(
          title: t,
          source: isEn ? 'AI' : 'AI 推荐',
          score: 80, // LLM 补的优先级较高 (它了解语义关联)
          fromLlm: true,
        ));
      }
      return results;
    } catch (e) {
      return [];
    }
  }
}
