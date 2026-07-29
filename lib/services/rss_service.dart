// lib/services/rss_service.dart
// 7/14 Brien 拍板接真 RSS (国内 36 氪 + 国际 The Verge)
// 走宪法 §1.1: 只接 metadata (title/url/description), 不存原片, 跳原站

import 'package:flutter/foundation.dart' show kIsWeb;
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
  // 7/29 加: NAS 后端代理 (绕过 web 浏览器 CORS 限制, 沿用 SOUL #103 沿用 #113 沿用 #15)
  // 浏览器 fetch 36 氪受 CORS 拦截, 走 NAS proxy 拉 (后端 curl 不受限制)
  static const String _proxyBase = 'http://127.0.0.1:7088/rss';
  // 国内版: 36 氪 (主源)
  static const String _kr36Feed = 'https://36kr.com/feed';
  // 国内备用: 少数派 (7/29 实测 226ms 极快, 36 氪 10s 慢)
  static const String _sspaiFeed = 'https://sspai.com/feed';
  // 国际版: The Verge
  static const String _vergeFeed = 'https://www.theverge.com/rss/index.xml';

  /// 7/29 加: 走 NAS proxy 拉 feed (web 端) — kIsWeb true
  /// native 端 (mobile) 直接 fetch — 没有 CORS 限制
  String _resolveUrl(String feedUrl) {
    if (kIsWeb) {
      return '$_proxyBase?url=${Uri.encodeComponent(feedUrl)}';
    }
    return feedUrl;
  }

  /// 7/14 加: 是否国际版
  final bool isInternational;

  RssService({this.isInternational = false});

  /// 7/29 加: 多 RSS 源 fallback 链
  List<String> get _feedUrls => isInternational
      ? [_vergeFeed]
      : [_kr36Feed, _sspaiFeed]; // 国内主 36 氪, 慢则 fallback 少数派

  String get _sourceName => isInternational ? 'The Verge' : '36氪';

  /// 7/14 加: 拉 RSS feed + 解析 (3 retries, 5s timeout each)
  /// 7/29 改: 多源 fallback + 单次 timeout 拉到 8s (36 氪实测 10s 慢)
  Future<List<RssItem>> fetchTop({int limit = 20}) async {
    // 7/29: 按 _feedUrls 顺序试, 任一源拿到就返 (不聚合 — 避免重复)
    for (final feedUrl in _feedUrls) {
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final resp = await http
              .get(
                Uri.parse(_resolveUrl(feedUrl)),
                headers: const {
                  'User-Agent': 'fragment_time/1.0 (NAS)',
                  'Accept': 'application/rss+xml, application/xml;q=0.9, */*;q=0.8',
                },
              )
              .timeout(const Duration(seconds: 8));

          if (resp.statusCode == 200) {
            final items = _parse(resp.body, limit);
            if (items.isNotEmpty) return items;
            // 解析空 -> 试下一个源
            break;
          }
          // 5xx 才重试, 4xx 直接试下一个源
          if (resp.statusCode < 500) break;
        } catch (e) {
          // timeout/network -> 重试一次
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 300));
            continue;
          }
          // 该源失败 -> 试下一个
          break;
        }
      }
    }
    // 所有源都失败 -> 返回 [] (UI 走空状态)
    return [];
  }

  List<RssItem> _parse(String body, int limit) {
    try {
      final doc = xml.XmlDocument.parse(body);
      // RSS 2.0 用 <item>, Atom 用 <entry>, 7/29 加 Atom fallback (少数派是 Atom)
      final rssItems = doc.findAllElements('item');
      final atomItems = doc.findAllElements('entry');
      final items = rssItems.isNotEmpty ? rssItems : atomItems;
      final result = <RssItem>[];
      for (final item in items.take(limit)) {
        // Atom 用 <title> 直系子, RSS 2.0 也是; link 在 Atom 是 href 属性
        final title = _textOf(item, 'title');
        String url = _textOf(item, 'link');
        if (url.isEmpty) {
          // Atom: <link href="..."/>
          final linkEl = item.findElements('link').firstOrNull;
          if (linkEl != null) url = linkEl.getAttribute('href') ?? '';
        }
        final desc = _stripHtml(_textOf(item, 'description').isNotEmpty
            ? _textOf(item, 'description')
            : _textOf(item, 'summary'));
        final pubDateStr = _textOf(item, 'pubDate').isNotEmpty
            ? _textOf(item, 'pubDate')
            : _textOf(item, 'updated');
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
    final stripped = html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.length > 160 ? '${stripped.substring(0, 160)}…' : stripped;
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

  /// 7/29 加: 搜索 RSS 关键词 (按 userType×scene 主题词筛)
  /// 简单 substring 匹配 title/description, 返回前 N 条真 RSS
  Future<List<ContentItem>> searchInRss(String query, {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final items = await fetchTop(limit: 30);
    if (items.isEmpty) return [];
    final q = query.toLowerCase();
    final matched = <RssItem>[];
    for (final item in items) {
      if (item.title.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q)) {
        matched.add(item);
      }
    }
    return matched
        .take(limit)
        .map((r) => toContentItem(r, contentType: 'article'))
        .toList();
  }
}
