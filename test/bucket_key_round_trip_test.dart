// ignore_for_file: avoid_print
// 8/28 P45-2 沿 SOUL #189: bucketKey 互逆反查 汇总测试
//   验证 Scene + UserType 反查函数对称
// 跑法: flutter test test/bucket_key_round_trip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/models/models.dart';

void main() {
  test('Scene + UserType bucketKey 互逆反查', () {
    // 4 Scene × 6 UserType = 24 个组合
    for (final s in Scene.values) {
      for (final ut in UserType.values) {
        final sKey = s.bucketKey;
        final utKey = ut.bucketKey;
        // 互逆: 序列化 → 反查 = 自身
        expect(SceneBucket.fromBucketKey(sKey), s,
            reason: 'Scene $s → $sKey → ${SceneBucket.fromBucketKey(sKey)}');
        expect(UserTypeBucket.fromBucketKey(utKey), ut,
            reason: 'UserType $ut → $utKey → ${UserTypeBucket.fromBucketKey(utKey)}');
      }
    }
    print('✓ 4 Scene × 6 UserType = 24 组合 round-trip 全 OK');
  });

  test('bucketKey 格式 (无空格)', () {
    // 4 Scene + 6 UserType: 验证所有 bucketKey 不含空格
    for (final s in Scene.values) {
      expect(s.bucketKey, isNot(contains(' ')),
          reason: 'Scene $s bucketKey "${s.bucketKey}" 不应含空格');
    }
    for (final ut in UserType.values) {
      expect(ut.bucketKey, isNot(contains(' ')),
          reason: 'UserType $ut bucketKey "${ut.bucketKey}" 不应含空格');
    }
    print('✓ 10 个 bucketKey 不含空格');
  });

  test('从 bucketKey 拼回 桶 key (RSS 24 桶 key 格式)', () {
    // 验证 analytics / settings 持久化常用模式
    // 24 桶 key 格式: e.g. "student_learn", "officeWorker_relax"
    //   UserType 含 camelCase (officeWorker, entrepreneur), Scene 全小写
    int total = 0;
    for (final s in Scene.values) {
      for (final ut in UserType.values) {
        final key = '${ut.bucketKey}_${s.bucketKey}';
        // 8/28 P45-2 改: regex 允许 camelCase (officeWorker 含大写 W)
        expect(key, matches(RegExp(r'^[a-zA-Z]+_[a-z]+$')),
            reason: '24 桶 key 应匹配: $key (lowercase/camelCase + underscore + lowercase)');
        total++;
      }
    }
    print('✓ $total 桶 key 格式 (camelCase_lowercase)');
  });
}