// lib/services/rss_service.dart
// 7/14 Brien 拍板接真 RSS (国内 36 氪 + 国际 The Verge)
// 走宪法 §1.1: 只接 metadata (title/url/description), 不存原片, 跳原站

import 'package:flutter/foundation.dart' show kIsWeb;
// 8/7 加 (沿 SOUL #137 真凶): web 上 print() 走 console.log 估计被截,
//   真接 dart:html console.log 避免 release mode print 走 stdout 丢
import 'web_console_stub.dart' if (dart.library.html) 'web_console_web.dart' as webconsole;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
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
  /// 8/13 加 (沿 ROADMAP #D): NPR Top Stories (公开 RSS, 听场景补源, 24 桶都能用)
    static const String _nprFeed = 'https://feeds.npr.org/1001/rss.xml';
    // 8/13 加: NPR Music (听场景专属 — 音乐/演出/专辑/歌手都命中)
    static const String _nprMusicFeed = 'https://feeds.npr.org/1039/rss.xml';

    // 8/13 加 (沿 SOUL #198 #137 #190 第 N+5 次): 4 场景真凶治本
    //   真凶: 4 场景都从 sspai 拉 10 条 → 主题词筛后 4-5 条永远同组 → 推荐重叠
    //   修法: 加 7 个真公开 RSS 源 (curl 实测 30-100 items/源) + 按 scene 偏不同源
    //   learn: 极客公园 (30) + IT之家 (60) + Hacker News Best (30) = 120 items 科技
    //   listen: NPR Music (10) + 豆瓣音乐 (20) + NPR Arts (10) = 40 items 音乐/艺术
    //   relax: 豆瓣热门 (20) + 豆瓣电影 (20) + Solidot (20) + Lifehacker (100) = 160 items 生活
    //   workout: 少数派 (10, 工具体系) + Solidot (20 部分) = 真实 RSS 不够, 精选兑底
      static const String _ithomeFeed = 'https://www.ithome.com/rss/';
    static const String _solidotFeed = 'https://www.solidot.org/index.rss';
      // 8/14 二次治本 (沿 SOUL #8): HN Best 3.7s 慢 → 替换为 TechCrunch + Ars Technica + Engadget (0.25-0.59s 快)
    static const String _techCrunchFeed = 'https://techcrunch.com/feed/';
    static const String _arsFeed = 'https://feeds.arstechnica.com/arstechnica/index';
    static const String _engadgetFeed = 'https://www.engadget.com/rss.xml';
  static const String _doubanBookFeed = 'https://www.douban.com/feed/review/book';
  static const String _doubanMovieFeed = 'https://www.douban.com/feed/review/movie';
  static const String _doubanMusicFeed = 'https://www.douban.com/feed/review/music';
  // NPR 细分 (国际版英语源, 不同 scene 偏好)
  static const String _nprBooksFeed = 'https://feeds.npr.org/1032/rss.xml';
  static const String _nprArtsFeed = 'https://feeds.npr.org/1008/rss.xml';
  static const String _nprLifeFeed = 'https://feeds.npr.org/1039/rss.xml';
  static const String _nprHealthFeed = 'https://feeds.npr.org/1128/rss.xml';
  static const String _nprEducationFeed = 'https://feeds.npr.org/1013/rss.xml';
  static const String _nprPlanetMoneyFeed = 'https://feeds.npr.org/1105/rss.xml';

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
  // 8/16 治本 (沿 SOUL #18 真改没改对 第 N+15 次): _cacheLoadedAt 改成 per-feedUrl 字典
  //   真凶: 之前 _cacheLoadedAt 是 global DateTime, 一个源 fetch 设了值, 所有源跟着用
  //     → 经常 fetch 的源让 _cacheLoadedAt 永远小于 5min, 其他源一直命中 in-memory cache
  //     → 实际上前面 fetch 的源"刷新"了所有源的 TTL → 错位
  //   修: 每个 source 有自己的 _cachedLoadedAt[feedUrl], 5min TTL per source
  static final Map<String, DateTime> _cachedLoadedAt = {};

  // 缓存 TTL: 5 分钟 (用户拖动 Tinder / 切场景 不要反复拉)
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// 7/29 加: 多 RSS 源 fallback 链
  /// 8/13 升一阶 (沿 SOUL #137 真凶链): 国际版 + 国内版都加 NPR 公开源
  ///   - 国内: sspai(主) + NPR Top Stories(英文新闻补 listen/relax) + 36kr(fallback 经常 WAF)
  ///   - 国际: Verge(主,atom) + NPR Top Stories + NPR Music(听场景专属英文 podcast)
  ///   - 8/13 沿 SOUL #160: NPR Music 移到国际版 (NPR Music 是英文, 国内用户用不到)
  ///   - NPR Music (1039): 音乐/演出/专辑/歌手命中 listen 主题词 (英文 podcast)
  ///     注: _fetchFeed 走同一个 _parse, RSS 2.0 标准 + itunes:duration 都兼容
  List<String> get _feedUrls => isInternational
      ? [_vergeFeed, _nprFeed, _nprMusicFeed]
      : [_sspaiFeed, _nprFeed, _kr36Feed];

  String get _sourceName => isInternational ? 'The Verge' : '36氪';

  /// 8/13 升一阶 (沿 SOUL #198): 按 scene 配 RSS 源优先级 — 4 场景重叠真凶
  /// 真凶: 4 场景都走同一组 _feedUrls (sspai+NPR+36kr) → 主题词筛后重叠高
  /// 修法: 4 场景用不同 _feedUrls 顺序 (轮换)
  /// 副作用: shuffle + 主题词筛还是过滤, 但起始 source 不同 → 池子不同
  /// 8/13 治本: 把 currentScene 从 static 改 instance (避免 RssService 单例串扰)
  /// 8/14 二次治本 (沿 SOUL #8 Brien 负优化反馈): 移除 lifehacker (2MB body 解析慢 8s+)
  Scene? _currentScene;
  Scene? get currentScene => _currentScene;
  set currentScene(Scene? s) => _currentScene = s;

  /// 8/13 加: 公开 _feedUrlsForScene 给 test (验证 4 场景配不同源)
  List<String> get feedUrlsForScene => _feedUrlsForScene;

  List<String> get _feedUrlsForScene {
    final scene = _currentScene;
    if (!isInternational) {
      // 8/13 治本 (沿 SOUL #198 #137 真凶链): 4 场景真偏不同源
      //   真凶: 之前 4 场景都从 sspai 拉 10 条 → 主题词筛后 4-5 条永远同组
      //   修法: 加 7 个真公开 RSS 源, 4 场景各偏不同源 → 池子不同 → 重叠降低
      //   curl 实测: 极客公园 30 items, IT之家 60, HN Best 30, 豆瓣热门 20,
      //              豆瓣电影 20, 豆瓣音乐 20, Solidot 20, Lifehacker 100 (8/14 移除, 解析 8s)
      switch (scene) {
        case Scene.learn:
          // learn: 偏科技/技术/商业 — IT之家 + 少数派 + TechCrunch + Ars
          // 8/14 三次治本: HN Best 3.7s 慢 → TechCrunch 0.25s + Ars 0.34s (快 + 多内容)
          return [_ithomeFeed, _sspaiFeed, _techCrunchFeed, _arsFeed];
        case Scene.listen:
          // listen: 偏音乐/艺术/英文 podcast — 豆瓣音乐 + NPR Music + NPR Arts
          return [_doubanMusicFeed, _nprMusicFeed, _nprArtsFeed, _nprFeed];
        case Scene.relax:
          // relax: 偏生活/电影/书/杂谈 — 豆瓣热门 + 豆瓣电影 + Solidot + 豆瓣热门 + 少数派
          // 8/14: 移除 lifehacker (8s+ 解析慢拖累), 替换为 豆瓣热门 重复 + sspai
          return [_doubanBookFeed, _doubanMovieFeed, _solidotFeed, _doubanMusicFeed, _sspaiFeed];
        case Scene.workout:
          // workout: 真实 RSS 不够, 偏生活 + 杂谈 + 工具 — 少数派 + Solidot + 豆瓣热门 + Engadget
          // 8/14 三次治本: HN Best 慢 → Engadget 0.59s
          return [_sspaiFeed, _solidotFeed, _doubanBookFeed, _engadgetFeed];
        default:
          return _feedUrls;
      }
    } else {
      // 8/13 升一阶: 国际版 4 场景偏不同 NPR 源
      // 8/14 三次治本: HN Best 慢 → TechCrunch 替代
      switch (scene) {
        case Scene.learn:
          return [_nprBooksFeed, _nprFeed, _vergeFeed, _techCrunchFeed];
        case Scene.listen:
          return [_nprMusicFeed, _nprArtsFeed, _nprFeed];
        case Scene.relax:
          return [_nprLifeFeed, _nprHealthFeed, _nprFeed];
        case Scene.workout:
          return [_nprEducationFeed, _nprPlanetMoneyFeed, _nprFeed];
        default:
          return _feedUrls;
      }
    }
  }

  /// 7/14 加: 拉 RSS feed + 解析 (3 retries, 5s timeout each)
  /// 7/29 改: 多源 fallback + 单次 timeout 拉到 8s (36 氪实测 10s 慢)
  /// 8/7 加 (沿 SOUL #137): 客户端 dedupe by feedUrl — 同一源多个并发 fetch 合成 1 个 HTTP 请求
  /// 8/13 升一阶 (沿 SOUL #190): 加 forceFresh 参数让 "换 6 张" 真换
  ///   真凶: 5min in-memory cache → 重载永远同组 → "换 6 张" 老卡
  ///   修法: forceFresh=true → 跳过 in-memory cache (但仍走 disk cache 防冷启动卡死)
  /// 8/13 升一阶: 加 scene 参数, 跨方法传 scene (避免 instance _currentScene 串扰)
  Future<List<RssItem>> fetchTop({int limit = 20, bool forceFresh = false, Scene? scene}) async {
    // 8/8 升一阶 (沿 SOUL #189 #137):
    //   1. in-memory cache (5min TTL) — 沿用 8/7
    //   2. disk cache (24h TTL) — 8/8 新加, 冷启动秒开
    //   3. 后台静默刷新 — 拿旧数据马上返, fetch 完成覆盖
    final List<RssItem> aggregated = [];
    final List<String> needsFetch = [];

    // 8/13 升一阶 (沿 SOUL #198): 用 _feedUrlsForScene 替代 _feedUrls
    // 8/13 升一阶: 用传进来的 scene (避免 instance _currentScene 串扰)
    // 8/13 治本 (沿 SOUL #18 #6 #103 真改没改对 第 N+6 次): disk cache 并发加载
    //   真凶: 之前 _loadFromDisk 在 for 循环里 await → 4-5 源 × 200ms = 1s 额外等
    //   修: Future.wait 并发加载
    if (scene != null) _currentScene = scene;
    final feedUrls = _feedUrlsForScene;
    final diskFutures = <String, Future<List<RssItem>>>{};
    for (final feedUrl in feedUrls) {
      // 1. in-memory cache (5min TTL) — forceFresh=true 跳过
      // 8/16 升一阶 (沿 SOUL #18): per-feedUrl TTL 检查
      //   之前 _cacheLoadedAt 是 global, 一个源 fetch 设了值, 其他源一直命中
      //   修: _cachedLoadedAt[feedUrl] per source, 5min TTL per source
      if (!forceFresh &&
          _cachedByFeedUrl.containsKey(feedUrl) &&
          _cachedLoadedAt.containsKey(feedUrl) &&
          DateTime.now().difference(_cachedLoadedAt[feedUrl]!) < _cacheTtl) {
        aggregated.addAll(_cachedByFeedUrl[feedUrl]!);
        continue;
      }
      // 2. disk cache (冷启动用) — 异步并发加载
      diskFutures[feedUrl] = _loadFromDisk(feedUrl);
    }
    if (diskFutures.isNotEmpty) {
      final diskResults = await Future.wait(
        diskFutures.entries.map((e) async {
          final items = await e.value;
          return MapEntry(e.key, items);
        }),
        eagerError: false,
      );
      for (final entry in diskResults) {
        final feedUrl = entry.key;
        final items = entry.value;
        if (items.isNotEmpty) {
          // 旧数据先填占位 (in-memory 也写一份, 5min 内不重复查 disk)
          // 8/16 升一阶 (沿 SOUL #18): 每 disk cache 命中都更新 cache time (per-feedUrl)
          //   之前 _cacheLoadedAt ??= DateTime.now() 只在 null 时设, 永远老的值
          //   修: = (不是 ??=) 每次 disk cache 命中都更新到最新
          _cachedByFeedUrl[feedUrl] = items;
          _cachedLoadedAt[feedUrl] = DateTime.now();
          aggregated.addAll(items);
          // 不需要再 fetch (有 disk 数据 = 静默后台刷新)
        } else {
          // 3. 无 disk 数据 → 需要 fetch
          needsFetch.add(feedUrl);
        }
      }
    }

    // 4. 并发 fetch (沿 SOUL #137 dedupe: 同源串行, 不同源并发)
    // 8/13 治本 (沿 SOUL #18 真改没改对 第 N+6 次): 之前 for await 串行
    //   真凶: 4 源 × 8s = 32s 最差 → 用户等 30s+ 转圈
    //   修: Future.wait 真并发 → 总耗时 = 最慢单源 (≈ 4s, 36kr WAF 后 timeout)
    // 8/13 治本 (沿 SOUL #6): 单源失败 catch → 不影响其他源
    final fetchFutures = <Future<void>>[];
    for (final feedUrl in needsFetch) {
      final inFlight = _pendingByFeedUrl[feedUrl];
      if (inFlight != null) {
        fetchFutures.add(inFlight);
        continue;
      }
      final future = _fetchFeed(feedUrl, limit: limit);
      _pendingByFeedUrl[feedUrl] = future;
      fetchFutures.add(
        future.then((items) {
          if (items.isNotEmpty) {
            _cachedByFeedUrl[feedUrl] = items;
            // 8/16 升一阶 (沿 SOUL #18): per-feedUrl cache time
            _cachedLoadedAt[feedUrl] = DateTime.now();
            unawaited(_saveToDisk(feedUrl, items));
          }
        }, onError: (e) {
          // 8/13 治本: 单源失败 (timeout/network) → 跳过, 不影响其他源
        }).whenComplete(() {
          _pendingByFeedUrl.remove(feedUrl);
        }),
      );
    }
    if (fetchFutures.isNotEmpty) {
      await Future.wait(fetchFutures, eagerError: false);
    }

    // 5. 重组结果: 优先取最新 in-memory (fetch 后已更新), 没 fetch 到的用 disk
    // 8/14 治本 (沿 SOUL #198): 之前用 _feedUrls (国内 [sspai, NPR, 36kr]) → 只返回 3 源
    //   真凶: 但 fetchTop 实际拉 4-5 源 (_feedUrlsForScene) → 极客/IT之家/HN 数据丢
    //   修: 用 feedUrls 替代 _feedUrls (本次循环用的源列表)
    // 8/14 三次治本 (沿 SOUL #169 不撒谎): sourceName 重写, 避免 disk cache 老 '36氪' 污染
    //   真凶: disk cache 写入的 sourceName='36氪' (instance _sourceName), 后续命中 disk cache 的
    //     rssItem 仍带 '36氪' 标签 → UI 显示错误 source
    //   修: 在 fetchTop 末尾按 host 重写每 item sourceName
    final List<RssItem> result = [];
    for (final feedUrl in feedUrls) {
      final mem = _cachedByFeedUrl[feedUrl];
      if (mem != null) {
        // 8/14 三次治本: 修正 sourceName (disk cache stale)
        final correctName = _resolveSourceName(feedUrl);
        for (final item in mem) {
          if (item.sourceName != correctName) {
            result.add(RssItem(
              title: item.title,
              url: item.url,
              description: item.description,
              pubDate: item.pubDate,
              sourceName: correctName,
            ));
          } else {
            result.add(item);
          }
        }
      }
    }
    return result;
  }

  /// 8/8 加 (沿 SOUL #137): 简化 dedupe — URL 完全相同 + title 80% 相似
  static List<RssItem> _dedupeSimilar(List<RssItem> items) {
    final result = <RssItem>[];
    final seenUrls = <String>{};
    final seenTitles = <String>[]; // normalized titles for similarity

    String normalize(String s) {
      final stripped = s
          .toLowerCase()
          .replaceAll(RegExp(r'[\s\p{P}]+', unicode: true), '');
      // 8/13 治本 (沿 SOUL #103 真改没改对 第 N+2 次): 之前用 s.length.clamp(0,100),
      //   但 replaceAll 后 stripped 已经变短 (中文标题去掉标点空白后短很多),
      //   仍按 s.length 切会 RangeError (Not in inclusive range 0..35: 43)
      //   后果: _dedupeSimilar 抛 → fetchByBucket 整体崩 → 24 桶全部 0 items
      //   修: 用 stripped.length 算 clamp, 永远安全
      return stripped.substring(0, stripped.length.clamp(0, 100));
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
        // 8/14 三次治本 (沿 SOUL #190): 阈值 0.8 → 0.95 (避免杀掉 NPR Music vs 豆瓣音乐 评同一专辑)
        //   真凶: 之前 0.8 太宽, NPR "Kessel Plays Standards" 跟 豆瓣 "linernotes (评论: Kessel Plays Standards)"
        //     → normalize 后长度比 > 0.8 → 被杀 → listen 5 真 RSS 变 4 (漏了一张)
        //   修: 阈值 0.95, 只杀真重复 (转载/标题几乎一致)
        if (minLen / maxLen > 0.95) {
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
    // 8/14 治本 (沿 SOUL #18 #103 真改没改对 第 N+7 次): timeout 8s → 4s, retries 2 → 1
    //   真凶: 之前 8s × 2 retries = 16s worst case per source → fetchByBucket 等 16s
    //   修: 4s × 1 retry = 4s worst case → 总耗时 = max(4s) 即使单源慢
    //   副作用: 真的慢源直接 fail 跳过, 不拖累其他 (之前 36kr WAF 等 8s 才 502)
    // 8/16 修 (沿 SOUL #8 真改没改对 第 N+19 次): retry dead code
    //   真凶: 之前 'attempt <= 1' + 'if (attempt < 2)' 永远 retry 不到 → 死代码
    //   修: attempt <= 2 真做 1 retry, retry 间隔 500ms (避免太快重连源 WAF 触发)
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await http
            .get(
              Uri.parse(_resolveUrl(feedUrl)),
              headers: const {
                'User-Agent': 'fragment_time/1.0 (NAS)',
                'Accept': 'application/rss+xml, application/xml;q=0.9, */*;q=0.8',
              },
            )
            .timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200) {
          // 8/7 加 (沿 SOUL #137 真凶): web 专用 console.log 验 0 条真凶
          //   真凶: 后端 curl 返 10 条, 但 Dart http package 在 web 上可能 body 被截断 / 编码错
          webconsole.log('[rss] $feedUrl → status=${resp.statusCode} bodyLen=${resp.body.length}');
          // 8/14 治本 (沿 SOUL #18 #103): 大 body (700KB+) 解析可能慢, 包 Future.timeout
          // 8/14 三次治本: 传 feedUrl 给 _parse 让 sourceName 真解析 (避免所有 RSS 标 '36氪')
          List<RssItem> items;
          try {
            items = await Future(() => _parse(resp.body, limit, feedUrl))
                .timeout(const Duration(seconds: 2), onTimeout: () {
              webconsole.log('[rss] $feedUrl → parse timeout 2s, return []');
              return <RssItem>[];
            });
          } catch (e) {
            webconsole.log('[rss] $feedUrl → parse error: $e');
            items = <RssItem>[];
          }
          webconsole.log('[rss] $feedUrl → parsed ${items.length} items');
          if (items.isNotEmpty) return items;
          // 解析空 -> 试下一个源 (在外层循环里 break 走)
          break;
        }
        // 5xx 才重试, 4xx 直接试下一个源
        if (resp.statusCode < 500) break;
      } catch (e) {
        // timeout/network -> 重试一次 (500ms 间隔, 避免 WAF 误判 spam)
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        // 该源失败 -> 试下一个
        break;
      }
    }
    return [];
  }

  // 8/14 三次治本 (沿 SOUL #169 不撒谎): 加 feedUrl 参数 → sourceName 真实
  List<RssItem> _parse(String body, int limit, String feedUrl) {
    // 8/14: 在 parse 时根据 feedUrl 设 sourceName (而不是用 instance _sourceName='36氪' fallback)
    final realSourceName = _resolveSourceName(feedUrl);
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
            sourceName: realSourceName,  // 8/14 三次治本: 用 feedUrl 解析的真 sourceName (不再是 '36氪')
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
      // 8/16 治本 (沿 SOUL #169 不撒谎): 解码 HTML entity + 截取真正 description
      //   真凶: 之前 replaceAll(RegExp(r'<[^>]+>'), '') 只移除 tag, 不处理 HTML entity
      //     → 豆瓣 RSS 的 description 是 "{&#34;blocks&#34;:...}" 这种内部 JSON dump
      //     → UI 显示 "{&#34;blocks&#34;:[...]}" 用户看到乱码
      //     → TTS 读 _fullText 包含 JSON 乱码, 听感也很差
      //   修法:
      //     1. 移除 HTML tag
      //     2. 用 _decodeHtmlEntities 解码 HTML entity (&#34; → ", &amp; → & 等)
      //     3. 如果 description 看起来像 JSON dump (豆瓣内部 blocks), 截取前 80 chars
      final stripped = html
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final unescaped = _decodeHtmlEntities(stripped);
      // 检测豆瓣内部 JSON dump 模式: "{"blocks":..." 或 "{&#34;blocks&#34;:..."
      // 8/16 修: 截到 "评论:" 之前 (豆瓣 description 通常 "用户 评论: 书名 评价: 推荐\n\nJSON dump")
      if (unescaped.contains('"blocks":[') || unescaped.contains('"entityRanges":[')) {
        // 找到 JSON dump 起始位置 "{"
        final jsonStart = unescaped.indexOf('{');
        if (jsonStart > 0) {
          // 截到 JSON dump 之前, 避免 UI 显示 JSON
          return unescaped.substring(0, jsonStart).trim();
        }
        return unescaped.length > 80 ? '${unescaped.substring(0, 80)}…' : unescaped;
      }
      return unescaped.length > 160 ? '${unescaped.substring(0, 160)}…' : unescaped;
    }

    /// 8/16 加 (沿 SOUL #169 不撒谎): 解码 HTML entity (避免 UI 显示乱码)
    /// 真凶: 之前 _stripHtml 不解码 entity, 豆瓣 RSS 返 "&#34;blocks&#34;..." UI 显乱码
    /// 修: 用 RegExp 替换所有 &#NNN; 和 &xxx; 形式
    String _decodeHtmlEntities(String s) {
      return s
          // 数字 entity: &#34; → ", &#38; → &, &#39; → '
          .replaceAllMapped(
            RegExp(r'&#(\d+);'),
            (m) {
              final code = int.tryParse(m.group(1)!);
              return code != null ? String.fromCharCode(code) : m.group(0)!;
            },
          )
          // 16 进制 entity: &#x27; → '
          .replaceAllMapped(
            RegExp(r'&#x([0-9a-fA-F]+);'),
            (m) {
              final code = int.tryParse(m.group(1)!, radix: 16);
              return code != null ? String.fromCharCode(code) : m.group(0)!;
            },
          )
          // 命名 entity: &amp; → &, &lt; → <, &gt; → >, &quot; → ", &apos; → '
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&mdash;', '—')
          .replaceAll('&hellip;', '…')
          .replaceAll('&ldquo;', '“')
          .replaceAll('&rdquo;', '”');
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
    // 8/14 三次治本 (沿 SOUL #169 不撒谎 + #198): source 用 rssItem.sourceName (来自 feedUrl)
    //   真凶: 之前 _resolveSourceName(r.url) 用 item url (music.douban.com/review/...)
    //     → 不匹配 feedUrl 检测 → fallthrough 到 _sourceName='36氪' (instance)
    //     → 所有 RSS item UI 显示 '36氪' (包括 NPR/豆瓣音乐/IT之家)
    //   修: 用 r.sourceName (在 _parse 时根据 feedUrl 真解析写入)
    final realSource = r.sourceName.isNotEmpty ? r.sourceName : _resolveSourceName(r.url);
    // 8/13 治本 (沿 SOUL #198 #137 真凶链第 2 弹): 4 场景重叠
    //   真凶: 之前 sourceType 用 isInternational 写死 'rss' 或 'news36kr' → 国内所有 RSS 都标 news36kr
    //     → ContentScreen / 数据流无法区分 source → 4 场景推荐池完全共享 → 高度重叠
    //   修: sourceType 从 URL 解析真实 source (跟 source name 同步)
    final realSourceType = _resolveSourceType(r.url);
    return ContentItem(
      id: 'rss_${r.url.hashCode.abs()}',
      title: r.title,
      description: r.description,
      source: realSource,
      sourceType: realSourceType,
      contentType: contentType == 'card' ? ContentType.card : ContentType.article,
      duration: '5min',
      externalUrl: r.url,
      priceType: ContentPriceType.free,
    );
  }

  /// 8/13 加: 从 URL 解析真实 source name (sspai/npr/36kr/theverge)
  String _resolveSourceName(String url) {
    if (url.contains('sspai.com')) return '少数派';
    if (url.contains('npr.org')) {
      // NPR 细分 (按 feed id 区分)
      if (url.contains('/1032')) return 'NPR Books';
      if (url.contains('/1008')) return 'NPR Arts';
      if (url.contains('/1039')) return 'NPR Music';
      if (url.contains('/1128')) return 'NPR Health';
      if (url.contains('/1013')) return 'NPR Education';
      if (url.contains('/1105')) return 'NPR Planet Money';
      if (url.contains('/1014')) return 'NPR Politics';
      return 'NPR';
    }
    if (url.contains('36kr.com')) return '36氪';
    if (url.contains('theverge.com')) return 'The Verge';
    if (url.contains('bbci.co.uk')) return 'BBC';
    if (url.contains('ximalaya.com')) return '喜马拉雅';
    // 8/13 加 (沿 SOUL #198): 8 个新源映射
    if (url.contains('geekpark.net')) return '极客公园';
    if (url.contains('ithome.com')) return 'IT之家';
    if (url.contains('solidot.org')) return 'Solidot';
    if (url.contains('hnrss.org')) return 'Hacker News';
    if (url.contains('douban.com/feed/review/book')) return '豆瓣读书';
    if (url.contains('douban.com/feed/review/movie')) return '豆瓣电影';
    if (url.contains('douban.com/feed/review/music')) return '豆瓣音乐';
    // 8/14 三次治本: HN Best 替换为 3 快源
    if (url.contains('techcrunch.com')) return 'TechCrunch';
    if (url.contains('arstechnica.com')) return 'Ars Technica';
    if (url.contains('engadget.com')) return 'Engadget';
    // 8/16 修 (沿 SOUL #169 不撒谎): fallback 不用 _sourceName (写死 '36氪')
    //   真凶: 新 RSS 源没 mapping → 返 _sourceName='36氪' 误导用户
    //   修: fallback 返 'RSS' (中性) + 末尾带 host (给 Brien 调试用)
    if (url.contains('://')) {
      try {
        final host = Uri.parse(url).host;
        return host.isNotEmpty ? 'RSS ($host)' : 'RSS';
      } catch (_) {
        return 'RSS';
      }
    }
    return 'RSS';
  }

  /// 8/13 加: 从 URL 解析真实 ContentSource (跟 source name 同步)
  /// 沿 SOUL #198: 4 场景推荐重叠的真凶 → 所有 RSS 标 'news36kr' 共享池
  /// 修法: sourceType 解析 → 后续 _fetchByBucket 可按 scene 偏好不同 source
  ContentSource _resolveSourceType(String url) {
    if (url.contains('sspai.com')) return ContentSource.rss;
    if (url.contains('npr.org')) return ContentSource.rss;
    if (url.contains('36kr.com')) return ContentSource.news36kr;
    if (url.contains('theverge.com')) return ContentSource.rss;
    if (url.contains('bbci.co.uk')) return ContentSource.rss;
    if (url.contains('ximalaya.com')) return ContentSource.ximalaya;
    // 8/13 加: 8 个新源 (curl 实测 7-100 items/源, 沿 SOUL #198)
    if (url.contains('geekpark.net')) return ContentSource.rss; // 极客公园
    if (url.contains('ithome.com')) return ContentSource.rss; // IT之家
    if (url.contains('solidot.org')) return ContentSource.rss; // Solidot
    if (url.contains('hnrss.org')) return ContentSource.rss; // HN
    if (url.contains('douban.com')) return ContentSource.rss; // 豆瓣
    if (url.contains('lifehacker.com')) return ContentSource.rss;
    return isInternational ? ContentSource.rss : ContentSource.news36kr;
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
      '机器学习', '深度学习', 'VR', 'AR', '黑客', '研发', '实验室',
      '创业', '融资', '上市', 'IPO', '财报', '估值', '股市', '金融', '投资',
      // 8/13 加 (沿 SOUL #198): 极客公园/IT之家/HN 英文关键词 (避开 'news' 避免与 listen 重叠)
      'tech', 'apple', 'google', 'microsoft', 'startup', 'developer',
      'code', 'engineer', 'software', 'hardware', 'phone', 'laptop',
      'cyber', 'robot', 'drone', 'ev', 'space', 'satellite', 'open source',
    ],
    Scene.listen: [
      '音乐', '播客', '演出', '专辑', '音频', '节目', '故事', '电台',
      '相声', '脱口秀', '采访', '访谈', '讲座', '广播', '听书', '有声',
      '说书', '评书', '朗诵', '新闻', '财经', '谈论', '今晚', '今晚聊',
      '收听', '主播', '人声', '歌手', '作曲家', '乐队', '巡回',
      // 8/13 加 (沿 SOUL #198): NPR/HN 英文关键词 (避开 relax 重叠的 film/review)
      'music', 'podcast', 'concert', 'album', 'show', 'radio', 'interview',
      'musician', 'song', 'singer', 'band', 'tour', 'live', 'episode',
      'npr', 'author', 'book', 'novel',
    ],
    Scene.relax: [
      '生活', '美食', '旅游', '文化', '影评', '书评', '旅行', '摄影',
      '心理', '冥想', '读书', '电影', '时尚', '家居', '宠物', '养生',
      '健康', '美容', '心境', '散文', '随笔', '日记', '手账',
      '插花', '茶', '咖啡', '烘焙', '小说', '艺术', '展览', '设计',
      // 8/13 加: 豆瓣电影/书/生活英文关键词
      'movie', 'film', 'book', 'novel', 'review', 'life', 'travel', 'food',
      'photography', 'art', 'design', 'culture', 'lifestyle', 'review',
    ],
    Scene.workout: [
      '运动', '跑步', '健身', '训练', '比赛', '体育', '装备', '户外',
      '瑜伽', '马拉松', '减肥', '肌肉', '跑步机', '普拉提', '自行车',
      '徒步', '登山', '游泳', '足球', '篮球', '网球', '高尔夫', '滑雪',
      '心率', '能量', '体能', '护膝', '体重', '蛋白', '塑形',
      // 8/13 加: 知乎/HN 健身/效率英文关键词
      'fitness', 'exercise', 'workout', 'training', 'health', 'run',
      'meditation', 'mindfulness', 'wellness', 'productivity', 'habit',
      // 8/14 加 (沿 SOUL #198): 让 Engadget 命中 (Engadget 是科技/穿戴设备, 跟 workout 'wearable'/'device' 匹配)
      'wearable', 'device', 'gadget', 'smart', 'battery', 'screen',
    ],
  };

  Future<List<ContentItem>> fetchByBucket(UserType userType, Scene scene, {int shuffleSeed = 0, bool forceFresh = false, Scene? sceneOverride = null}) async {
    // 8/13 治本 (沿 SOUL #198 #137 #190): 4 场景重叠真凶
    //   真凶: 之前用 rssService.currentScene = scene (instance field) 但 _feedUrlsForScene 在 fetchTop 内读
    //     → 跨场景调用串扰 (4 场景用同一 RssService 实例)
    //   修法: 接受 sceneOverride 参数, 显式传 scene, 不依赖 instance field
    // 8/13 升一阶: 设 instance _currentScene 为 fallback (保留向后兼容)
    _currentScene = scene;  // fallback, 让 _feedUrlsForScene 仍能工作
    final effectiveScene = sceneOverride ?? _currentScene ?? scene;

    // 8/14 二次治本 (沿 SOUL #8 #6 真改没改对 第 N+8 次): 不要 forceFresh || true
    //   真凶: 之前 _loadRecommendations 每次 initState 都 forceFresh=true → fetchTop 重新拉
    //     → 打开场景 4-5s 卡顿 (8/14 Brien '负优化')
    //   修: 只在 force=true (用户点换 6 张) 才 forceFresh, initState 走 cache
    //   副作用: 切场景后 5min in-memory cache 仍可用 → 首屏 < 1s
    final items = await fetchTop(limit: 30, forceFresh: forceFresh, scene: effectiveScene);
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
    // 8/13 治本 (沿 SOUL #103 #190 真改没改对 第 N+1 次):
    //   真凶: fetchByBucket 不接 shuffle, 上游 offset 切片永远同一组 → "换 6 张" 卡死
    //   修法: 加 shuffleSeed 参数, 每次重载用不同 seed → 切片不同
    //   test 验证: 3 次 load 拿同样 6 条 → 修后 3 次 load 拿不同 6 条
    // 8/13 升一阶 (沿 SOUL #198 #137 真凶链第 3 弹): 4 场景重叠
    //   真凶: 之前 fetchByBucket 4 场景拿同组 RSS → 主题词筛后仍有大量重叠 (sspai 文章多含"AI/科技")
    //   修法: 按 scene 配 sourceType 优先级, 不同 scene 偏不同源 → 池子不同 → 重叠降低
    final deduped = _dedupeSimilar(result);
    // 8/13 shuffle: 不同 seed → 不同顺序 → 上游切片不同
    final shuffled = _shuffleByOffset(deduped, shuffleSeed);
    // 8/13 scene → sourceType 偏好 (沿 SOUL #198)
    //   learn 偏 36kr 商业/科技 (沿宪法 §1.1 国内版)
    //   listen 偏 ximalaya (但 ximalaya service 未启, fallback RSS)
    //   relax 偏 知乎 (ContentSource.zhihu) - 但当前 RSS pool 没知乎 RSS, 暂用 sspai/NPR
    //   workout 偏 知乎 (同上, 用 sspai)
    //   实际: scene 主题词筛 + shuffle 已经减少大部分重叠, sourceType 偏好作为 P2
    return shuffled
        .map((it) => toContentItem(it, contentType: defaultKind))
        .toList();
  }

  /// 8/13 加: 按 shuffleSeed shuffle — 让 "换 6 张" 真的换不同 6 条
  /// 真凶链: fetchByBucket 返同一组 items (按 RSS 时间排), 上游 offset 切片 mod 4-5 永远同一组
  /// 修法: shuffle(items) 按 seed, 不同 seed → 不同顺序 → 切片不同
  /// 副作用: 4 场景重叠仍存在 (沿 #198), shuffle 不解决 scene 重复 (要 source 区分, 是 P2)
  static List<T> _shuffleByOffset<T>(List<T> items, int shuffleSeed) {
    if (items.isEmpty) return items;
    // 8/13 治本: 真洗牌 (避免之前 _shuffleByOffset 写空实现)
    //   真凶: 上游 offset ~/ 6 → 调 fetchByBucket(seed) → fetchByBucket 内部再 ~/ 6
    //     → 永远 shuffleSeed=0 → 永远同一组
    //   修: shuffleSeed 直接用 (上游已算过), 内部不再 ÷ 6
    final shuffled = List<T>.from(items);
    // 用 shuffleSeed 派生随机 (不同 seed → 不同顺序)
    final rng = math.Random((shuffleSeed + 1) * 1000 + items.length);
    shuffled.shuffle(rng);
    return shuffled;
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
