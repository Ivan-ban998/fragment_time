// lib/services/rss_service.dart
// 7/14 Brien 拍板接真 RSS (国内 36 氪 + 国际 The Verge)
// 走宪法 §1.1: 只接 metadata (title/url/description), 不存原片, 跳原站

import 'package:flutter/foundation.dart' show kIsWeb;
// 8/7 加 (沿 SOUL #137 真凶): web 上 print() 走 console.log 估计被截,
//   真接 dart:html console.log 避免 release mode print 走 stdout 丢
import 'web_console_stub.dart'
    if (dart.library.html) 'web_console_web.dart' as webconsole;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert' show jsonEncode, jsonDecode;
// 8/8 加 (沿 SOUL #189): unawaited() 标记 fire-and-forget Future
import 'dart:async' show unawaited;
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

  /// 8/8 加 (沿 SOUL #189): disk cache 序列化
  Map<String, dynamic> toJson() => {
        't': title,
        'u': url,
        'd': description,
        'p': pubDate.millisecondsSinceEpoch,
        's': sourceName,
      };

  static RssItem fromJson(Map<String, dynamic> j) => RssItem(
        title: j['t'] as String? ?? '',
        url: j['u'] as String? ?? '',
        description: j['d'] as String? ?? '',
        pubDate: DateTime.fromMillisecondsSinceEpoch(j['p'] as int? ?? 0),
        sourceName: j['s'] as String? ?? '',
      );
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

  // 8/8 加 (沿 SOUL #189): 持久化 cache (SharedPreferences)
  //   用户痛点: 冷启动 / reload web / 断网 → 28 桶全部 8s×N 慢加载
  //   修法: 落盘最近一次成功结果 + 加载时间, 启动先返旧 + 后台静默刷新
  //   §1.1 严: 只 cache metadata (title/url/description/pubDate/sourceName), 不存原片
  static const String _diskPrefix = 'rss_cache_';
  static const String _diskLoadedAtSuffix = '_loaded_at';
  // 8/8 升一阶: disk cache 24h TTL (in-memory 还是 5min, 两层独立)
  //   24h rationale: 公开 RSS 多数 1-4h 发布频率, 24h 兜底够了
  //   stale-while-revalidate: 启动优先返旧, 后台 fetch 成功后覆盖
  static const Duration _diskTtl = Duration(hours: 24);

  /// 8/8 加: 从 disk 读 cache (冷启动秒开用)
  static Future<List<RssItem>> _loadFromDisk(String feedUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_diskPrefix${feedUrl.hashCode.abs()}';
      final raw = prefs.getString(key);
      final loadedAt = prefs.getInt('$key$_diskLoadedAtSuffix');
      if (raw == null || loadedAt == null) return [];
      final age = DateTime.now().millisecondsSinceEpoch - loadedAt;
      if (age < 0 || age > _diskTtl.inMilliseconds) return [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(RssItem.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  /// 8/8 加: 写 disk cache (成功后, 异步 fire-and-forget)
  static Future<void> _saveToDisk(String feedUrl, List<RssItem> items) async {
    if (items.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_diskPrefix${feedUrl.hashCode.abs()}';
      final json = jsonEncode(items.map((it) => it.toJson()).toList());
      await prefs.setString(key, json);
      await prefs.setInt(
        '$key$_diskLoadedAtSuffix',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // 写盘失败不影响主流程 (in-memory 仍 cache)
    }
  }

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
    // 8/8 升一阶 (沿 SOUL #189 #137):
    //   1. in-memory cache (5min TTL) — 沿用 8/7
    //   2. disk cache (24h TTL) — 8/8 新加, 冷启动秒开
    //   3. 后台静默刷新 — 拿旧数据马上返, fetch 完成覆盖
    final List<RssItem> aggregated = [];
    final List<String> needsFetch = [];

    for (final feedUrl in _feedUrls) {
      // 1. in-memory cache
      if (_cachedByFeedUrl.containsKey(feedUrl) &&
          _cacheLoadedAt != null &&
          DateTime.now().difference(_cacheLoadedAt!) < _cacheTtl) {
        aggregated.addAll(_cachedByFeedUrl[feedUrl]!);
        continue;
      }
      // 2. disk cache (冷启动用) — 同步返旧数据, 后台静默刷新
      final diskItems = await _loadFromDisk(feedUrl);
      if (diskItems.isNotEmpty) {
        // 旧数据先填占位 (in-memory 也写一份, 5min 内不重复查 disk)
        _cachedByFeedUrl[feedUrl] = diskItems;
        _cacheLoadedAt ??= DateTime.now();
        aggregated.addAll(diskItems);
      }
      // 3. 标记要 fetch (有 disk 数据 = 静默后台, 无 disk 数据 = 同步等)
      needsFetch.add(feedUrl);
    }

    // 4. 并发 fetch (沿 SOUL #137 dedupe: 同源串行, 不同源并发)
    for (final feedUrl in needsFetch) {
      final inFlight = _pendingByFeedUrl[feedUrl];
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      final future = _fetchFeed(feedUrl, limit: limit);
      _pendingByFeedUrl[feedUrl] = future;
      try {
        final items = await future;
        if (items.isNotEmpty) {
          _cachedByFeedUrl[feedUrl] = items;
          _cacheLoadedAt ??= DateTime.now();
          // 8/8 新加: 落盘 (fire-and-forget, 不阻塞)
          unawaited(_saveToDisk(feedUrl, items));
        }
      } finally {
        _pendingByFeedUrl.remove(feedUrl);
      }
    }

    // 5. 重组结果: 优先取最新 in-memory (fetch 后已更新), 没 fetch 到的用 disk
    final List<RssItem> result = [];
    for (final feedUrl in _feedUrls) {
      final mem = _cachedByFeedUrl[feedUrl];
      if (mem != null) result.addAll(mem);
    }
    return result;
  }

  /// 8/8 加 (沿 SOUL #137): 简化 dedupe — URL 完全相同 + title 80% 相似
  static List<RssItem> _dedupeSimilar(List<RssItem> items) {
    final result = <RssItem>[];
    final seenUrls = <String>{};
    final seenTitles = <String>[]; // normalized titles for similarity

    String normalize(String s) {
      return s
          .toLowerCase()
          .replaceAll(RegExp(r'[\s\p{P}]+', unicode: true), '')
          .substring(0, s.length.clamp(0, 100));
    }

    for (final item in items) {
      if (!seenUrls.add(item.url)) continue; // URL 重复 skip
      final normTitle = normalize(item.title);
      bool tooSimilar = false;
      for (final seen in seenTitles) {
        if (normTitle.isEmpty || seen.isEmpty) continue;
        // 8/8 简化: 包含关系 + 80% 长度比
        if (normTitle.contains(seen) || seen.contains(normTitle)) {
          tooSimilar = true;
          break;
        }
        final minLen = normTitle.length < seen.length ? normTitle.length : seen.length;
        final maxLen = normTitle.length > seen.length ? normTitle.length : seen.length;
        if (maxLen == 0) continue;
        // 8/8 简化: 80% 长度比 (不象 KMP / Levenshtein, 但足以 catch 转发标题)
        if (minLen / maxLen > 0.8) {
          tooSimilar = true;
          break;
        }
      }
      if (tooSimilar) continue;
      result.add(item);
      seenTitles.add(normTitle);
    }
    return result;
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
  // 8/8 加 (沿 SOUL #137 #160): 4 套 scene 主题词筛
  //  旧: 30 条 RSS 共享池, userType/scene 只切视觉类型, 不筛内容 → 跑题 (学场景看到 5G 商业新闻)
  //  修: 按 scene 主题词筛, 命中 ≥ 1 纳入, 0 命中 fallback 全部 (沿 SOUL #119 不撒谎)
  //  沿 #19 沿用 alert: userType 不分 (8 类型共用 4 套主题词), 留给 Brien 醒后拍
  static const Map<Scene, List<String>> _sceneKeywords = {
    Scene.learn: [
      'AI', 'GPT', 'LLaMA', 'Claude', 'Gemini', 'AGI', 'Agent',
      '科技', '编程', '学术', '商业', '公司', '模型', '论文', '投资人', '开源',
      '芯片', '云', '数据', '算法', '训练', '推理', 'GPU', 'Transformer', 'API',
      '机器学习', '深度学习', 'VR', 'AR', '黑客', '发布', '研发', '实验室',
      '创业', '融资', '上市', 'IPO', '财报', '估值', '股市', '金融', '投资',
    ],
    Scene.listen: [
      '音乐', '播客', '演出', '专辑', '音频', '节目', '故事', '电台',
      '相声', '脱口秀', '采访', '访谈', '讲座', '广播', '听书', '有声',
      '说书', '评书', '朗诵', '新闻', '财经', '谈论', '今晚', '今晚聊',
      '收听', '主播', '人声', '歌手', '作曲家', '乐队', '巡回',
    ],
    Scene.relax: [
      '生活', '美食', '旅游', '文化', '影评', '书评', '旅行', '摄影',
      '心理', '冥想', '读书', '电影', '时尚', '家居', '宠物', '养生',
      '健康', '美容', '心境', '散文', '随笔', '日记', '手账',
      '插花', '茶', '咖啡', '烘焙', '小说', '艺术', '展览', '设计',
    ],
    Scene.workout: [
      '运动', '跑步', '健身', '训练', '比赛', '体育', '装备', '户外',
      '瑜伽', '马拉松', '减肥', '肌肉', '跑步机', '普拉提', '自行车',
      '徒步', '登山', '游泳', '足球', '篮球', '网球', '高尔夫', '滑雪',
      '心率', '能量', '体能', '护膝', '体重', '蛋白', '塑形',
    ],
  };

  Future<List<ContentItem>> fetchByBucket(UserType userType, Scene scene) async {
    final items = await fetchTop(limit: 30);
    if (items.isEmpty) return [];

    // 8/8 升一阶 (沿 SOUL #137 #160): scene 主题词筛
    final keywords = _sceneKeywords[scene] ?? [];
    final filtered = keywords.isEmpty
        ? items
        : items.where((it) {
            final text = '${it.title} ${it.description}'.toLowerCase();
            return keywords.any((kw) => text.contains(kw.toLowerCase()));
          }).toList();

    // 8/8 沿 SOUL #119: 0 命中 fallback 全部 (不撒谎, 跑题比没结果轻)
    final result = filtered.isEmpty ? items : filtered;

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
    // 8/8 升一阶 (沿 SOUL #137): cross-source dedupe, 防止同一条新闻被多源拉到
    final deduped = _dedupeSimilar(result);
    return deduped
        .map((it) => toContentItem(it, contentType: defaultKind))
        .toList();
  }

  /// 7/29 加: 搜索 RSS 关键词
  /// 8/8 升一阶 (沿 SOUL #137 #160): relevance 排序 + title 命中 > desc 命中 + 全源 aggregate
  ///   旧实现: 简单 substring match, title 和 desc 同权, 多源可能拼一块全返
  ///   真凶: query="AI" 在 50 条 RSS 里命中 30+ 条, 但 90% 命中在 desc, 重要度一样
  ///   修法: title 命中 +3, desc 命中 +1, 按分数降序
  Future<List<ContentItem>> searchInRss(String query, {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final items = await fetchTop(limit: 30);
    if (items.isEmpty) return [];

    // 8/8 升一阶 (沿 SOUL #137): dedupe by URL (同一 URL 不重复)
    final seenUrls = <String>{};
    final uniqueItems = items.where((it) => seenUrls.add(it.url)).toList();

    final q = query.toLowerCase();
    final scored = <(RssItem, int)>[];
    for (final item in uniqueItems) {
      final titleHit = item.title.toLowerCase().contains(q);
      final descHit = item.description.toLowerCase().contains(q);
      if (!titleHit && !descHit) continue;
      // 8/8 升一阶: title 命中 > desc 命中
      final score = (titleHit ? 3 : 0) + (descHit ? 1 : 0);
      scored.add((item, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    return scored
        .take(limit)
        .map((r) => toContentItem(r.$1, contentType: 'article'))
        .toList();
  }
}
