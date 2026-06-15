// lib/services/analytics_service.dart
// 6/8 加：自用数据看板
// 宪法 §1.1 兼容：只存本地 SharedPreferences，不上传任何服务器
// 看 Brien 自己用啥 → 24 桶 6 角色偏好 / TTS 收听 / 视频点击 / 搜索

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  static const String _key = 'analytics_events';
  // 最多保留 1000 条事件（防 SharedPreferences 撑爆）
  static const int _maxEvents = 1000;

  // 6 类事件 + 自定义 props
  static const String EVT_APP_OPEN = 'app_open';
  static const String EVT_USER_TYPE_SELECT = 'user_type_select';
  static const String EVT_SCENE_SELECT = 'scene_select';
  static const String EVT_ITEM_OPEN = 'item_open';
  static const String EVT_TTS_PLAY = 'tts_play';
  static const String EVT_VIDEO_PLAY = 'video_play';
  static const String EVT_VIDEO_OPEN_EXTERNAL = 'video_open_external';
  static const String EVT_SEARCH = 'search';
  static const String EVT_SAVE = 'save';
  static const String EVT_HISTORY_DELETE = 'history_delete';

  /// 记录一条事件
  /// props = {'key': 'value'} 任意字符串字典
  Future<void> track(String event, {Map<String, String>? props}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final entry = jsonEncode({
      't': DateTime.now().millisecondsSinceEpoch,
      'e': event,
      if (props != null) 'p': props,
    });
    list.add(entry);
    if (list.length > _maxEvents) {
      list.removeRange(0, list.length - _maxEvents);
    }
    await prefs.setStringList(_key, list);
  }

  /// 读所有事件
  Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list
        .map((s) {
          try {
            return jsonDecode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  /// 清空（调试用）
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 6/8 自用看板：聚合统计
  Future<Map<String, dynamic>> summary() async {
    final events = await getAll();
    final now = DateTime.now().millisecondsSinceEpoch;
    final oneDayAgo = now - 24 * 3600 * 1000;
    final oneWeekAgo = now - 7 * 24 * 3600 * 1000;

    int appOpens = 0, appOpens1d = 0, appOpens7d = 0;
    final userTypePick = <String, int>{};
    final scenePick = <String, int>{};
    final itemOpens = <String, int>{};
    int ttsPlays = 0, videoPlays = 0, videoExtClicks = 0, searches = 0;
    final searchTerms = <String, int>{};
    final savesByType = <String, int>{};
    int historyDeletes = 0;

    for (final e in events) {
      final t = (e['t'] as num?)?.toInt() ?? 0;
      final name = e['e'] as String? ?? '';
      final p = (e['p'] as Map?)?.cast<String, String>() ?? {};

      if (name == EVT_APP_OPEN) {
        appOpens++;
        if (t > oneDayAgo) appOpens1d++;
        if (t > oneWeekAgo) appOpens7d++;
      } else if (name == EVT_USER_TYPE_SELECT) {
        final ut = p['userType'] ?? '';
        if (ut.isNotEmpty) userTypePick[ut] = (userTypePick[ut] ?? 0) + 1;
      } else if (name == EVT_SCENE_SELECT) {
        final sc = p['scene'] ?? '';
        if (sc.isNotEmpty) scenePick[sc] = (scenePick[sc] ?? 0) + 1;
      } else if (name == EVT_ITEM_OPEN) {
        final id = p['id'] ?? '';
        if (id.isNotEmpty) itemOpens[id] = (itemOpens[id] ?? 0) + 1;
      } else if (name == EVT_TTS_PLAY) {
        ttsPlays++;
      } else if (name == EVT_VIDEO_PLAY) {
        videoPlays++;
      } else if (name == EVT_VIDEO_OPEN_EXTERNAL) {
        videoExtClicks++;
      } else if (name == EVT_SEARCH) {
        searches++;
        final q = p['q'] ?? '';
        if (q.isNotEmpty) searchTerms[q] = (searchTerms[q] ?? 0) + 1;
      } else if (name == EVT_SAVE) {
        final t = p['type'] ?? '';
        if (t.isNotEmpty) savesByType[t] = (savesByType[t] ?? 0) + 1;
      } else if (name == EVT_HISTORY_DELETE) {
        historyDeletes++;
      }
    }

    // 24 桶偏好（userType × scene 组合）
    final bucketPick = <String, int>{};
    for (final e in events) {
      if (e['e'] == EVT_SCENE_SELECT) {
        final p = (e['p'] as Map?)?.cast<String, String>() ?? {};
        final ut = p['userType'] ?? '';
        final sc = p['scene'] ?? '';
        if (ut.isNotEmpty && sc.isNotEmpty) {
          final k = '$ut×$sc';
          bucketPick[k] = (bucketPick[k] ?? 0) + 1;
        }
      }
    }

    // 排序 helper
    List<MapEntry<String, int>> sortDesc(Map<String, int> m) {
      final l = m.entries.toList();
      l.sort((a, b) => b.value.compareTo(a.value));
      return l;
    }

    return {
      'appOpens': appOpens,
      'appOpens1d': appOpens1d,
      'appOpens7d': appOpens7d,
      'userTypePick': sortDesc(userTypePick).take(6).toList(),
      'scenePick': sortDesc(scenePick).take(4).toList(),
      'bucketPick': sortDesc(bucketPick).take(8).toList(),
      'itemOpens': sortDesc(itemOpens).take(10).toList(),
      'ttsPlays': ttsPlays,
      'videoPlays': videoPlays,
      'videoExtClicks': videoExtClicks,
      'searches': searches,
      'searchTerms': sortDesc(searchTerms).take(10).toList(),
      'savesByType': sortDesc(savesByType).toList(),
      'historyDeletes': historyDeletes,
      'totalEvents': events.length,
    };
  }
}
