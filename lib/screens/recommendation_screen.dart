// 8/28 P64 沿 SOUL #137 真凶链 + 用户"虽然换平台, 但还得自己去搜内容"治本:
//   真凶: 之前 P63-A 把 ximalaya 链接换成 Apple Podcasts/知乎/B站 搜索 URL
//     → 用户点卡片 → 跳平台搜索页 → 还得自己手动搜 → 等于没解决问题
//   修: 创建 RecommendationScreen, 点 chip → App 内直接拉 Apple Podcasts/RSS 真 API
//     → 显示有效推荐列表 (image + title + author + 真 episode URL)
//   8/28 P64 沿 SOUL #169 不撒谎 + SOUL #103 治好不抢注意力:
//     列表 3-8 条真内容, 一键直达 Apple Podcasts episode / RSS article, 不需要用户再搜
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/rss_service.dart';
import '../services/apple_podcasts_service.dart';
import 'in_app_webview_screen.dart';

/// 8/28 P64: 有效推荐屏 (沿 SOUL #137 治本)
///   用户点 AI 卡片 chip → 跳这里 → 显示 App 内拉的有效推荐列表
///   取代之前跳平台搜索页的假跳转
class RecommendationScreen extends StatefulWidget {
  /// chip 标题 (e.g. "BBC 英语")
  final String title;
  /// chip 类型 (audio/video/article/card) - 沿 P52
  final String contentType;
  /// 真搜索词 (e.g. "BBC 6 Minute English") - 调 Apple Podcasts / RSS API
  final String searchKeyword;
  /// 源类型 - apple_podcasts / rss
  final RecommendationSource source;
  /// 可选 language
  final bool isEn;

  const RecommendationScreen({
    super.key,
    required this.title,
    required this.contentType,
    required this.searchKeyword,
    required this.source,
    this.isEn = false,
  });

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

enum RecommendationSource {
  applePodcasts, // 走 Apple Podcasts iTunes API
  rssTop, // 走 RSS fetchTop (按 userType + scene)
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  late Future<List<_RecommendationItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRecommendations();
  }

  /// 8/28 P64: 调对应源 API 拉有效推荐
  Future<List<_RecommendationItem>> _loadRecommendations() async {
    switch (widget.source) {
      case RecommendationSource.applePodcasts:
        return _loadFromApplePodcasts();
      case RecommendationSource.rssTop:
        return _loadFromRss();
    }
  }

  /// 8/28 P64: Apple Podcasts search → 转 _RecommendationItem
  Future<List<_RecommendationItem>> _loadFromApplePodcasts() async {
    try {
      final aps = ApplePodcastsService();
      // 8 字节国家限制 us 搜英文, cn 搜中文 (沿宪法 #1.1 调原站, 不缓存 episode 内容)
      final country = _isChinese(widget.searchKeyword) ? 'cn' : 'us';
      final results = await aps.search(widget.searchKeyword, country: country, limit: 8);
      return results.map((p) {
        return _RecommendationItem(
          title: p.name,
          subtitle: p.artistName,
          imageUrl: p.artworkUrl,
          url: p.url, // itunes.apple.com/.../id{id} (宪法 §1.1)
          source: 'Apple Podcasts',
          type: 'audio',
        );
      }).toList();
    } catch (e) {
      debugPrint('[recommendation_] apple search err: $e');
      return [];
    }
  }

  /// 8/28 P64: RSS fetchTop → 转 _RecommendationItem (按 content type 选)
  Future<List<_RecommendationItem>> _loadFromRss() async {
    try {
      final rss = RssService();
      // 8 字节 P64: 根据 contentType 选 scene
      final scene = _sceneForContentType(widget.contentType);
      final items = await rss.fetchTop(limit: 12, scene: scene);
      // 8 字节 P64: 过滤匹配 searchKeyword (title 包含 keyword)
      final kw = widget.searchKeyword.toLowerCase();
      final matched = items.where((it) =>
        it.title.toLowerCase().contains(kw) ||
        it.description.toLowerCase().contains(kw)
      ).toList();
      // 8 字节 P64: 不足补足到 5+ (取 fetchTop 剩下的)
      final fallback = items.where((it) => !matched.contains(it)).take(5);
      final result = [...matched, ...fallback].take(8);
      return result.map((it) {
        return _RecommendationItem(
          title: it.title,
          subtitle: it.sourceName,
          imageUrl: null,
          url: it.url,
          source: it.sourceName,
          type: 'article',
        );
      }).toList();
    } catch (e) {
      debugPrint('[recommendation_] rss err: $e');
      return [];
    }
  }

  /// 8 字节 P64: contentType → scene 映射
  Scene? _sceneForContentType(String ct) {
    switch (ct) {
      case 'audio': return Scene.listen;
      case 'video': return Scene.workout;
      case 'article': return Scene.learn;
      case 'card': return Scene.learn;
      default: return Scene.learn;
    }
  }

  /// 8 字节 P64: 检测中文 keyword (优先 cn 国家搜 Apple Podcasts)
  bool _isChinese(String s) {
    return RegExp(r'[一-龥]').hasMatch(s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _future = _loadRecommendations();
            }),
          ),
        ],
      ),
      body: FutureBuilder<List<_RecommendationItem>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      widget.isEn
                          ? 'No recommendations for "${widget.searchKeyword}"'
                          : '"${widget.searchKeyword}" 暂无推荐',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _RecommendationCard(
              item: items[i],
              isEn: widget.isEn,
            ),
          );
        },
      ),
    );
  }
}

/// 8/28 P64: 单条推荐 card (image + title + author + tap 跳真 URL)
class _RecommendationCard extends StatelessWidget {
  final _RecommendationItem item;
  final bool isEn;
  const _RecommendationCard({required this.item, required this.isEn});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // 8/28 P64: 跳 in-app webview (沿 #1.1 宪法: 不缓存 episode 内容)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InAppWebViewScreen(
                url: item.url,
                title: item.title,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 封面图 (60x60)
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.music_note, color: Colors.grey[400]),
                        ),
                      )
                    : Icon(
                        item.type == 'audio' ? Icons.headphones
                        : item.type == 'video' ? Icons.play_circle_outline
                        : Icons.article,
                        color: Colors.grey[400],
                      ),
              ),
              const SizedBox(width: 12),
              // 标题 + 副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.source, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          item.source,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/// 8/28 P64: 内部 model (不依赖 ContentItem, 因为 RSS/Apple Podcasts 是不同 source)
class _RecommendationItem {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String url;
  final String source;
  final String type;

  _RecommendationItem({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.source,
    required this.type,
    this.imageUrl,
  });
}