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
      // 7/14 加: 优先 RSS (国内 36 氪 / 国际 The Verge), 失败 fallback 假数据
      // 走宪法 §1.1: 只接 metadata, 不存原片
      final rssResults = await news.fetchFromRss(userType, scene, isInternational: isInternational);
      if (rssResults.isNotEmpty) {
        return rssResults;
      }
      // RSS 拉空 -> 老逻辑 (硬编码假数据)
      if (isInternational) {
        return await international.getRecommendations(userType, scene);
      } else {
        final newsResults = await news.getRecommendations(userType, scene);
        return newsResults;
      }
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
}
