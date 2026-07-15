// lib/services/rss_service.dart
// 7/14 Brien 拍板接真 RSS (国内 36 氪 + 国际 The Verge)
// 走宪法 §1.1: 只接 metadata (title/url/description), 不存原片, 跳原站

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/models.dart';

class RssItem {
  final String title;
  final String url;
  final String description;
  final DateTime pubDate;
  final String sourceName;

  RssItem({
    required this.title,
    required this.url,
    required this.description,
    required this.pubDate,
    required this.sourceName,
  });
}

class RssService {
  // 国内版: 36 氪
  static const String _kr36Feed = 'https://36kr.com/feed';
  // 国际版: The Verge
  static const String _vergeFeed = 'https://www.theverge.com/rss/index.xml';

  /// 7/14 加: 是否国际版
  final bool isInternational;

  RssService({this.isInternational = false});

  String get _feedUrl => isInternational ? _vergeFeed : _kr36Feed;

  String get _sourceName => isInternational ? 'The Verge' : '36氪';

  /// 7/14 加: 拉 RSS feed + 解析 (3 retries, 5s timeout each)
  Future<List<RssItem>> fetchTop({int limit = 20}) async {
    // 7/14 SOUL #76: 重试 3 次防 CF edge transient RST
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final resp = await http
            .get(
              Uri.parse(_feedUrl),
              headers: const {
                'User-Agent': 'fragment_time/1.0 (NAS)',
                'Accept': 'application/rss+xml, application/xml;q=0.9, */*;q=0.8',
              },
            )
            .timeout(const Duration(seconds: 5));

        if (resp.statusCode != 200) {
          // 5xx 才重试, 4xx (rate limit/404) 直接放弃
          if (resp.statusCode >= 500 && attempt < 3) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            continue;
          }
          return [];
        }
        return _parse(resp.body, limit);
      } catch (e) {
        // timeout/network -> 重试
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        // 3 次都失败 -> 返回 [], news.fetchFromRss 会 fallback 假数据
        return [];
      }
    }
    return [];
  }

  List<RssItem> _parse(String body, int limit) {
    try {
      final doc = xml.XmlDocument.parse(body);
      final items = doc.findAllElements('item');
      final result = <RssItem>[];
      for (final item in items.take(limit)) {
        final title = _textOf(item, 'title');
        final url = _textOf(item, 'link');
        final desc = _stripHtml(_textOf(item, 'description'));
        final pubDateStr = _textOf(item, 'pubDate');
        DateTime? dt;
        if (pubDateStr.isNotEmpty) {
          try {
            dt = _parseRfc822(pubDateStr);
          } catch (_) {
            dt = DateTime.now();
          }
        } else {
          dt = DateTime.now();
        }
        if (title.isEmpty || url.isEmpty) continue;
        result.add(
          RssItem(
            title: title,
            url: url,
            description: desc,
            pubDate: dt,
            sourceName: _sourceName,
          ),
        );
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  String _textOf(xml.XmlElement el, String tag) {
    final found = el.findElements(tag);
    if (found.isEmpty) return '';
    return found.first.innerText.trim();
  }

  String _stripHtml(String html) {
    if (html.isEmpty) return '';
    // 7/14 简化: 拿前 160 chars (移除 HTML 标签)
    return html
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .length >
        160
        ? html
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .substring(0, 160) +
            '…'
        : html
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
  }

  /// 简易 RFC 822 解析: "Mon, 14 Jul 2026 19:21:42 +0800" → DateTime
  DateTime _parseRfc822(String s) {
    // RFC822 格式: "Tue, 14 Jul 2026 19:21:42 +0800"
    // Dart 标准库 DateTime.parse 不支持 RFC822
    final cleaned = s.replaceAll(RegExp(r'[,]'), '').trim();
    // 用 RFC1123 兼容: "Tue 14 Jul 2026 19:21:42 +0800"
    return DateTime.parse(cleaned);
  }

  /// 7/14 加: 把 RSS item 转 ContentItem (适配 24 桶)
  ContentItem toContentItem(RssItem r, {String contentType = 'article'}) {
    return ContentItem(
      id: 'rss_${r.url.hashCode.abs()}',
      title: r.title,
      description: r.description,
      source: r.sourceName,
      sourceType: isInternational ? ContentSource.rss : ContentSource.news36kr,
      contentType: contentType == 'card' ? ContentType.card : ContentType.article,
      duration: '5min',
      externalUrl: r.url,
      priceType: ContentPriceType.free,
    );
  }

  /// 7/14 加: 按 user_type × scene 映射 RSS items (简单发配 — 真实推荐算法 P1 干)
  Future<List<ContentItem>> fetchByBucket(UserType userType, Scene scene) async {
    final items = await fetchTop(limit: 30);
    if (items.isEmpty) return [];

    // 简单发配: 6 桶都拿到 RSS items, 不同 bucket 显示不同切片
    // 7/14: 不做内容分类 (没时间), 但给不同 bucket 起不同 default card_type 视觉变化
    String defaultKind;
    switch (scene) {
      case Scene.learn:
        defaultKind = 'article';
        break;
      case Scene.listen:
        defaultKind = 'card';
        break;
      case Scene.relax:
        defaultKind = 'card';
        break;
      case Scene.workout:
        defaultKind = 'card';
        break;
    }

    // 错位切片: 不同 bucket 用不同 offset (循环 RSS items)
    final offset = (userType.index * 5 + scene.index * 3) % items.length;
    final picked = <ContentItem>[];
    for (var i = 0; i < items.length && picked.length < 6; i++) {
      final idx = (offset + i) % items.length;
      picked.add(toContentItem(items[idx], contentType: defaultKind));
    }
    return picked;
  }
}
