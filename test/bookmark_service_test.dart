// ignore_for_file: avoid_print
// 8/28 P53-2 沿 SOUL #189: BookmarkService 单元测试
//   验证 P53 收藏: add / remove / toggle / isBookmarked / getRecent
// 跑法: flutter test test/bookmark_service_test.dart
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
    // 8/28 P53-2: 初始化 SharedPreferences (测试用 mock)
    SharedPreferences.setMockInitialValues({});
  });

  test('BookmarkService add / isBookmarked / remove', () async {
    final svc = BookmarkService.instance;
    final item = _item('test_1', 'Test Article 1');

    expect(await svc.isBookmarked('test_1'), false,
        reason: '初始状态不应有收藏');

    await svc.add(item);
    expect(await svc.isBookmarked('test_1'), true,
        reason: 'add 后应已收藏');
    expect(await svc.count(), 1, reason: 'count 应为 1');

    await svc.remove('test_1');
    expect(await svc.isBookmarked('test_1'), false,
        reason: 'remove 后应未收藏');
    expect(await svc.count(), 0);
  });

  test('BookmarkService toggle 返回正确状态', () async {
    final svc = BookmarkService.instance;
    final item = _item('test_2', 'Test Article 2');

    final added = await svc.toggle(item);
    expect(added, true, reason: '首次 toggle 应返回 true (已收藏)');
    expect(await svc.isBookmarked('test_2'), true);

    final removed = await svc.toggle(item);
    expect(removed, false, reason: '再次 toggle 应返回 false (取消)');
    expect(await svc.isBookmarked('test_2'), false);
  });

  test('BookmarkService dedup (重复 add skip)', () async {
    final svc = BookmarkService.instance;
    final item = _item('test_3', 'Test 3');

    await svc.add(item);
    await svc.add(item);
    await svc.add(item);
    expect(await svc.count(), 1,
        reason: '重复 add 不应创建重复条目');
  });

  test('BookmarkService getRecent 按时间倒序', () async {
    final svc = BookmarkService.instance;
    await svc.clear();

    await svc.add(_item('a', 'Article A'));
    await Future.delayed(const Duration(milliseconds: 10));
    await svc.add(_item('b', 'Article B'));
    await Future.delayed(const Duration(milliseconds: 10));
    await svc.add(_item('c', 'Article C'));

    final recent = await svc.getRecent();
    expect(recent.length, 3);
    expect(recent[0].id, 'c', reason: '最新添加应在最前');
    expect(recent[1].id, 'b');
    expect(recent[2].id, 'a');
    print('✓ getRecent: ${recent.map((e) => e.id).toList()}');
  });

  test('BookmarkService 持久化 (跨 instance 保留)', () async {
    // 8/28 P53-2 治本 (沿 SOUL #188 透明): SharedPreferences 持久化
    final svc1 = BookmarkService.instance;
    await svc1.clear();
    await svc1.add(_item('persist_1', 'Persist Test 1'));

    // 8/28 P53-2: simulate app restart (新 instance 读 SharedPreferences)
    final svc2 = BookmarkService.instance;
    final entries = await svc2.getAll();
    expect(entries.length, 1, reason: '持久化应保留收藏');
    expect(entries.first.id, 'persist_1');
    expect(entries.first.title, 'Persist Test 1');
  });

  test('BookmarkService clear 清空所有', () async {
    final svc = BookmarkService.instance;
    await svc.clear();
    await svc.add(_item('c1', 'C1'));
    await svc.add(_item('c2', 'C2'));
    expect(await svc.count(), 2);

    await svc.clear();
    expect(await svc.count(), 0, reason: 'clear 后应为 0');
  });

  test('BookmarkEntry fromJson round-trip', () {
    // 8/28 P53-2: 测试序列化 / 反序列化
    final orig = BookmarkEntry(
      id: 'round_trip_1',
      title: 'Round Trip Test',
      source: 'B站',
      url: 'https://example.com/1',
      description: 'desc',
      addedAt: DateTime(2026, 8, 28),
    );
    final json = orig.toJson();
    final back = BookmarkEntry.fromJson(json);
    expect(back.id, orig.id);
    expect(back.title, orig.title);
    expect(back.source, orig.source);
    expect(back.url, orig.url);
    expect(back.addedAt, orig.addedAt);
    print('✓ round-trip: ${back.id} / ${back.addedAt}');
  });
}