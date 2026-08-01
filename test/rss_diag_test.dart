// 8/2 沿用 #103 #125 真改没改对诊断测试
// 直接跑 fetchFromRss + getRecommendations 看实际返啥
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/news_service.dart';
import 'package:fragment_time/models/models.dart';

void main() {
  test('RSS 真返数据 + getRecommendations 真换 6 张', () async {
    final ns = NewsService();

    print('=== fetchFromRss ===');
    final rss = await ns.fetchFromRss(UserType.senior, Scene.learn);
    print('fetchFromRss 返 ${rss.length} 条');
    if (rss.isNotEmpty) {
      print('第一条: ${rss.first.title}');
      print('第一条 URL: ${rss.first.externalUrl}');
    }

    print('=== getRecommendations(0) ===');
    final rec0 = await ns.getRecommendations(UserType.senior, Scene.learn, offset: 0);
    print('getRecommendations(0) 返 ${rec0.length} 条');
    for (int i = 0; i < rec0.length; i++) {
      print('  [$i] ${rec0[i].title}');
    }

    print('=== getRecommendations(6) ===');
    final rec6 = await ns.getRecommendations(UserType.senior, Scene.learn, offset: 6);
    print('getRecommendations(6) 返 ${rec6.length} 条');
    for (int i = 0; i < rec6.length; i++) {
      print('  [$i] ${rec6[i].title}');
    }

    final sameSet = rec0.length == rec6.length &&
        rec0.every((r0) => rec6.any((r6) => r0.title == r6.title));
    print('=== 同样内容? $sameSet ===');
    expect(sameSet, false, reason: '换 6 张应该不返同 6 条');
  });
}
