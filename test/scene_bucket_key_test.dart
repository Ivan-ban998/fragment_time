// ignore_for_file: avoid_print
// 8/28 P43-2 沿 SOUL #189: Scene enum fromBucketKey 单元测试
//   验证 P42-3 反查功能 (RSS / analytics 持久化用)
// 跑法: flutter test test/scene_bucket_key_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/models/models.dart';

void main() {
  test('Scene.bucketKey 4 个值正确映射', () {
    expect(Scene.learn.bucketKey, 'learn');
    expect(Scene.listen.bucketKey, 'listen');
    expect(Scene.relax.bucketKey, 'relax');
    expect(Scene.workout.bucketKey, 'workout');
  });

  test('Scene.fromBucketKey 反查正确 (4 个 key)', () {
    expect(SceneBucket.fromBucketKey('learn'), Scene.learn);
    expect(SceneBucket.fromBucketKey('listen'), Scene.listen);
    expect(SceneBucket.fromBucketKey('relax'), Scene.relax);
    expect(SceneBucket.fromBucketKey('workout'), Scene.workout);
  });

  test('Scene.fromBucketKey round-trip 不丢字段', () {
    for (final s in Scene.values) {
      final key = s.bucketKey;
      final back = SceneBucket.fromBucketKey(key);
      expect(back, s, reason: '$s → $key → $back');
    }
    print('✓ 4 Scene round-trip OK');
  });

  test('Scene.fromBucketKey 兜底 (unknown key → Scene.learn)', () {
    expect(SceneBucket.fromBucketKey('invalid_key'), Scene.learn);
    expect(SceneBucket.fromBucketKey(''), Scene.learn);
    print('✓ fallback to Scene.learn');
  });
}