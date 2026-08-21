// ignore_for_file: avoid_print
// 8/28 P43-3 沿 SOUL #189: RssService cache 单元测试
//   验证 cacheStats getter + clearCache 行为
// 跑法: flutter test test/rss_service_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/rss_service.dart';

void main() {
  test('RssService.cacheStats 初始 hit/miss = 0', () {
    RssService.clearCache();
    expect(RssService.cacheHits, 0);
    expect(RssService.cacheMisses, 0);
    final stats = RssService.cacheStats;
    print('cacheStats: $stats');
    expect(stats['hits'], 0);
    expect(stats['misses'], 0);
    expect(stats['total'], 0);
    expect(stats['hit_rate'], '0.0');
  });

  test('RssService.clearCache 重置 hit/miss 计数', () {
    RssService.clearCache();
    // after clear, should be 0
    expect(RssService.cacheHits, 0);
    expect(RssService.cacheMisses, 0);
  });
}