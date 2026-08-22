// ignore_for_file: avoid_print
// 8/28 P53-3 沿 SOUL #189: RssItem.qualityScore 单元测试
//   验证 P53-3 评分算法 (freshness 40% + popularity 30% + title_length 30%)
// 跑法: flutter test test/rss_quality_score_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/rss_service.dart';

RssItem _item({
  required String title,
  required String sourceName,
  Duration age = const Duration(hours: 1),
}) {
  return RssItem(
    title: title,
    url: 'https://example.com/${title.hashCode}',
    description: 'desc',
    pubDate: DateTime.now().subtract(age),
    sourceName: sourceName,
  );
}

void main() {
  test('qualityScore 新鲜 1h + sspai 标题 15字 → 高分', () {
    final item = _item(title: '新出的 sspai 文章 15字', sourceName: 'sspai');
    final score = item.qualityScore;
    print('sspai/1h/15字 → $score');
    // freshness 40 (1h) + popularity 30 (sspai) + title 30 (15字) = 100
    expect(score, greaterThanOrEqualTo(95),
        reason: '1h fresh + hot source + good title 应 ~100');
  });

  test('qualityScore 168h 旧 + 冷门源 + 长标题 → 低分', () {
    final item = _item(
      title: '这是一篇非常长的标题超过40个中文字符的内容会有非常糟糕的标题长度评分',
      sourceName: 'unknownsource',
      age: const Duration(hours: 200),
    );
    final score = item.qualityScore;
    print('200h+ 冷门 + 长标题 → $score');
    // freshness 0 (200h clamp 168, ratio=1, 40*(1-1)=0)
    // popularity 15 (unknown source)
    // title 35 字 in (25..40] → 30 - (35-25)*2 = 10
    // total: 0 + 15 + 10 = 25
    expect(score, lessThanOrEqualTo(30));
  });

  test('qualityScore 24h + bilibili + 10字 → 中等分', () {
    final item = _item(
      title: 'bilibili 推荐',
      sourceName: 'bilibili',
      age: const Duration(hours: 24),
    );
    final score = item.qualityScore;
    print('24h/bilibili/10字 → $score');
    // freshness: 40 * (1 - 24/168) = 40 * 0.857 ≈ 34
    // popularity: 30 (bilibili 在 hot_sources)
    // title 6 字 < 8 → 6 * 30 / 8 = 22
    // total: 34 + 30 + 22 = 86
    expect(score, greaterThanOrEqualTo(80));
  });

  test('isQualityFresh score >= 60 + 7 天内', () {
    final freshItem = _item(
      title: 'Fresh Article',
      sourceName: 'sspai',
      age: const Duration(days: 3),
    );
    expect(freshItem.isQualityFresh, true,
        reason: '3 天 + 高分 应 isQualityFresh=true');

    final oldItem = _item(
      title: 'Old Article',
      sourceName: 'sspai',
      age: const Duration(days: 30),
    );
    expect(oldItem.isQualityFresh, false,
        reason: '30 天 + 应 isQualityFresh=false (即使 source 热门)');
  });

  test('qualityScore 排序: 新鲜 > 旧, 热门 > 冷门', () {
    final fresh = _item(title: 'New sspai', sourceName: 'sspai');
    final stale = _item(
      title: 'New sspai',
      sourceName: 'sspai',
      age: const Duration(days: 14),
    );
    expect(fresh.qualityScore, greaterThan(stale.qualityScore),
        reason: 'fresh > stale (同 source 同 title)');

    final hot = _item(title: 'Title article', sourceName: '36氪');
    final cold = _item(title: 'Title article', sourceName: 'unknown');
    // 14字 → 14 * 30 / 8 = 52 ? no, 14 in (8..25) → 30
    // 13字 → 13 * 30 / 8 = 48
    // 实际 'Title article' is 13 chars → 13 < 8? no → 30
    // title = 'Title article' (13) → 30
    // hot: 40 + 30 + 30 = 100
    // cold: 40 + 15 + 30 = 85
    expect(hot.qualityScore, greaterThan(cold.qualityScore),
        reason: 'hot source > cold source');
  });

  test('qualityScore 上限 100, 下限 0', () {
    // 8/28 P53-3: 评分边界
    final superFresh = _item(
      title: 'X',  // 1 字 < 8 → 1 * 30 / 8 = 3
      sourceName: 'sspai',
      age: const Duration(minutes: 1),
    );
    // freshness 40 + popularity 30 + title 3 = 73
    print('super fresh + 1字标题 → ${superFresh.qualityScore}');
    expect(superFresh.qualityScore, lessThanOrEqualTo(100));
    expect(superFresh.qualityScore, greaterThanOrEqualTo(0));
  });
}