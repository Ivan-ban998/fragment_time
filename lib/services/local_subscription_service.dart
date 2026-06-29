import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

// 6/24 v14: extends ChangeNotifier — subscribe/unsubscribe 通知 listeners
// 让 MySubscriptionsScreen 用 context.watch 自动 rebuild
class LocalSubscriptionService extends ChangeNotifier {
  static final LocalSubscriptionService instance = LocalSubscriptionService._();
  LocalSubscriptionService._();

  static const String _key = 'subscribed_content';

  Future<List<ContentItem>> getSubscribedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((json) => _itemFromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> subscribe(ContentItem item) async {
    final items = await getSubscribedItems();
    // 6/29 15:33 Brien 反馈: "只能收藏一个名言" — 真凶: 去重用 title+source, 但名言 title 都是
    // "AI 6月29日名言" 格式 (同一天), 不同名言重复被拒, 只有第一个能入 list
    // 修: 去重用 item.id (id = quote_<text hash>, 不同名言不同 id)
    if (!items.any((i) => i.id == item.id)) {
      items.add(item);
      await _save(items);
    }
  }

  // 6/9 4：离线收藏包 — 导出 / 导入
  Future<String> exportPack() async {
    final items = await getSubscribedItems();
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'items': items.map((i) => i.toJson()).toList(),
    };
    return jsonEncode(data);
  }

  Future<int> importPack(String json) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      int imported = 0;
      for (final m in items) {
        final item = ContentItem.fromJson(m);
        await subscribe(item);
        imported += 1;
      }
      return imported;
    } catch (e) {
      return 0;
    }
  }

  Future<void> unsubscribe(ContentItem item) async {
    final items = await getSubscribedItems();
    items.removeWhere((i) => i.title == item.title && i.source == item.source);
    await _save(items);
  }

  // 6/9 Sofa 启发：进度更新
  Future<void> updateProgress(ContentItem item, int progress) async {
    final items = await getSubscribedItems();
    final idx = items.indexWhere(
      (i) => i.title == item.title && i.source == item.source,
    );
    if (idx < 0) return;
    final old = items[idx];
    final updated = ContentItem(
      id: old.id,
      title: old.title,
      description: old.description,
      duration: old.duration,
      source: old.source,
      imageUrl: old.imageUrl,
      audioUrl: old.audioUrl,
      externalUrl: old.externalUrl,
      sourceType: old.sourceType,
      contentType: old.contentType,
      videoId: old.videoId,
      videoPlatform: old.videoPlatform,
      progress: progress.clamp(0, 100),
      lastReadAt: DateTime.now(),
      priceType: old.priceType,
      priceNote: old.priceNote,
    );
    items[idx] = updated;
    await _save(items);
  }

  // 取最近 1-3 条未完成 (0 < progress < 100)
  Future<List<ContentItem>> getInProgress({int limit = 3}) async {
    final items = await getSubscribedItems();
    final inProg = items
        .where((i) => i.progress > 0 && i.progress < 100)
        .toList()
      ..sort((a, b) {
        final ad = a.lastReadAt ?? DateTime(2000);
        final bd = b.lastReadAt ?? DateTime(2000);
        return bd.compareTo(ad); // 新的在前
      });
    return inProg.take(limit).toList();
  }

  Future<bool> isSubscribed(ContentItem item) async {
    final items = await getSubscribedItems();
    return items.any((i) => i.title == item.title && i.source == item.source);
  }

  Future<void> _save(List<ContentItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = items.map((item) => _itemToJson(item)).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
    // 6/24 v14: 通知 listeners (MySubscriptionsScreen 自动 rebuild)
    notifyListeners();
  }

  Map<String, dynamic> _itemToJson(ContentItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'description': item.description,
      'duration': item.duration,
      'source': item.source,
      'imageUrl': item.imageUrl,
      'audioUrl': item.audioUrl,
      'externalUrl': item.externalUrl,
      'sourceType': item.sourceType.name,
      'priceType': item.priceType.name,
      'priceNote': item.priceNote,
      'contentType': item.contentType.name,
      'videoId': item.videoId,
      'videoPlatform': item.videoPlatform?.name,
      'progress': item.progress,
      'lastReadAt': item.lastReadAt?.toIso8601String(),
    };
  }

  ContentItem _itemFromJson(Map<String, dynamic> json) {
    return ContentItem(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      duration: (json['duration'] ?? '') as String,
      source: (json['source'] ?? '') as String,
      imageUrl: json['imageUrl'] as String?,
      audioUrl: json['audioUrl'] as String?,
      externalUrl: json['externalUrl'] as String?,
      sourceType: ContentSource.values.firstWhere((s) => s.name == json['sourceType'], orElse: () => ContentSource.ximalaya),
      priceType: ContentPriceType.values.firstWhere((p) => p.name == json['priceType'], orElse: () => ContentPriceType.free),
      priceNote: json['priceNote'] as String?,
      contentType: ContentType.values.firstWhere((c) => c.name == json['contentType'], orElse: () => ContentType.article),
      videoId: json['videoId'] as String?,
      videoPlatform: json['videoPlatform'] != null
          ? VideoPlatform.values.firstWhere(
              (v) => v.name == json['videoPlatform'],
              orElse: () => VideoPlatform.youtube,
            )
          : null,
      progress: (json['progress'] ?? 0) as int,
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.tryParse(json['lastReadAt'] as String)
          : null,
    );
  }

  // 6/9 场景包：用户选 N 条 → “今天包” / “通勤包” 一键调
  static const String _packKey = 'scene_pack_v1';
  String? _packName;
  List<String> _packIds = [];

  Future<void> setPack(String name, List<ContentItem> items) async {
    _packName = name;
    _packIds = items.map((i) => i.id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_packKey}_name', name);
    await prefs.setStringList('${_packKey}_ids', _packIds);
  }

  Future<({String? name, List<String> ids})> getPack() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      name: prefs.getString('${_packKey}_name'),
      ids: prefs.getStringList('${_packKey}_ids') ?? const [],
    );
  }

  Future<void> clearPack() async {
    _packName = null;
    _packIds = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_packKey}_name');
    await prefs.remove('${_packKey}_ids');
  }
}