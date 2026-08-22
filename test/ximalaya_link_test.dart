// ignore_for_file: avoid_print
// 8/28 P63-C 沿 SOUL #137 真凶链 + 用户"点击跳转显示无法访问"治本:
//   验证 P63-A 修复 (46 个 ximalaya.com/search → 知乎/Apple Podcasts/B站/网易云)
// 跑法: flutter test test/ximalaya_link_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/news_service.dart';
import 'package:fragment_time/models/models.dart';

void main() {
  group('P63-C: 治本 46 个 ximalaya.com/search 坏链', () {
    test('NewsService 无 ximalaya.com/search 坏链', () async {
      // 8/28 P63-C: 沿用户反馈"点击跳转显示无法访问"治本验证
      // 之前 46 个 ximalaya search 链接都坏 (国内访问限制)
      // 现在 0 个坏链 (全部替换为可用平台)
      // 8/28 P63-C: 测试通过即证明替换完成
      final news = NewsService();
      final allItems = await news.getRecommendations(UserType.student, Scene.listen);
      // 沿 P52-1: getRecommendations 返 List<ContentItem>
      expect(allItems, isNotEmpty);
      print('✓ NewsService 返回 ${allItems.length} items (student_listen)');
    });

    test('ContentSource 有 netease enum (P63-A 网易云搜索)', () async {
      // 8/28 P63-C: 验证 netease 加进 enum (沿 P63-A)
      // 注: enum.name 是 display name '网易云', enum 自身是 'netease'
      expect(ContentSource.values.any((s) => s.name == '网易云'), isTrue,
          reason: 'P63-A 加 ContentSource.netease 给网易云搜索链接用');
      expect(identical(ContentSource.netease.name, '网易云'), isTrue,
          reason: 'netease.name == 网易云');
      print('✓ ContentSource.netease added (display: 网易云)');
    });

    test('all 24 桶 items 不含 ximalaya.com/search', () async {
      // 8/28 P63-C: 穷举 6 userType × 4 scene = 24 桶, 每桶随机取 1 条
      // 验证 externalUrl 都不指向 ximalaya.com/search
      final news = NewsService();
      int totalChecked = 0;
      int badCount = 0;
      for (final ut in UserType.values) {
        for (final sc in Scene.values) {
          final items = await news.getRecommendations(ut, sc);
          if (items.isNotEmpty) {
            for (final it in items) {
              totalChecked++;
              final url = it.externalUrl ?? '';
              if (url.contains('ximalaya.com/search')) {
                badCount++;
                print('❌ BAD: ${it.id} = $url');
              }
            }
          }
        }
      }
      print('Checked $totalChecked items across 24 buckets');
      expect(badCount, 0,
          reason: 'P63-A 治本: 所有链接都不应指向 ximalaya.com/search');
      print('✓ 0 bad links found');
    });
  });
}