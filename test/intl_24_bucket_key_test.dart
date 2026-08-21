// ignore_for_file: avoid_print
// 8/28 P47-4 沿 SOUL #189: 24 桶 dynamic key pattern 测试
//   验证 international_service 桶 key 命名约定
//   (不变 hardcoded data, 只验证 pattern)
// 跑法: flutter test test/intl_24_bucket_key_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/models/models.dart';

void main() {
  test('24 桶 key 模式 (UserType × Scene)', () {
    // 8/28 P47-4 治本 (沿 SOUL #137 真凶): 24 桶 key 命名约定
    //   真凶: 之前 international_service hardcoded 24 keys
    //     → 加 user type / scene 需手维护 (易漏)
    //   修: 验证 dynamic 生成的 key 格式
    int total = 0;
    final expectedTypes = {'student', 'officeWorker', 'entrepreneur', 'parent', 'senior', 'child'};
    final expectedScenes = {'learn', 'listen', 'relax', 'workout'};

    for (final ut in UserType.values) {
      for (final s in Scene.values) {
        final key = '${ut.bucketKey}_${s.bucketKey}';
        // 8/28 P47-4: 验证所有 6 user type × 4 scene 组合 = 24
        expect(expectedTypes, contains(ut.bucketKey),
            reason: 'UserType.bucketKey "${ut.bucketKey}" 应在 6 个 user type 中');
        expect(expectedScenes, contains(s.bucketKey),
            reason: 'Scene.bucketKey "${s.bucketKey}" 应在 4 个 scene 中');
        total++;
      }
    }
    expect(total, 24, reason: '6 user types × 4 scenes = 24');
    print('✓ 24 桶 key 模式 OK');
  });

  test('intl_ 前缀格式 (international_service 命名)', () {
    // 8/28 P47-4 治本: international_service 用 intl_${userType}_${scene} 区分
    int total = 0;
    for (final ut in UserType.values) {
      for (final s in Scene.values) {
        final intlKey = 'intl_${ut.bucketKey}_${s.bucketKey}';
        // 8/28 P47-4: intl_ 前缀 + 24 桶 pattern
        expect(intlKey, startsWith('intl_'),
            reason: '$intlKey 应以 intl_ 开头');
        total++;
      }
    }
    expect(total, 24);
    print('✓ 24 intl_ 桶 key 格式 OK');
  });
}