import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// 6/7 步骤 2：本地历史记录（SharedPreferences）
/// 宪法 §1.1 兼容：只在用户设备本地，不上传、不持久化到服务器
class HistoryService {
  static final HistoryService instance = HistoryService._();
  HistoryService._();

  static const String _key = 'read_history';
  static const int _maxItems = 50;

  Future<List<HistoryItem>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(ContentItem item) async {
    final current = await getAll();
    // 去重（同 id 的删旧的，新的加到最前）
    current.removeWhere((h) => h.id == item.id && item.id.isNotEmpty);
    current.insert(
      0,
      HistoryItem(
        id: item.id,
        title: item.title,
        source: item.source,
        sourceTypeName: item.sourceType.name,
        contentTypeName: item.contentType.name,
        priceTypeName: item.priceType.name,
        priceNote: item.priceNote,
        duration: item.duration,
        description: item.description,
        imageUrl: item.imageUrl,
        audioUrl: item.audioUrl,
        externalUrl: item.externalUrl,
        videoId: item.videoId,
        videoPlatformName: item.videoPlatform?.name,
        readAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (current.length > _maxItems) current.removeRange(_maxItems, current.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 6/8 修复：单条删除（只要 id 匹配的就刷掉）
  /// 不重写整表 = 不动其他条
  Future<void> removeById(String id) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await getAll();
    final next = current.where((h) => h.id != id).toList();
    if (next.length == current.length) return; // 没变化就不写
    if (next.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(
        _key,
        jsonEncode(next.map((e) => e.toJson()).toList()),
      );
    }
  }
}

class HistoryItem {
  final String id;
  final String title;
  final String source;
  final String sourceTypeName;
  final String contentTypeName;
  final String priceTypeName;
  final String? priceNote;
  final String duration;
  final String? description;
  final String? imageUrl;
  final String? audioUrl;
  final String? externalUrl;
  final String? videoId;
  final String? videoPlatformName;
  final int readAt;

  const HistoryItem({
    required this.id,
    required this.title,
    required this.source,
    required this.sourceTypeName,
    required this.contentTypeName,
    required this.priceTypeName,
    this.priceNote,
    required this.duration,
    this.description,
    this.imageUrl,
    this.audioUrl,
    this.externalUrl,
    this.videoId,
    this.videoPlatformName,
    required this.readAt,
  });

  /// 还原为 ContentItem 供再次打开
  ContentItem toContentItem() {
    return ContentItem(
      id: id,
      title: title,
      source: source,
      sourceType: ContentSource.values.firstWhere(
        (s) => s.name == sourceTypeName,
        orElse: () => ContentSource.ximalaya,
      ),
      contentType: ContentType.values.firstWhere(
        (c) => c.name == contentTypeName,
        orElse: () => ContentType.article,
      ),
      priceType: ContentPriceType.values.firstWhere(
        (p) => p.name == priceTypeName,
        orElse: () => ContentPriceType.free,
      ),
      priceNote: priceNote,
      duration: duration,
      description: description ?? '',
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      externalUrl: externalUrl,
      videoId: videoId,
      videoPlatform: videoPlatformName != null
          ? VideoPlatform.values.firstWhere(
              (v) => v.name == videoPlatformName,
              orElse: () => VideoPlatform.youtube,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'sourceTypeName': sourceTypeName,
        'contentTypeName': contentTypeName,
        'priceTypeName': priceTypeName,
        'priceNote': priceNote,
        'duration': duration,
        'description': description,
        'imageUrl': imageUrl,
        'audioUrl': audioUrl,
        'externalUrl': externalUrl,
        'videoId': videoId,
        'videoPlatformName': videoPlatformName,
        'readAt': readAt,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        source: json['source'] ?? '',
        sourceTypeName: json['sourceTypeName'] ?? 'ximalaya',
        contentTypeName: json['contentTypeName'] ?? 'article',
        priceTypeName: json['priceTypeName'] ?? 'free',
        priceNote: json['priceNote'],
        duration: json['duration'] ?? '',
        description: json['description'],
        imageUrl: json['imageUrl'],
        audioUrl: json['audioUrl'],
        externalUrl: json['externalUrl'],
        videoId: json['videoId'],
        videoPlatformName: json['videoPlatformName'],
        readAt: json['readAt'] ?? 0,
      );
}
