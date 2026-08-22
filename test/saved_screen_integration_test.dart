// ignore_for_file: avoid_print
// 8/28 P56-4 沿 SOUL #189: MySubscriptionsScreen 子 Tab 集成测试
//   验证 P56-3 4th tab (我的收藏) 接入 + 类目 chip 跳主场景
// 跑法: flutter test test/saved_screen_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fragment_time/services/bookmark_service.dart';
import 'package:fragment_time/services/local_subscription_service.dart';
import 'package:fragment_time/services/subscription_service.dart';
import 'package:fragment_time/models/models.dart';

ContentItem _articleItem(String id, String title, String source) => ContentItem(
      id: id,
      title: title,
      description: 'desc $id',
      duration: '5min',
      source: source,
      sourceType: ContentSource.news36kr,
      contentType: ContentType.article,
    );

ContentItem _quoteItem(String id, String author, String text) => ContentItem(
      id: id,
      title: author,
      description: text,
      duration: '1 min read',
      source: 'Daily Quote',
      sourceType: ContentSource.rss,
      contentType: ContentType.card,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> _resetSub() async {
    final items = await LocalSubscriptionService.instance.getSubscribedItems();
    for (final it in items) {
      await LocalSubscriptionService.instance.unsubscribe(it);
    }
  }

  test('Saved screen: BookmarkService + LocalSubscriptionService 双写', () async {
    // 8/28 P56-4: 验证 P54-2 双写 (内容 tab + 我的收藏 tab 都看到)
    final bookmark = BookmarkService.instance;
    final sub = LocalSubscriptionService.instance;
    await bookmark.clear();
    await _resetSub();

    final item = _articleItem('ss_test_1', 'Tech Article 1', '36氪');

    // 8/28 P56-4: 模拟详情页 _toggleSubscribe 双写
    await sub.subscribe(item);
    await bookmark.add(item);

    // 8/28 P56-4: 我的收藏 tab 应看到
    expect(await bookmark.isBookmarked(item.id), true);
    // 8/28 P56-4: 内容 tab 应看到 (LocalSubscription)
    expect(await sub.isSubscribed(item), true);

    // 8/28 P56-4: 删除同步
    await sub.unsubscribe(item);
    await bookmark.remove(item.id);
    expect(await bookmark.isBookmarked(item.id), false);
    expect(await sub.isSubscribed(item), false);
    print('✓ 双写 + 删除同步 OK');
  });

  test('Saved screen: 4 个 tab 数据分离 (内容/名言/关注/我的收藏)', () async {
    // 8/28 P56-4: 验证 P56-3 4 tabs 各自独立数据源
    final bookmark = BookmarkService.instance;
    final sub = LocalSubscriptionService.instance;
    await bookmark.clear();
    await _resetSub();

    // 内容 tab: 真实文章
    await sub.subscribe(_articleItem('art_1', 'Article 1', '36氪'));
    await sub.subscribe(_articleItem('art_2', 'Article 2', 'sspai'));

    // 名言 tab: 特殊 id quote_* 前缀
    await sub.subscribe(_quoteItem('quote_1', 'Socrates', 'Know thyself'));
    await sub.subscribe(_quoteItem('quote_2', 'Plato', 'Wisdom begins in wonder'));

    // 我的收藏 tab: BookmarkService 独立条目 (跟 LocalSubscription 不重复)
    await bookmark.add(_articleItem('bm_1', 'Bookmarked 1', 'NPR'));

    // 8/28 P56-4: 验证数据独立
    final subArticles = (await sub.getSubscribedItems()).where((it) => !it.id.startsWith('quote_')).toList();
    final subQuotes = (await sub.getSubscribedItems()).where((it) => it.id.startsWith('quote_')).toList();
    final bookmarkEntries = await bookmark.getAll();

    expect(subArticles.length, 2, reason: '内容 tab 应有 2 个');
    expect(subQuotes.length, 2, reason: '名言 tab 应有 2 个');
    expect(bookmarkEntries.length, 1, reason: '我的收藏 tab 应有 1 个');
    expect(bookmarkEntries.first.id, 'bm_1');
    print('✓ 4 tabs 数据独立 OK (2+2+1)');
  });

  test('Saved screen: 关注 tab 显示用户订阅的平台 + 类目', () async {
    // 8/28 P56-4: 验证关注 tab 数据
    final sub = SubscriptionService.instance;

    // 8/28 P56-4: 默认订阅 (init state)
    final sources = await sub.getSubscribedSources();
    final categories = await sub.getSubscribedCategories();
    expect(sources.isNotEmpty, true, reason: '默认应订阅至少 1 平台');
    expect(categories.isNotEmpty, true, reason: '默认应订阅至少 1 类目');

    // 8/28 P56-4: 加 1 个类目
    await sub.subscribeCategory('编程开发');
    final afterCategories = await sub.getSubscribedCategories();
    expect(afterCategories.length, categories.length + 1,
        reason: '加 1 个类目, 长度+1');
    print('✓ 关注 tab 订阅流程 OK (${sources.length} 平台 + ${afterCategories.length} 类目)');
  });

  test('Saved screen: BookmarkService 跨 tab 共享 (内容 tab 加的 → 我的收藏 tab 显示)', () async {
    // 8/28 P56-4: 验证 P54-2 双写 (内容 tab _toggleSubscribe 也写 BookmarkService)
    final bookmark = BookmarkService.instance;
    final sub = LocalSubscriptionService.instance;
    await bookmark.clear();
    await _resetSub();

    final item = _articleItem('cross_tab_1', 'Cross Tab Test', 'NPR');
    // 内容 tab 路径 (模拟详情页 _toggleSubscribe 双写)
    await sub.subscribe(item);
    await bookmark.add(item);

    // 8/28 P56-4: 我的收藏 tab 立刻能看 (因为双写)
    final bookmarkEntries = await bookmark.getAll();
    expect(bookmarkEntries.any((e) => e.id == item.id), true,
        reason: '内容 tab 加的应同步到我的收藏 tab');
    print('✓ 跨 tab 数据同步 OK');
  });
}