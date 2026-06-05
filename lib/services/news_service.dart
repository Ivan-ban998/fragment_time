import 'package:flutter/foundation.dart';
import '../models/models.dart';

class NewsService {
  Future<List<ContentItem>> getRecommendations(UserType userType, Scene scene) async {
    // Mock 数据：8 条假新闻
    return [
      ContentItem(
        id: 'news_1',
        title: '2026 年 AI 大模型发展回顾：从 GPT-5 到 Claude 4',
        description: '今年主流大模型的性能对比和未来趋势分析',
        source: '36kr',
        sourceIcon: '📰',
        sourceType: ContentSourceType.news36kr,
        externalUrl: 'https://36kr.com/p/123456',
        priceType: PriceType.free,
      ),
      ContentItem(
        id: 'news_2',
        title: 'MiniMax M3 发布：1M 上下文 + MSA 注意力架构',
        description: '国产模型的重大突破',
        source: '36kr',
        sourceIcon: '📰',
        sourceType: ContentSourceType.news36kr,
        externalUrl: 'https://36kr.com/p/234567',
        priceType: PriceType.free,
      ),
      ContentItem(
        id: 'zhihu_1',
        title: '如何高效利用碎片时间学习？',
        description: '10 个科学的时间管理方法',
        source: 'zhihu',
        sourceIcon: '💡',
        sourceType: ContentSourceType.zhihu,
        externalUrl: 'https://zhuanlan.zhihu.com/p/123456',
        priceType: PriceType.free,
      ),
      ContentItem(
        id: 'zhihu_2',
        title: '通勤路上听什么节目最好？',
        description: '推荐 5 个高质量音频内容',
        source: 'zhihu',
        sourceIcon: '💡',
        sourceType: ContentSourceType.zhihu,
        externalUrl: 'https://zhuanlan.zhihu.com/p/234567',
        priceType: PriceType.free,
      ),
      ContentItem(
        id: 'news_3',
        title: '播客市场 2026：增长 50%',
        description: '音频内容迎来第二春',
        source: '36kr',
        sourceIcon: '📰',
        sourceType: ContentSourceType.news36kr,
        externalUrl: 'https://36kr.com/p/345678',
        priceType: PriceType.free,
      ),
      ContentItem(
        id: 'zhihu_3',
        title: 'Flutter 3.24 性能优化实战',
        description: 'Web 端首屏加速 50%',
        source: 'zhihu',
        sourceIcon: '💡',
        sourceType: ContentSourceType.zhihu,
        externalUrl: 'https://zhuanlan.zhihu.com/p/345678',
        priceType: PriceType.freemium,
        priceNote: '会员可看完整版',
      ),
      ContentItem(
        id: 'news_4',
        title: 'OpenClaw 本地 AI 助理爆火',
        description: 'DIY 智能助理的开源革命',
        source: '36kr',
        sourceIcon: '📰',
        sourceType: ContentSourceType.news36kr,
        externalUrl: 'https://36kr.com/p/456789',
        priceType: PriceType.free,
      ),
      ContentItem(
        id: 'zhihu_4',
        title: '每天 15 分钟，能学会什么？',
        description: '微学习时代的认知科学',
        source: 'zhihu',
        sourceIcon: '💡',
        sourceType: ContentSourceType.zhihu,
        externalUrl: 'https://zhuanlan.zhihu.com/p/456789',
        priceType: PriceType.free,
      ),
    ];
  }

  Future<List<ContentItem>> search(String query) async {
    // Mock 搜索：返回过滤结果
    final all = await getRecommendations(UserType.student, Scene.learn);
    if (query.isEmpty) return all;
    return all.where((item) =>
      item.title.toLowerCase().contains(query.toLowerCase()) ||
      (item.description?.toLowerCase().contains(query.toLowerCase()) ?? false)
    ).toList();
  }
}
