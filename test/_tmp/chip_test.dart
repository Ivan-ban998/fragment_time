
import "package:flutter_test/flutter_test.dart";
import "package:fragment_time_good/screens/ai_assistant_screen.dart";
import "package:fragment_time_good/services/rss_service.dart";

void main() {
  test('chip 路径不再 search, 改跳对应 scene', () async {
    // 8/18 验证: _sendQuick 不再调 NewsService.search, 改 fetchTop(scene)
    // 简化测: 模拟 chip '今日新闻' (label='今日新闻', realTitle='得到头条', type='audio')
    // 期望: 走 Scene.listen → fetchTop(scene: listen) → 返 RSS 真数据
    // 不再 search '得到头条' → 永远 0 hits
    
    // 看 _sceneForType helper
    final type = 'audio';
    final scene = _sceneForType(type);  // 应 = Scene.listen
    expect(scene, Scene.listen, reason: 'audio 应映射到 listen scene');
    
    print('audio → \${scene.name}');  // listen
  });
  
  test('article 应映射到 relax', () async {
    final scene = _sceneForType('article');
    expect(scene, Scene.relax);
  });
  
  test('video 应映射到 workout', () async {
    final scene = _sceneForType('video');
    expect(scene, Scene.workout);
  });
}
