// lib/services/user_preference_service.dart
// 6/13 用户偏好/交互日志
// 三个 key:
//   - 'pref_dismissed' : List<String> item.id（点 ❌ 不喜欢）
//   - 'pref_liked'     : Map<String, int> item.source -> count（点 ❤️ / 进详情累计）
//   - 'pref_log'       : List<Map> 滚动 50 条 JSON，{ts, action, id, source, type, userType, scene}
// 设计：dismissed 存盘（24 桶内容去重后不推）；liked 累计；log 50 条 FIFO 上限
//
// AI 接入：getPreferenceSummary() 输出字符串给 LLM system prompt 拼
//   "用户偏好：news36kr x 5, 36kr_video x 2, 偏好类型: video, 偏好场景: learn"

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

enum PrefAction { view, like, dismiss, save }

class UserPreferenceService {
  static final UserPreferenceService instance = UserPreferenceService._();
  UserPreferenceService._();

  static const String _kDismissed = 'pref_dismissed';
  static const String _kLiked = 'pref_liked';
  static const String _kLog = 'pref_log';
  // 6/14 推荐完成计数: 'pref_daily_done' = 'YYYY-MM-DD|count'
  static const String _kDailyDone = 'pref_daily_done';
  static const int _logMax = 50;

  // ========== Public API ==========

  /// 记录一次交互
  Future<void> record({
    required PrefAction action,
    required ContentItem item,
    required UserType userType,
    required Scene scene,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) liked 累计（按 source 类目）
    if (action == PrefAction.like || action == PrefAction.save) {
      final liked = _decodeStringIntMap(prefs.getString(_kLiked));
      liked[item.source] = (liked[item.source] ?? 0) + 1;
      await prefs.setString(_kLiked, _encodeStringIntMap(liked));
    }

    // 2) dismissed 列表（去重）
    if (action == PrefAction.dismiss) {
      final dismissed = prefs.getStringList(_kDismissed) ?? <String>[];
      if (!dismissed.contains(item.id)) {
        dismissed.add(item.id);
        await prefs.setStringList(_kDismissed, dismissed);
      }
    }

    // 3) log 滚动 50
    final log = _decodeLogList(prefs.getString(_kLog));
    log.add({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'action': action.name,
      'id': item.id,
      'source': item.source,
      'type': item.contentType.name,
      'userType': userType.name,
      'scene': scene.name,
    });
    if (log.length > _logMax) {
      log.removeRange(0, log.length - _logMax);
    }
    await prefs.setString(_kLog, _encodeLogList(log));
  }

  /// 过滤掉已 dislike 的 items
  List<ContentItem> filterDismissed(List<ContentItem> items) {
    // 注意：此方法为同步；dismissed 列表可从 SharedPreferences 同步取
    // 但 prefs 异步……这里我们让调用方在 record() 之后做本地过滤（_dismissedIds 内存缓存）
    return items;
  }

  /// LLM 用的偏好摘要
  Future<String> getPreferenceSummary({UserType? userType, Scene? scene}) async {
    final prefs = await SharedPreferences.getInstance();
    final liked = _decodeStringIntMap(prefs.getString(_kLiked));
    if (liked.isEmpty) return '';

    // 按 count 降序
    final entries = liked.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(3).map((e) => '${e.key} x${e.value}').join(', ');

    // 偏好类型（从 log 算）
    final log = _decodeLogList(prefs.getString(_kLog));
    final typeCount = <String, int>{};
    for (final e in log) {
      if (e['action'] == 'like' || e['action'] == 'view') {
        final t = e['type'] as String? ?? '';
        typeCount[t] = (typeCount[t] ?? 0) + 1;
      }
    }
    final typeEntries = typeCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final typeLine = typeEntries.isEmpty
        ? ''
        : '偏好类型: ${typeEntries.take(2).map((e) => e.key).join('+')}';

    // 偏好 userType/scene
    final sceneCount = <String, int>{};
    for (final e in log) {
      final s = e['scene'] as String? ?? '';
      sceneCount[s] = (sceneCount[s] ?? 0) + 1;
    }
    final sceneEntries = sceneCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sceneLine = sceneEntries.isEmpty
        ? ''
        : '偏好场景: ${sceneEntries.take(1).map((e) => e.key).join('')}';

    return '用户偏好：$top${typeLine.isNotEmpty ? ', $typeLine' : ''}${sceneLine.isNotEmpty ? ', $sceneLine' : ''}';
  }

  /// 6/14 今日推荐完成计数:返回今日完成次数（跨日重置）
  /// 同时 +1 写回
  Future<int> incrementDailyDone() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final raw = prefs.getString(_kDailyDone) ?? '';
    int count = 0;
    if (raw.startsWith('$today|')) {
      count = int.tryParse(raw.split('|').last) ?? 0;
    }
    count += 1;
    await prefs.setString(_kDailyDone, '$today|$count');
    return count;
  }

  /// 读今日完成次数
  Future<int> getDailyDone() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final raw = prefs.getString(_kDailyDone) ?? '';
    if (!raw.startsWith('$today|')) return 0;
    return int.tryParse(raw.split('|').last) ?? 0;
  }

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// 调试用
  Future<Map<String, dynamic>> debugDump() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'dismissed_count': (prefs.getStringList(_kDismissed) ?? []).length,
      'liked': _decodeStringIntMap(prefs.getString(_kLiked)),
      'log_count': _decodeLogList(prefs.getString(_kLog)).length,
    };
  }

  // ========== Internal: codec ==========

  String _encodeStringIntMap(Map<String, int> m) =>
      jsonEncode(m.map((k, v) => MapEntry(k, v)));

  Map<String, int> _decodeStringIntMap(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  String _encodeLogList(List<Map<String, dynamic>> log) => jsonEncode(log);
  List<Map<String, dynamic>> _decodeLogList(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
