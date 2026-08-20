// lib/services/apple_podcasts_service.dart
// 8/7 加 (沿 ROADMAP #D + SOUL #137 真凶): Apple Podcasts 公开 JSON API 真接
// 真凶链:
//   - 之前国际版搜索返空 (international_service.dart 占位)
//   - 8/7 查公开 API: rss.applemarketingtools.com/api/v2/{country}/podcasts/top/{limit}/podcasts.json
//     真返 JSON, 含 artistName/name/id/url/artworkUrl100/genres 等 metadata
//   - 沿宪法 §1.1: 仅拿 metadata + 跳原站 (itunes.apple.com/.../id{trackId})
// 修法 (宪法 §1.1 严):
//   - topCharts(country, limit) 拿 Apple 官方榜单 metadata
//   - 不缓存音频, 不缓存任何播放 URL (feedUrl 仅展示, 实际听跳原站)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApplePodcast {
  final String id;
  final String name;
  final String artistName;
  final String url; // itunes.apple.com/.../id{id} (宪法 §1.1: 跳原站)
  final String artworkUrl;
  final List<String> genres;
  final String? feedUrl; // RSS feed (宪法 §1.1: 仅 metadata, 不缓存)

  ApplePodcast({
    required this.id,
    required this.name,
    required this.artistName,
    required this.url,
    required this.artworkUrl,
    required this.genres,
    this.feedUrl,
  });

  // 转 ContentItem 适配 24 桶
  ContentItem toContentItem() {
    return ContentItem(
      id: 'apple_podcast_$id',
      title: name,
      description: '$artistName · ${genres.join('/')}',
      source: 'Apple Podcasts',
      sourceType: ContentSource.applePodcasts,
      contentType: ContentType.audio,
      duration: '5min', // 沿用 5min (宪法 §1.1 不缓存时长)
      externalUrl: url, // 跳原站
      priceType: ContentPriceType.free,
      imageUrl: artworkUrl,
    );
  }
}

class ApplePodcastsService {
  // 8/7 加 (沿 SOUL #137): 同源代理 (跟 RSS /api/llm 模式一致)
  // 真凶链: web 调 https://rss.applemarketingtools.com/... → CORS 拦截
  //   修法: ft_server.py 代理该域 → 同源不撞 CORS
  String _resolveUrl(String country, int limit) {
    if (kIsWeb) {
      // 8/7: 用 /rss 路径代理 (ft_server.py 已支持)
      return '/rss?url=${Uri.encodeComponent('https://rss.applemarketingtools.com/api/v2/$country/podcasts/top/$limit/podcasts.json')}';
    }
    return 'https://rss.applemarketingtools.com/api/v2/$country/podcasts/top/$limit/podcasts.json';
  }

  /// 8/7 加: 真接 Apple Podcasts top charts
  Future<List<ApplePodcast>> topCharts({String country = 'us', int limit = 25}) async {
    try {
      final resp = await http
          .get(
            Uri.parse(_resolveUrl(country, limit)),
            headers: const {
              'User-Agent': 'fragment_time/1.0 (NAS)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) {
        debugPrint('[apple-podcasts] topCharts country=$country → ${resp.statusCode}');
        return [];
      }

      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return [];

      final feed = body['feed'];
      if (feed is! Map<String, dynamic>) return [];

      final results = feed['results'];
      if (results is! List) return [];

      return results
          .whereType<Map<String, dynamic>>()
          .map((r) => ApplePodcast(
                id: r['id']?.toString() ?? '',
                name: r['name']?.toString() ?? '',
                artistName: r['artistName']?.toString() ?? '',
                url: r['url']?.toString() ?? '',
                artworkUrl: r['artworkUrl100']?.toString() ?? '',
                genres: (r['genres'] as List?)
                        ?.whereType<Map<String, dynamic>>()
                        .map((g) => g['name']?.toString() ?? '')
                        .where((s) => s.isNotEmpty)
                        .toList() ??
                    [],
                feedUrl: r['feedUrl']?.toString(),
              ))
          .where((p) => p.id.isNotEmpty && p.url.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[apple-podcasts] topCharts country=$country failed: $e');
      return [];
    }
  }

  /// 8/7 加: 真接 Apple Podcasts search (公开 search JSON API)
  /// 8/7 测: https://itunes.apple.com/search?term=keyword&media=podcast&limit=N&country=CN
  Future<List<ApplePodcast>> search(String keyword, {String country = 'us', int limit = 20}) async {
    if (keyword.trim().isEmpty) return [];
    try {
      // 8/7 沿 #137 沿用 alert: iTunes Search API 公开, 跨域需代理
      // 真凶链: web 调 https://itunes.apple.com/search → CORS 拦截
      //   修法: ft_server.py 代理 (沿 #137 #171 RSS 模式)
      final queryStr = Uri(queryParameters: {
        'term': keyword,
        'media': 'podcast',
        'limit': '$limit',
        'country': country.toUpperCase(),
      }).query;
      final url = kIsWeb
          ? '/rss?url=${Uri.encodeComponent('https://itunes.apple.com/search?$queryStr')}'
          : 'https://itunes.apple.com/search?$queryStr';

      final resp = await http
          .get(
            Uri.parse(url),
            headers: const {
              'User-Agent': 'fragment_time/1.0 (NAS)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) {
        debugPrint('[apple-podcasts] search keyword="$keyword" → ${resp.statusCode}');
        return [];
      }

      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return [];
      final results = body['results'];
      if (results is! List) return [];

      return results
          .whereType<Map<String, dynamic>>()
          .where((r) => r['wrapperType'] == 'track' || r['kind'] == 'podcast')
          .map((r) => ApplePodcast(
                id: r['collectionId']?.toString() ?? r['trackId']?.toString() ?? '',
                name: r['collectionName']?.toString() ?? r['trackName']?.toString() ?? '',
                artistName: r['artistName']?.toString() ?? '',
                url: r['collectionViewUrl']?.toString() ?? r['trackViewUrl']?.toString() ?? '',
                artworkUrl: r['artworkUrl100']?.toString() ?? '',
                genres: (r['genres'] as List?)
                        ?.map((g) => g.toString())
                        .where((s) => s.isNotEmpty)
                        .toList() ??
                    [],
                feedUrl: r['feedUrl']?.toString(),
              ))
          .where((p) => p.id.isNotEmpty && p.url.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[apple-podcasts] search keyword="$keyword" failed: $e');
      return [];
    }
  }
}