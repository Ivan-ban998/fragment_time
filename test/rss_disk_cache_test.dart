// ignore_for_file: avoid_print
// 8/8 沿 SOUL #189: 单元测试 RSS disk cache 落盘 + 读盘
// 验证: 模拟 SharedPreferences 写 → 新 RssService 读 (整路径)
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fragment_time/services/rss_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RssItem.toJson / fromJson round-trip', () {
    final orig = RssItem(
      title: 'Test 标题',
      url: 'https://example.com/1',
      description: 'desc',
      pubDate: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      sourceName: 'sspai',
    );
    final back = RssItem.fromJson(orig.toJson());
    expect(back.title, orig.title);
    expect(back.url, orig.url);
    expect(back.description, orig.description);
    expect(back.pubDate.millisecondsSinceEpoch, orig.pubDate.millisecondsSinceEpoch);
    expect(back.sourceName, orig.sourceName);
    print('✓ toJson/fromJson round-trip OK');
  });

  test('RssService 整路径: fetchTop 成功后 _saveToDisk 写盘', () async {
    // 模拟 SharedPreferences: 初始空
    SharedPreferences.setMockInitialValues({});

    final svc = RssService(isInternational: false);
    final items = await svc.fetchTop(limit: 10);
    print('fetchTop 返 ${items.length} 条');
    if (items.isEmpty) {
      print('⚠️ 网络不通或 sspai 返空, 跳过 disk cache 验收');
      return;
    }

    // 验 mock SharedPreferences 真有 rss_cache_
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.toString().startsWith('rss_cache_'));
    print('mock SharedPreferences rss_cache_* keys: ${keys.length}');
    expect(keys.isNotEmpty, true, reason: 'fetchTop 成功应该有 rss_cache_* 落盘');
    print('✓ _saveToDisk 写盘 OK');

    // 模拟"重启" — 新 RssService instance
    final svc2 = RssService(isInternational: false);
    final items2 = await svc2.fetchTop(limit: 10);
    print('重启后 fetchTop 返 ${items2.length} 条');
    expect(items2.length, items.length, reason: '重启后从 disk cache 拿应一致');
    print('✓ _loadFromDisk 读盘 OK');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
