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
    int offset = 0, // 8/1 加 (沿用 #103): 让 '换 6 张' 真换不同 6 条 (Step 2 覆盖 Step 1 时保持 offset 一致)
    bool forceFresh = false, // 8/14 加 (沿 SOUL #190 真改没改对 第 N+5 次): 透传到 NewsService.getRecommendations
                          //   真凶: 之前 Step 2 不传 forceFresh, "换 6 张" force=true → Step 1 真换 → Step 2 cache 命中返老卡覆盖
                          //   修: Step 2 跟 Step 1 一样 forceFresh=force
    Set<String> excludeIds = const {}, // 8/14 加: 透传已 dismiss 的 item
  }) async {
    try {
      // 7/29 重构: 只走真 RSS (36 氪 / 少数派 / The Verge), 拉空返 []
      // 8/13 升一阶 (沿 SOUL #119): 真 RSS 不足 6 → NewsService 兑底精选到 6 (避免 tinder 半空)
      //   实际逻辑都在 NewsService.getRecommendations 内部, 这里直接复用
      // 8/13 修: 透传 isInternational 让国际版走 The Verge+NPR (国内走 sspai+NPR+36kr)
      // 8/14 治本 (沿 SOUL #190 #103 真改没改对 第 N+6 次): 透传 forceFresh + excludeIds
      //   真凶: 之前 Step 2 不传 forceFresh, 5min cache 命中 → "换 6 张" 老卡覆盖 Step 1 新卡
      //   修: Step 2 跟 Step 1 一样 forceFresh=force + excludeIds 一致
      final result = await NewsService().getRecommendations(
        userType, scene,
        offset: offset,
        isInternational: isInternational,
        forceFresh: forceFresh,
        excludeIds: excludeIds,
      );
      return result;
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
