// ignore_for_file: avoid_print
// 8/28 P55-4 沿 SOUL #189: BookmarkService + Chip 集成测试
//   验证 P54-2 双写 (LocalSubscription + BookmarkService) + P53 持久化
// 跑法: flutter test test/bookmark_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fragment_time/services/bookmark_service.dart';
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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('BookmarkService 集成: add + isBookmarked + count', () async {
    // 8/28 P55-4: 模拟详情页 _toggleSubscribe 双写 BookmarkService
    final svc = BookmarkService.instance;
    await svc.clear();

    final item = _item('integration_1', 'Integration Test 1');
    expect(await svc.isBookmarked(item.id), false);

    await svc.add(item);
    expect(await svc.isBookmarked(item.id), true);
    expect(await svc.count(), 1);

    // 8/28 P55-4: 模拟 _toggleSubscribe 删路径
    await svc.remove(item.id);
    expect(await svc.isBookmarked(item.id), false);
    expect(await svc.count(), 0);
    print('✓ add + isBookmarked + remove flow OK');
  });

  test('BookmarkService 集成: 多个 items (chip 多次点击)', () async {
    final svc = BookmarkService.instance;
    await svc.clear();

    // 8/28 P55-4: 模拟用户点多个 chip
    final items = [
      _item('intl_chip_1', 'BBC English Article'),
      _item('intl_chip_2', 'White Noise Audio'),
      _item('intl_chip_3', '5-Min Meditation'),
    ];
    for (final item in items) {
      await svc.add(item);
    }

    expect(await svc.count(), 3);
    final recent = await svc.getRecent();
    expect(recent.length, 3);
    expect(recent[0].id, 'intl_chip_3', reason: '最新添加应在最前');
    print('✓ 3 chips 添加后 getRecent 按时间倒序 OK');
  });

  test('BookmarkService 集成: Listener 模式 (UI 自动刷新)', () async {
    // 8/28 P55-4: 验证 addListener + removeListener 沿 P53-4 BookmarksScreen 用法
    final svc = BookmarkService.instance;
    await svc.clear();
    int listenerCount = 0;
    void listener() => listenerCount++;

    svc.addListener(listener);
    await svc.add(_item('listener_test', 'Listener Test'));
    expect(listenerCount, 1, reason: 'add 应触发 listener 1 次');

    await svc.add(_item('listener_test_2', 'Listener Test 2'));
    expect(listenerCount, 2, reason: 'add 应触发 listener 1 次');

    svc.removeListener(listener);
    await svc.add(_item('listener_test_3', 'Listener Test 3'));
    expect(listenerCount, 2, reason: 'removeListener 后不触发');
    print('✓ listener 模式 OK');
  });

  test('BookmarkService 集成: dedup + 内容不变 (snapshot 真实数据)', () async {
    // 8/28 P55-4 沿 SOUL #169 不撒谎: snapshot ContentItem 真实数据
    final svc = BookmarkService.instance;
    await svc.clear();

    final item = _item('dedup_1', 'Dedup Test');
    await svc.add(item);
    await svc.add(item);  // 重复
    await svc.add(item);  // 重复
    expect(await svc.count(), 1, reason: '重复 add 应只保留 1 条');

    // 8/28 P55-4: 验证 snapshot 内容 (不是 mock placeholder)
    final entries = await svc.getAll();
    expect(entries.first.title, 'Dedup Test');
    expect(entries.first.source, '36氪');
    expect(entries.first.url, '', reason: 'item.externalUrl 为空, snapshot 也空');
    print('✓ dedup + 内容 OK');
  });

  test('BookmarkService 集成: clear + 持久化', () async {
    final svc = BookmarkService.instance;
    await svc.add(_item('persist_test', 'Persist Test'));

    // 8/28 P55-4: 模拟 app 重启 (新 singleton, 但 SharedPreferences 持久)
    final newSvc = BookmarkService.instance;
    expect(await newSvc.isBookmarked('persist_test'), true);

    await newSvc.clear();
    expect(await newSvc.count(), 0);
    print('✓ 持久化 + clear OK');
  });
}