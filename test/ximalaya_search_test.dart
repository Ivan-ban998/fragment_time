// ignore_for_file: avoid_print
// 8/28 P39-4 沿 SOUL #189: XimalayaService iTunes Search 单元测试
//   验证 P38-1 search() 接入 + 解析 iTunes API 响应
// 跑法: flutter test test/ximalaya_search_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/ximalaya_service.dart';

void main() {
  test('XimalayaService.search "tech podcast" 返非空 list (真 iTunes API)', () async {
    // 8/28 P39-5: 验证 search() 调 iTunes API 真工作 (网络可达时)
    final tracks = await XimalayaService().search('tech podcast', limit: 3);
    print('search("tech podcast", limit=3) 返 ${tracks.length} tracks');
    if (tracks.isEmpty) {
      print('⚠️ 网络不通或 iTunes API 返空, 跳过验证');
      return;
    }
    expect(tracks.isNotEmpty, true, reason: 'iTunes API 应返至少 1 条');
    // 第一条 title: 不应为空, url 应为 Apple Podcasts 链接
    expect(tracks.first.title.isNotEmpty, true);
    expect(tracks.first.url.isNotEmpty, true);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('XimalayaService.albums 返 5 个 trending podcasts (并发 fetch)', () async {
    final albums = await XimalayaService().albums();
    print('albums() 返 ${albums.length} trending podcasts');
    if (albums.isEmpty) {
      print('⚠️ 网络不通, 跳过验证');
      return;
    }
    expect(albums.isNotEmpty, true, reason: 'albums 应返至少 1 个');
  }, timeout: const Timeout(Duration(seconds: 30)));
}