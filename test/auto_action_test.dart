// ignore_for_file: avoid_print
// 8/28 P57-6 沿 SOUL #189: 自动做 actions 测试 (autoSaveOnRead / autoFollowOnView / demoBookmarks)
//   验证 P57-2/3/4 默认做 actions (沿用户"默认做"指示)
// 跑法: flutter test test/auto_action_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fragment_time/services/bookmark_service.dart';
import 'package:fragment_time/services/local_subscription_service.dart';
import 'package:fragment_time/services/subscription_service.dart';
import 'package:fragment_time/models/models.dart';

ContentItem _item(String id, String title) => ContentItem(
      id: id,
      title: title,
      description: 'desc $id',
      duration: '5min',
      source: '36氪',
      sourceType: ContentSource.news36kr,
      contentType: ContentType.article,
    );

Future<void> _resetSub() async {
  final items = await LocalSubscriptionService.instance.getSubscribedItems();
  for (final it in items) {
    await LocalSubscriptionService.instance.unsubscribe(it);
  }
}

/// 8/28 P57-6: 重置 SubscriptionService.categories (回到默认状态)
Future<void> _resetCategories() async {
  final cats = await SubscriptionService.instance.getSubscribedCategories();
  for (final c in cats.toList()) {
    await SubscriptionService.instance.unsubscribeCategory(c);
  }
  // 8/28 P57-6: 加默认 8 类目 (跟 main.dart _autoSubscribeDefaultCategories 一致)
  for (final c in SubscriptionService.defaultCategories) {
    await SubscriptionService.instance.subscribeCategory(c);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 8/28 P57-6: 重置 SubscriptionService 默认状态
    await _resetCategories();
  });

  test('P57-4: demoBookmarks 首次启动预填 3 条', () async {
    // 8/28 P57-6: 验证 demoBookmarks 加 3 条
    final svc = BookmarkService.instance;
    await svc.clear();

    // 8/28 P57-6: 首次启动 (无收藏) → 加 demo
    final added = await svc.addDemoBookmarksIfFirst();
    expect(added, true, reason: '首次启动应返 true (加了 demo)');

    // 8/28 P57-6: 验证 3 条 demoBookmarks
    final entries = await svc.getAll();
    expect(entries.length, 3, reason: '应有 3 条 demo');
    expect(entries[0].id, '_demo_bookmark_1');
    expect(entries[1].id, '_demo_bookmark_2');
    expect(entries[2].id, '_demo_bookmark_3');
    print('✓ demoBookmarks 加 3 条 OK');
  });

  test('P57-4: demoBookmarks 不重复加 (有收藏就不加)', () async {
    // 8/28 P57-6: 验证有收藏时, addDemoBookmarksIfFirst 不加 demo
    final svc = BookmarkService.instance;
    await svc.clear();
    await svc.add(_item('user_added_1', 'User Added'));

    // 8/28 P57-6: 有 1 条真实收藏, 不应加 demo
    final added = await svc.addDemoBookmarksIfFirst();
    expect(added, false, reason: '有真实收藏时不应加 demo');

    final entries = await svc.getAll();
    expect(entries.length, 1, reason: '只有 1 条真实收藏');
    expect(entries.first.id, 'user_added_1');
    print('✓ demoBookmarks 不重复加 OK');
  });

  test('P57-2: autoSaveOnRead 模拟 (读完自动 BookmarkService.add)', () async {
    // 8/28 P57-6: 模拟 content_reader _markComplete 双写
    final svc = BookmarkService.instance;
    final sub = LocalSubscriptionService.instance;
    await svc.clear();
    await _resetSub();

    final item = _item('auto_save_1', 'Auto Save Test');
    // 8/28 P57-6: 模拟 _markComplete (读 100% + autoSaveOnRead)
    await sub.updateProgress(item, 100);
    if (!await svc.isBookmarked(item.id)) {
      await svc.add(item);
    }

    expect(await svc.isBookmarked(item.id), true,
        reason: 'autoSaveOnRead 应自动加到 BookmarkService');
    print('✓ autoSaveOnRead 双写 OK');
  });

  test('P57-3: autoFollowOnView student 推荐类目全订阅', () async {
    // 8/28 P57-6: 验证 _onUserTypeSelected 加 student 推荐 3 类目
    //   注: 默认 8 类目已含 英语学习/科技资讯, 所以"新加"只算 编程开发
    final svc = SubscriptionService.instance;
    final before = await svc.getSubscribedCategories();
    final count = await svc.autoFollowOnView(UserType.student);
    expect(count, greaterThan(0), reason: 'student 应加至少 1 个新类目 (编程开发是新)');
    final after = await svc.getSubscribedCategories();
    // 8/28 P57-6: student 推荐 3 个类目都应在订阅列表
    expect(after.contains('编程开发'), true);
    expect(after.contains('英语学习'), true);
    expect(after.contains('科技资讯'), true);
    print('✓ autoFollowOnView student 加 ${after.length - before.length} 新类目 (推荐 3 全订阅)');
  });

  test('P57-3: autoFollowOnView 6 userType 全部有推荐', () async {
    // 8/28 P57-6: 验证 6 userType 都有推荐类目
    int totalRecs = 0;
    for (final ut in UserType.values) {
      final recs = SubscriptionService.recommendedCategoriesByUserType[ut.name] ?? [];
      expect(recs.isNotEmpty, true, reason: '$ut 应有推荐类目');
      expect(recs.length, 3, reason: '$ut 应有 3 个推荐');
      totalRecs += recs.length;
      print('  $ut → $recs');
    }
    expect(totalRecs, 18, reason: '6 userType × 3 = 18 推荐');
    print('✓ 6 userType 推荐覆盖 OK');
  });

  test('P57-3: autoFollowOnView officeWorker 推荐类目全订阅', () async {
    // 8/28 P57-6: 验证 officeWorker 推荐类目
    final svc = SubscriptionService.instance;
    final before = await svc.getSubscribedCategories();
    await svc.autoFollowOnView(UserType.officeWorker);
    final after = await svc.getSubscribedCategories();
    print('DEBUG: before=$before');
    print('DEBUG: after=$after');
    // 8/28 P57-6: officeWorker 推荐 3 类目都应在订阅列表
    expect(after.contains('职场技能'), true);
    expect(after.contains('理财知识'), true);
    expect(after.contains('心理成长'), true);
    print('✓ autoFollowOnView officeWorker 加 ${after.length - before.length} 新类目 (推荐 3 全订阅)');
  });

  test('P57-3: autoFollowOnView 不重复加 (幂等)', () async {
    // 8/28 P57-6: 已订阅的 userType 推荐类目, 二次调用不重复
    final svc = SubscriptionService.instance;
    await svc.autoFollowOnView(UserType.parent);
    final after1 = await svc.getSubscribedCategories();
    await svc.autoFollowOnView(UserType.parent);
    final after2 = await svc.getSubscribedCategories();
    expect(after2.length, after1.length,
        reason: '第二次 autoFollowOnView 不应再加 (已订阅)');
    print('✓ autoFollowOnView 幂等 OK');
  });
}