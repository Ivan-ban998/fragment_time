import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  static const String _sourcesKey = 'subscribed_sources';
  static const String _categoriesKey = 'subscribed_categories';

  // 6/7 立：宪法 §3 假数据可上线，但平台/类目订阅必须持久化（用户基本设置）
  // 6/8 修复：从 8 个补到 12 个（跟 UI chip 列表对齐，补了 心理/音乐/体育/冥想/编程/理财）
  // 注：用户首次装 app 默认订阅哪 8 个 仍然存 here，但 allCategories 是【完整 12】
  static const List<String> defaultCategories = [
    '职场技能',
    '英语学习',
    '科技资讯',
    '历史故事',
    '理财知识',
    '健康养生',
    '亲子教育',
    '音乐有声',
  ];

  // 6/8 修复：allCategories 提上来与 UI 共享，避免两边漂移
  // 所有可选 12 个类目（中英双语），顺序与 UI chip 顺序一致
  static const List<String> allCategoriesZh = [
    '职场技能', '英语学习', '科技资讯', '历史故事',
    '心理成长', '理财知识', '健康养生', '亲子教育',
    '音乐有声', '体育健身', '冥想放松', '编程开发',
  ];
  static const List<String> allCategoriesEn = [
    'Career skills', 'English', 'Tech news', 'History',
    'Psychology', 'Finance', 'Health', 'Parenting',
    'Music & audio', 'Fitness', 'Meditation', 'Programming',
  ];

  // 业务逻辑使用：中文 key（跟 SharedPreferences 存的字符串一致）
  static const List<String> allCategories = allCategoriesZh;

  /// 6/8 修复：取双语列表（UI 使用）
  static List<String> getAllCategories({required bool isEn}) {
    return isEn ? allCategoriesEn : allCategoriesZh;
  }

  static const List<ContentSource> defaultSources = [
    ContentSource.ximalaya,
    ContentSource.news36kr,
  ];

  // 所有可选平台
  static const List<ContentSource> allSources = [
    ContentSource.ximalaya,
    ContentSource.lizhiFM,
    ContentSource.news36kr,
    ContentSource.zhihu,
    ContentSource.bilibili,
    ContentSource.applePodcasts,
    ContentSource.spotify,
    ContentSource.youtube,
    ContentSource.rss,
  ];

  Future<Set<ContentSource>> getSubscribedSources() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_sourcesKey);
    if (list == null) {
      return defaultSources.toSet();
    }
    return list
        .map((n) => ContentSource.values.firstWhere(
              (s) => s.name == n,
              orElse: () => ContentSource.ximalaya,
            ))
        .toSet();
  }

  Future<Set<String>> getSubscribedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_categoriesKey);
    if (list == null) {
      return defaultCategories.toSet();
    }
    return list.toSet();
  }

  Future<void> subscribeSource(ContentSource source) async {
    final current = await getSubscribedSources();
    current.add(source);
    await _saveSources(current);
  }

  Future<void> unsubscribeSource(ContentSource source) async {
    final current = await getSubscribedSources();
    current.remove(source);
    await _saveSources(current);
  }

  Future<void> subscribeCategory(String category) async {
    final current = await getSubscribedCategories();
    current.add(category);
    await _saveCategories(current);
  }

  Future<void> unsubscribeCategory(String category) async {
    final current = await getSubscribedCategories();
    current.remove(category);
    await _saveCategories(current);
  }

  Future<void> _saveSources(Set<ContentSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _sourcesKey,
      sources.map((s) => s.name).toList(),
    );
  }

  Future<void> _saveCategories(Set<String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_categoriesKey, categories.toList());
  }

  Future<List<ContentItem>> fetchSubscribedContent() async {
    final sources = await getSubscribedSources();
    final List<ContentItem> allContent = [];

    for (final source in sources) {
      try {
        final items = _getSampleContent(source);
        allContent.addAll(items);
      } catch (_) {}
    }

    return allContent;
  }

  List<ContentItem> _getSampleContent(ContentSource source) {
    switch (source) {
      case ContentSource.ximalaya:
        return [
          ContentItem(
            id: 'sub_ximalaya_1',
            title: '职场晋升笔记',
            description: '职场晋升路上的思考与复盘',
            duration: '45集',
            source: '喜马拉雅',
            sourceType: ContentSource.ximalaya,
            contentType: ContentType.audio,
            priceType: ContentPriceType.free,
          ),
          ContentItem(
            id: 'sub_ximalaya_2',
            title: '商业财经内参',
            description: '每天5分钟，掌握商业动态',
            duration: '365集',
            source: '喜马拉雅',
            sourceType: ContentSource.ximalaya,
            contentType: ContentType.audio,
            priceType: ContentPriceType.membership,
            priceNote: '喜马拉雅会员免费',
          ),
          ContentItem(
            id: 'sub_ximalaya_3',
            title: '老炮儿创业故事',
            description: '真实创业者的血泪史',
            duration: '20集',
            source: '喜马拉雅',
            sourceType: ContentSource.ximalaya,
            contentType: ContentType.audio,
            priceType: ContentPriceType.paid,
            priceNote: '¥99',
          ),
        ];

      case ContentSource.news36kr:
        return [
          ContentItem(
            id: 'sub_36kr_1',
            title: 'AI 大模型如何重塑内容创作行业',
            description: '从写作到视频，AI 正在改变内容生产的方式...',
            duration: '2小时前',
            source: '36氪',
            sourceType: ContentSource.news36kr,
            contentType: ContentType.card,
            priceType: ContentPriceType.free,
          ),
          ContentItem(
            id: 'sub_36kr_2',
            title: '2024年最值得关注的科技趋势',
            description: '从量子计算到脑机接口，这些技术将改变我们的生活...',
            duration: '昨天',
            source: '36氪',
            sourceType: ContentSource.news36kr,
            contentType: ContentType.card,
            priceType: ContentPriceType.free,
          ),
        ];

      case ContentSource.lizhiFM:
        return [
          ContentItem(
            id: 'sub_lizhi_1',
            title: '科技创业故事',
            description: '创业者的真实故事',
            duration: '80集',
            source: '荔枝FM',
            sourceType: ContentSource.lizhiFM,
            contentType: ContentType.audio,
            priceType: ContentPriceType.free,
          ),
          ContentItem(
            id: 'sub_lizhi_2',
            title: '深夜电台',
            description: '城市夜归人的心灵港湾',
            duration: '200集',
            source: '荔枝FM',
            sourceType: ContentSource.lizhiFM,
            contentType: ContentType.audio,
            priceType: ContentPriceType.membership,
            priceNote: '会员专享',
          ),
        ];

      case ContentSource.zhihu:
        return [
          ContentItem(
            id: 'sub_zhihu_1',
            title: '有哪些越早知道越好的职场道理？',
            description: '职场生存指南',
            duration: '知乎',
            source: '知乎',
            sourceType: ContentSource.zhihu,
            contentType: ContentType.article,
            priceType: ContentPriceType.free,
          ),
          ContentItem(
            id: 'sub_zhihu_2',
            title: '知乎盐选年度精选',
            description: '高质量深度内容合集',
            duration: '50篇',
            source: '知乎',
            sourceType: ContentSource.zhihu,
            contentType: ContentType.article,
            priceType: ContentPriceType.membership,
            priceNote: '盐选会员免费读',
          ),
        ];

      case ContentSource.bilibili:
        return [
          // 6/7 §1: B 站 BV ID 是示例 stub，实际可能无效
          // 6/11 B1：移除假 BV ID，改用 B 站搜索页（永远不死）
          // videoId=null 走 fallback (buildVideoEmbedUrl) → externalUrl 跳 B 站搜索
          ContentItem(
            id: 'sub_bili_1',
            title: 'B 站知识区热搜',
            description: '点击跳 B 站知识区搜索页，看当天热门',
            duration: '10-15min',
            source: 'B站',
            sourceType: ContentSource.bilibili,
            contentType: ContentType.video,
            videoId: null,
            videoPlatform: null,
            externalUrl: 'https://search.bilibili.com/all?keyword=%E7%9F%A5%E8%AF%86',
            priceType: ContentPriceType.free,
          ),
        ];

      case ContentSource.applePodcasts:
        return [
          ContentItem(
            id: 'sub_apple_1',
            title: 'The Daily',
            description: 'NYT 每日新闻深度报道',
            duration: '20min',
            source: 'Apple Podcasts',
            sourceType: ContentSource.applePodcasts,
            contentType: ContentType.audio,
            priceType: ContentPriceType.free,
          ),
        ];

      case ContentSource.spotify:
        return [
          ContentItem(
            id: 'sub_spotify_1',
            title: 'Lex Fridman Podcast',
            description: 'AI 研究者深度对话',
            duration: '3h',
            source: 'Spotify',
            sourceType: ContentSource.spotify,
            contentType: ContentType.audio,
            priceType: ContentPriceType.membership,
            priceNote: 'Premium 专享',
          ),
        ];

      case ContentSource.youtube:
        return [
          ContentItem(
            id: 'sub_yt_1',
            title: 'Khan Academy - Human Anatomy',
            description: 'Anatomy basics, 12 min intro',
            duration: '12min',
            source: 'YouTube',
            sourceType: ContentSource.youtube,
            contentType: ContentType.video,
            videoId: '8jLOx1hD3_o',
            videoPlatform: VideoPlatform.youtube,
            priceType: ContentPriceType.free,
          ),
          ContentItem(
            id: 'sub_yt_2',
            title: 'freeCodeCamp - Python Tutorial',
            description: 'Learn Python in 4 hours',
            duration: '4h',
            source: 'YouTube',
            sourceType: ContentSource.youtube,
            contentType: ContentType.video,
            videoId: 'rfscVS0vtbw',
            videoPlatform: VideoPlatform.youtube,
            priceType: ContentPriceType.free,
          ),
        ];

      case ContentSource.rss:
        return [
          ContentItem(
            id: 'sub_rss_1',
            title: '少数派',
            description: '数字生活方式指南',
            duration: '每日',
            source: 'RSS',
            sourceType: ContentSource.rss,
            contentType: ContentType.article,
            priceType: ContentPriceType.free,
          ),
        ];
    }
  }
}
