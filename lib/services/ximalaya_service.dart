// lib/services/ximalaya_service.dart
// 8/7 改 (沿 ROADMAP #D + SOUL #137 真凶): 喜马拉雅真接 (宪法 §1.1 严 — 仅 metadata + 跳原站)
// 真凶链:
//   - 之前 XimalayaService.search/albums 全返 [], 占位实现
//   - 8/7 查公开 API: 喜马拉雅专辑公开 RSS = https://www.ximalaya.com/album/{id}.xml
//     真返 RSS 2.0 + itunes namespace (元数据完整: title/description/duration/pubDate/enclosure)
//   - 搜索: 喜马拉雅搜索 API 不公开 JSON, 走 SPA HTML 撞宪法 §1.1 不允许爬
// 修法 (宪法 §1.1 严):
//   - 新增 getAlbumTracks(albumId) → 拿 metadata + 跳原站链接
//   - search 改为 按 albumId 列表遍历 (待 SearchScreen 沿用 8/5 沿 #115 关键词)
//   - 不缓存音频, 不缓存任何播放 URL (enclosure 仅展示, 实际听跳原站)
//
// 真接法 (沿 RSS 模式 #137):
//   - 客户端 fetch /rss?url=https://www.ximalaya.com/album/{id}.xml → ft_server.py 代理
//   - ft_server.py 需放行 .ximalaya.com (沿 #137 RSS 域白名单)
//   - XML 解析: rss/item/title/link/description/pubDate/enclosure[@url]

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/models.dart';

class XimalayaTrack {
  final String title;
  final String url; // 专辑页面 url (宪法 §1.1: 跳原站)
  final String description;
  final DateTime pubDate;
  final String audioUrl; // enclosure url (仅 metadata, 不缓存)
  final int durationSec; // 解析 itunes:duration
  final String albumTitle;

  XimalayaTrack({
    required this.title,
    required this.url,
    required this.description,
    required this.pubDate,
    required this.audioUrl,
    required this.durationSec,
    required this.albumTitle,
  });

  // 转 ContentItem 适配 24 桶
  ContentItem toContentItem() {
    return ContentItem(
      id: 'ximalaya_${url.hashCode.abs()}',
      title: title,
      description: description,
      source: '喜马拉雅',
      sourceType: ContentSource.ximalaya,
      contentType: ContentType.audio,
      duration: durationSec > 0 ? '${(durationSec ~/ 60).toString()}min' : '5min',
      externalUrl: url, // 跳原站
      priceType: ContentPriceType.free,
    );
  }
}

class XimalayaService {
  // 8/7 加: ft_server.py /rss 同源代理 (沿 #137 #171 模式)
  String _resolveAlbumUrl(int albumId) {
    if (kIsWeb) {
      return '/rss?url=${Uri.encodeComponent('https://www.ximalaya.com/album/$albumId.xml')}';
    }
    return 'https://www.ximalaya.com/album/$albumId.xml';
  }

  /// 8/7 加 (沿 ROADMAP #D): 真接 — 拿专辑 metadata + 跳原站
  /// 真撞 (沿 #137): 之前返 [], 占位实现. 8/7 改真接 fetch + XML 解析
  Future<List<XimalayaTrack>> getAlbumTracks(int albumId) async {
    try {
      final resp = await http
          .get(
            Uri.parse(_resolveAlbumUrl(albumId)),
            headers: const {
              'User-Agent': 'fragment_time/1.0 (NAS)',
              'Accept': 'application/rss+xml, application/xml;q=0.9, */*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return [];
      return _parse(resp.body);
    } catch (e) {
      // 8/7 加 (沿 SOUL #25 #26): 失败 log, 不返兜底假数据 (宪法 §1.1 严)
      debugPrint('[ximalaya] getAlbumTracks albumId=$albumId failed: $e');
      return [];
    }
  }

  /// 8/7 加: XML 解析 (RSS 2.0 + itunes namespace)
  List<XimalayaTrack> _parse(String body) {
    try {
      final doc = xml.XmlDocument.parse(body);
      final channel = doc.findAllElements('channel').firstOrNull;
      final albumTitle = channel?.findElements('title').firstOrNull?.innerText.trim() ?? '';

      final items = doc.findAllElements('item');
      final result = <XimalayaTrack>[];
      for (final item in items) {
        final title = item.findElements('title').firstOrNull?.innerText.trim() ?? '';
        final link = item.findElements('link').firstOrNull?.innerText.trim() ?? '';
        final desc = item
                .findElements('description')
                .firstOrNull
                ?.innerText
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim() ??
            '';
        if (desc.length > 200) {
          // 8/7 加: 限长, 避免 description 巨长占屏
          desc.substring(0, 200);
        }

        // pubDate 解析 (RFC822)
        DateTime pubDate = DateTime.now();
        final pubDateStr = item.findElements('pubDate').firstOrNull?.innerText.trim();
        if (pubDateStr != null && pubDateStr.isNotEmpty) {
          try {
            pubDate = DateTime.parse(pubDateStr.replaceAll(RegExp(r'[,]'), '').trim());
          } catch (_) {}
        }

        // audio enclosure url (宪法 §1.1: 仅 metadata, 不缓存)
        String audioUrl = '';
        final enclosureEl = item.findElements('enclosure').firstOrNull;
        if (enclosureEl != null) {
          audioUrl = enclosureEl.getAttribute('url') ?? '';
        }

        // itunes:duration (秒)
        int durationSec = 0;
        final itunesDuration = item
            .findElements('itunes:duration')
            .firstOrNull
            ?.innerText
            .trim();
        if (itunesDuration != null && itunesDuration.isNotEmpty) {
          // 格式: HH:MM:SS 或 MM:SS 或纯秒
          final parts = itunesDuration.split(':');
          if (parts.length == 3) {
            durationSec =
                int.tryParse(parts[0])! * 3600 + int.tryParse(parts[1])! * 60 + int.tryParse(parts[2])!;
          } else if (parts.length == 2) {
            durationSec = int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
          } else {
            durationSec = int.tryParse(itunesDuration) ?? 0;
          }
        }

        if (title.isEmpty || link.isEmpty) continue;
        result.add(
          XimalayaTrack(
            title: title,
            url: link,
            description: desc,
            pubDate: pubDate,
            audioUrl: audioUrl,
            durationSec: durationSec,
            albumTitle: albumTitle,
          ),
        );
      }
      return result;
    } catch (e) {
      debugPrint('[ximalaya] XML parse failed: $e');
      return [];
    }
  }

  /// 8/7 沿用 alert (沿 #137): 搜索 API 不公开 JSON, 走 SPA HTML 撞宪法 §1.1 不允许爬
  /// 替代方案: iTunes Search API (公开 JSON, 沿 https://itunes.apple.com/search)
  /// TODO (沿 #137 沿用 alert): 等你拍要不要接 iTunes 搜索 (国际版) 还是手动专辑列表
  Future<List<dynamic>> search(String keyword) async {
    // 8/7 沿用 alert: 返空数组 + TODO log, 不假装能搜
    debugPrint('[ximalaya] search("$keyword") → [] (沿 #137 沿用 alert, 搜索 API 不公开)');
    return [];
  }

  /// 8/7 沿用 alert: 同 search 原因, 返空
  Future<List<dynamic>> albums() async {
    debugPrint('[ximalaya] albums() → [] (沿 #137 沿用 alert, 待 Brien 拍)');
    return [];
  }
}