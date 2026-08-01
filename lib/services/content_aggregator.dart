import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'ximalaya_service.dart';
import 'news_service.dart';
import 'international_service.dart';

class ContentAggregator {
  final XimalayaService ximalaya;
  final NewsService news;
  final InternationalService international;

  ContentAggregator({
    XimalayaService? ximalaya,
    NewsService? news,
    InternationalService? international,
  })  : ximalaya = ximalaya ?? XimalayaService(),
        news = news ?? NewsService(),
        international = international ?? InternationalService();

  Future<List<ContentItem>> fetchRecommendContent({
    required UserType userType,
    required Scene scene,
    bool isInternational = false,
  }) async {
    try {
      // 7/29 重构: 只走真 RSS (36 氪 / 少数派 / The Verge), 拉空返 []
      // 之前的 fallback _allContent 假数据已移除 — 上线后访客应看真内容
      // _allContent 保留仅供 dev 演示 (news._fetchFakeForDev)
      final rssResults = await news.fetchFromRss(userType, scene, isInternational: isInternational);
      if (rssResults.isNotEmpty) {
        return rssResults;
      }
      // RSS 拉空 -> 返 [] (UI 走空状态)
      return [];
    } catch (e) {
      debugPrint('ContentAggregator error: $e');
      return [];
    }
  }

  Future<List<ContentItem>> searchContent(String query, {bool isInternational = false}) async {
    try {
      if (isInternational) {
        return await international.search(query);
      } else {
        final results = <ContentItem>[];
        final ximalayaResults = await ximalaya.search(query);
        final newsResults = await news.search(query);
        results.addAll(ximalayaResults.cast<ContentItem>());
        results.addAll(newsResults);
        return results;
      }
    } catch (e) {
      debugPrint('ContentAggregator search error: $e');
      return [];
    }
  }

  // 7/30: 按 ContentSource 取所有匹配 item (tab-收藏 → 点平台跳详情用)
  // 沿用 24 桶假数据 (点 36 氪 / B站等能看到现有假内容先, 不接真 RSS 避免 #103 #117 CORS 撞坑)
  Future<List<ContentItem>> fetchBySource(ContentSource source) async {
    try {
      return await news.fetchAllBySource(source);
    } catch (e) {
      debugPrint('[aggregator] fetchBySource error: $e');
      return [];
    }
  }
}
