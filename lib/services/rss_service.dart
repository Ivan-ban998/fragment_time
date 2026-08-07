// lib/services/rss_service.dart
// 7/14 Brien 拍板接真 RSS (国内 36 氪 + 国际 The Verge)
// 走宪法 §1.1: 只接 metadata (title/url/description), 不存原片, 跳原站

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
// 8/7 加 (沿 SOUL #137 真凶): web 上 print() 走 console.log 估计被截,
//   真接 dart:html console.log 避免 release mode print 走 stdout 丢
import 'web_console_stub.dart'
    if (dart.library.html) 'web_console_web.dart' as webconsole;
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
  // 8/1 修 (沿用 #103 真改没改对 — Brien 15:13 硬刷报 127.0.0.1:7088 connection refused):
  // - 之前 127.0.0.1 = 浏览器本地, NAS rss_proxy 拉不到 (desktop 浏览器撞)
  // - 改 NAS LAN IP 192.168.1.2 (desktop + 内网浏览器走局域网访问)
  // - 8/1 二次修: tailscale 100.89.204.123 拒连 (tailscale0 device 不存在, 进程没启)
  // - rss_proxy.py 也已绑 0.0.0.0 不止 127.0.0.1 (8/1 同步修)
  // 沿用 #113: 外网访问 fragment_time 时 rss 拉不到 → 下次起 tailscale + 改回 IP
  // 8/4 修 #169 CORS: 相对路径 /rss 同 origin, 避免跨域被拒
// ft_server.py 在 7080 同时 serve fragment_time + /rss 路径
static const String _proxyBase = '/rss';
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

  // 8/7 加 (沿 SOUL #137 真凶): 客户端 dedupe
  //   8 userType × 4 scene = 24 桶, UI 进场景页 / refresh / Tinder 换 6 张
  //   → 同一 bucket 反复调 fetchByBucket → 8-16 个同源 fetch 堆栈
  //   复 bug 链: Chrome 6 连接池 + 服务端单线程 → 浏览器看 pending
  //   修法: 同一 bucket 多次调 = 1 个 in-flight, 其他 await 同一 Future
  static final Map<String, Future<List<RssItem>>> _pendingByFeedUrl = {};
  static final Map<String, List<RssItem>> _cachedByFeedUrl = {};
  static DateTime? _cacheLoadedAt;

  // 缓存 TTL: 5 分钟 (用户拖动 Tinder / 切场景 不要反复拉)
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// 7/29 加: 多 RSS 源 fallback 链
  List<String> get _feedUrls => isInternational
      ? [_vergeFeed]
      : [_sspaiFeed, _kr36Feed]; // 8/5 修: 36kr 触发火山引擎 WAF 挑战 (返 17KB HTML 不是 RSS), sspai 提到主源, 36kr 留 fallback

  String get _sourceName => isInternational ? 'The Verge' : '36氪';

  /// 7/14 加: 拉 RSS feed + 解析 (3 retries, 5s timeout each)
  /// 7/29 改: 多源 fallback + 单次 timeout 拉到 8s (36 氪实测 10s 慢)
  /// 8/7 加 (沿 SOUL #137): 客户端 dedupe by feedUrl — 同一源多个并发 fetch 合成 1 个 HTTP 请求
  Future<List<RssItem>> fetchTop({int limit = 20}) async {
    // 8/7 dedupe: 按 feedUrl (不是整组 _feedUrls) 逐个 dedupe
    //   fetchTop 试多源 fallback, 每个源独立 dedupe
    final List<RssItem> aggregated = [];
    for (final feedUrl in _feedUrls) {
      // 查 cache (5min TTL)
      if (_cachedByFeedUrl.containsKey(feedUrl) &&
          _cacheLoadedAt != null &&
          DateTime.now().difference(_cacheLoadedAt!) < _cacheTtl) {
        aggregated.addAll(_cachedByFeedUrl[feedUrl]!);
        continue;
      }
      // 查 in-flight (8/7 修: 同源并发只 1 个 HTTP)
      final inFlight = _pendingByFeedUrl[feedUrl];
      if (inFlight != null) {
        final items = await inFlight;
        aggregated.addAll(items);
        continue;
      }
      // 发起新 fetch (存 in-flight, 完成清空)
      final future = _fetchFeed(feedUrl, limit: limit);
      _pendingByFeedUrl[feedUrl] = future;
      try {
        final items = await future;
        // 8/7 改 (沿 SOUL #137 真凶): 只 cache 成功 + 非空结果
        // 真凶: 之前空结果也 cache → 5 分钟内反复返空 (用户刷新 / 切 bucket 都不重试)
        if (items.isNotEmpty) {
          _cachedByFeedUrl[feedUrl] = items;
          _cacheLoadedAt ??= DateTime.now();
        }
        aggregated.addAll(items);
      } finally {
        _pendingByFeedUrl.remove(feedUrl);
      }
      // 拿到 6+ 条就别试下一个源 (省请求)
      if (aggregated.length >= 6) break;
    }
    return aggregated;
  }

  /// 8/7 加 (沿 SOUL #137): 单源 RSS 拉取 (1 个 HTTP 请求)
  Future<List<RssItem>> _fetchFeed(String feedUrl, {required int limit}) async {
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
          // 8/7 加 (沿 SOUL #137 真凶): web 专用 console.log 验 0 条真凶
          //   真凶: 后端 curl 返 10 条, 但 Dart http package 在 web 上可能 body 被截断 / 编码错
          webconsole.log('[rss] $feedUrl → status=${resp.statusCode} bodyLen=${resp.body.length}');
          final items = _parse(resp.body, limit);
          webconsole.log('[rss] $feedUrl → parsed ${items.length} items');
          if (items.isNotEmpty) return items;
          // 解析空 -> 试下一个源 (在外层循环里 break 走)
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

    // 8/2 修 (沿用 #103 真改没改对 第 N 次): 返整个 items (不裁到 6), 让上游
    //   getRecommendations / fetchRecommendContent 拿 offset 切片 6 条
    //   真凶: 之前返 6 条 + 上游 start = offset % 6 → offset 0-5 都循环同一组
    return items
        .map((it) => toContentItem(it, contentType: defaultKind))
        .toList();
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
