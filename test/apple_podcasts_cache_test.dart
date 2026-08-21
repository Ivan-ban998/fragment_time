// ignore_for_file: avoid_print
// 8/28 P42-2 沿 SOUL #189: ApplePodcastsService cache 单元测试
//   验证 P41-5 10min in-memory cache (topCharts/search)
// 跑法: flutter test test/apple_podcasts_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/apple_podcasts_service.dart';

void main() {
  test('ApplePodcastsService cache hits/misses 初始为 0', () {
    expect(ApplePodcastsService.topChartsCacheHits, 0);
    expect(ApplePodcastsService.topChartsCacheMisses, 0);
    expect(ApplePodcastsService.searchCacheHits, 0);
    expect(ApplePodcastsService.searchCacheMisses, 0);
  });

  test('topCharts cache hit (网络可达时)', () async {
    final service = ApplePodcastsService();
    final podcasts = await service.topCharts(country: 'us', limit: 3);
    print('topCharts(us, 3) 返 ${podcasts.length}');
    if (podcasts.isEmpty) {
      print('⚠️ 网络不通, 跳过 cache 验证');
      return;
    }
    // 第一次: miss, 第二次: hit
    final firstMisses = ApplePodcastsService.topChartsCacheMisses;
    final firstHits = ApplePodcastsService.topChartsCacheHits;
    await service.topCharts(country: 'us', limit: 3);
    final secondMisses = ApplePodcastsService.topChartsCacheMisses;
    final secondHits = ApplePodcastsService.topChartsCacheHits;
    print('1st: miss=$firstMisses hit=$firstHits → 2nd: miss=$secondMisses hit=$secondHits');
    expect(secondHits, greaterThan(firstHits),
        reason: '2nd call 应 hit cache, 增加 hits');
    expect(secondMisses, firstMisses,
        reason: '2nd call 不应增加 miss (cache hit)');
  }, timeout: const Timeout(Duration(seconds: 30)));
}