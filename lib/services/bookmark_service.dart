// 8/28 P53-2 沿 SOUL #188 透明: BookmarkService 单条目收藏
//   真凶: 之前只支持平台/类目订阅, 单篇文章无法收藏
//     → 用户看到喜欢的文章无法保存
//   修: 持久化 List<BookmarkEntry> (id + contentSnapshot + addedAt)
//     通过 SharedPreferences 存
//   SOUL #6 能跑起来 > 等完美答案: 简化数据结构 (id + title + source + url)
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/models.dart';

/// 8/28 P53-2: 收藏条目 (id + title + source + url + 摘要)
class BookmarkEntry {
  final String id; // ContentItem.id 或 URL hash
  final String title;
  final String source;
  final String url;
  final String description;
  final DateTime addedAt;

  BookmarkEntry({
    required this.id,
    required this.title,
    required this.source,
    required this.url,
    required this.description,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'url': url,
        'description': description,
        'addedAt': addedAt.toIso8601String(),
      };

  factory BookmarkEntry.fromJson(Map<String, dynamic> j) => BookmarkEntry(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        source: j['source'] as String? ?? '',
        url: j['url'] as String? ?? '',
        description: j['description'] as String? ?? '',
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
      );

  /// 从 ContentItem 创建 (沿 SOUL #169 不撒谎, snapshot 真实数据)
  factory BookmarkEntry.fromContentItem(ContentItem item) {
    final addedAt = DateTime.now();
    return BookmarkEntry(
      id: item.id,
      title: item.title,
      source: item.source,
      url: item.externalUrl ?? '',
      description: item.description,
      addedAt: addedAt,
    );
  }
}

class BookmarkService {
  static final BookmarkService instance = BookmarkService._();
  BookmarkService._();

  static const String _key = 'bookmarked_items';

  // 8/28 P53-2: 内存 cache (避免每次 SharedPreferences read)
  List<BookmarkEntry>? _cache;
  final List<void Function()> _listeners = [];

  /// 8/28 P53-2: 加 listener (UI 状态同步)
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final l in _listeners) {
      try {
        l();
      } catch (e) {
        debugPrint('[bookmark] listener err: $e');
      }
    }
  }

  Future<List<BookmarkEntry>> getAll() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final entries = list.map((s) {
      try {
        // 8/28 P53-2: 用 Map 序列化 (避免 jsonEncode/decode 复杂性)
        // 简单格式: id|title|source|url|description|iso8601
        final parts = s.split('|||');
        if (parts.length < 6) return null;
        return BookmarkEntry(
          id: parts[0],
          title: parts[1],
          source: parts[2],
          url: parts[3],
          description: parts[4],
          addedAt: DateTime.tryParse(parts[5]) ?? DateTime.now(),
        );
      } catch (e) {
        debugPrint('[bookmark] parse err: $e');
        return null;
      }
    }).whereType<BookmarkEntry>().toList();
    _cache = entries;
    return entries;
  }

  /// 8/28 P53-2: 加收藏 (沿 SOUL #103 治好不抢注意力)
  Future<bool> add(ContentItem item) async {
    final entries = await getAll();
    // dedup by id
    if (entries.any((e) => e.id == item.id)) {
      debugPrint('[bookmark] ${item.id} 已收藏, skip');
      return false;
    }
    final entry = BookmarkEntry.fromContentItem(item);
    entries.add(entry);
    await _save(entries);
    _notify();
    return true;
  }

  /// 8/28 P53-2: 删收藏
  Future<bool> remove(String id) async {
    final entries = await getAll();
    final before = entries.length;
    entries.removeWhere((e) => e.id == id);
    if (entries.length == before) return false;
    await _save(entries);
    _notify();
    return true;
  }

  /// 8/28 P53-2: toggle (UI 按钮)
  Future<bool> toggle(ContentItem item) async {
    final entries = await getAll();
    if (entries.any((e) => e.id == item.id)) {
      await remove(item.id);
      return false; // 取消
    }
    await add(item);
    return true; // 收藏
  }

  /// 8/28 P53-2: 是否已收藏
  Future<bool> isBookmarked(String id) async {
    final entries = await getAll();
    return entries.any((e) => e.id == id);
  }

  /// 8/28 P53-2: 总数 (UI 显示)
  Future<int> count() async {
    final entries = await getAll();
    return entries.length;
  }

  /// 8/28 P53-2: 按时间倒序 (最新在前)
  Future<List<BookmarkEntry>> getRecent({int limit = 50}) async {
    final entries = await getAll();
    entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return entries.take(limit).toList();
  }

  /// 8/28 P53-2: 清空所有 (用户主动清空收藏)
  Future<void> clear() async {
    _cache = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _notify();
  }

  Future<void> _save(List<BookmarkEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final list = entries.map((e) => '${e.id}|||${e.title}|||${e.source}|||${e.url}|||${e.description}|||${e.addedAt.toIso8601String()}').toList();
    await prefs.setStringList(_key, list);
    _cache = entries;
  }

  // 8/28 P53-3 沿 SOUL #189 智: 静态 stats counter (沿 P46-3 模式)
  // ignore: prefer_final_fields
  static int _addCount = 0;
  // ignore: prefer_final_fields
  static int _removeCount = 0;

  static int get statsAddCount => _addCount;
  static int get statsRemoveCount => _removeCount;
}