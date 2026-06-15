import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'web_host_stub.dart'
    if (dart.library.html) 'web_host_web.dart' as webhost;
import 'history_service.dart';

/// 6/12 周回顾：基于 history 算 7 天内的统计 + LLM 总结
class WeeklyRecapService {
  static final WeeklyRecapService instance = WeeklyRecapService._();
  WeeklyRecapService._();

  /// 算最近 7 天的历史，分类汇总
  Future<WeeklyRecap> generate({bool useLLM = true}) async {
    final all = await HistoryService.instance.getAll();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));

    final recent = all.where((h) {
      final t = DateTime.fromMillisecondsSinceEpoch(h.readAt);
      return t.isAfter(cutoff);
    }).toList();

    if (recent.isEmpty) {
      return WeeklyRecap(
        total: 0,
        perSource: const {},
        perType: const {},
        perDay: const {},
        topTitles: const [],
        daysActive: 0,
        summary: '本周还没读任何内容。打开首页挑一条开始吧。',
        llmUsed: false,
      );
    }

    final perSource = <String, int>{};
    final perType = <String, int>{};
    final perDay = <String, int>{};
    final daysActive = <String>{};

    for (final h in recent) {
      perSource[h.source] = (perSource[h.source] ?? 0) + 1;
      perType[h.contentTypeName] = (perType[h.contentTypeName] ?? 0) + 1;
      final d = DateTime.fromMillisecondsSinceEpoch(h.readAt);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      perDay[key] = (perDay[key] ?? 0) + 1;
      daysActive.add(key);
    }

    final topTitles = recent.take(5).map((h) => h.title).toList();
    final topSource = _topEntry(perSource);
    final topType = _topEntry(perType);

    String summary;
    bool llmUsed = false;
    if (useLLM) {
      try {
        final prompt = _buildPrompt(
          total: recent.length,
          topSource: topSource,
          topType: topType,
          daysActive: daysActive.length,
          topTitles: topTitles,
        );
        final llm = await _callOllama(prompt);
        if (llm != null && llm.isNotEmpty) {
          summary = llm;
          llmUsed = true;
        } else {
          summary = _fallbackSummary(recent.length, topSource, topType, daysActive.length);
        }
      } catch (_) {
        summary = _fallbackSummary(recent.length, topSource, topType, daysActive.length);
      }
    } else {
      summary = _fallbackSummary(recent.length, topSource, topType, daysActive.length);
    }

    return WeeklyRecap(
      total: recent.length,
      perSource: perSource,
      perType: perType,
      perDay: perDay,
      topTitles: topTitles,
      daysActive: daysActive.length,
      summary: summary,
      llmUsed: llmUsed,
    );
  }

  MapEntry<String, int>? _topEntry(Map<String, int> m) {
    if (m.isEmpty) return null;
    final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first;
  }

  String _buildPrompt({
    required int total,
    required MapEntry<String, int>? topSource,
    required MapEntry<String, int>? topType,
    required int daysActive,
    required List<String> topTitles,
  }) {
    return '''你是 fragment_time 的 AI 私教。给用户写一段 60 字以内的本周阅读回顾，要求：
1. 提数字（读了 X 条 / 看了 X 天）
2. 提最多看的来源 / 类型
3. 给一句具体可执行的"下周建议"
4. 不说客套话，不超过 60 字

数据：
- 总条数：$total
- 活跃天数：$daysActive / 7
- 最多来源：${topSource?.key ?? '-'} (${topSource?.value ?? 0} 条)
- 最多类型：${topType?.key ?? '-'} (${topType?.value ?? 0} 条)
- 最近 5 个标题：${topTitles.join(' / ')}

只输出回顾正文。''';
  }

  /// 6/12: 直接调 Ollama（不走 LlmService 避免 userType/scene 强绑）
  /// 超时 8 秒；失败返回 null
  Future<String?> _callOllama(String prompt) async {
    String host;
    if (kIsWeb) {
      host = webhost.currentHostname();
    } else {
      host = '192.168.1.20';
    }
    final endpoint = 'http://$host:11434/api/chat';
    try {
      final resp = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': 'qwen2.5:7b',
              'stream': false,
              'messages': [
                {'role': 'system', 'content': '你是 fragment_time 的 AI 私教。'},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final msg = data['message'] as Map<String, dynamic>?;
      return msg?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _fallbackSummary(
    int total,
    MapEntry<String, int>? topSource,
    MapEntry<String, int>? topType,
    int daysActive,
  ) {
    final src = topSource?.key ?? '-';
    final type = topType?.key ?? '-';
    return '本周读了 $total 条，活跃 $daysActive 天。最常看 $src 的 $type。';
  }
}

class WeeklyRecap {
  final int total;
  final Map<String, int> perSource;
  final Map<String, int> perType;
  final Map<String, int> perDay;
  final List<String> topTitles;
  final int daysActive;
  final String summary;
  final bool llmUsed;

  const WeeklyRecap({
    required this.total,
    required this.perSource,
    required this.perType,
    required this.perDay,
    required this.topTitles,
    required this.daysActive,
    required this.summary,
    required this.llmUsed,
  });
}
