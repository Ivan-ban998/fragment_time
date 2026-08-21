// ignore_for_file: avoid_print
// 8/28 P44-3 沿 SOUL #189: UserType enum fromBucketKey 单元测试
//   验证 P44-2 反查功能 (analytics / settings 持久化用)
// 跑法: flutter test test/user_type_bucket_key_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/models/models.dart';

void main() {
  test('UserType.bucketKey 6 个值正确映射', () {
    expect(UserType.student.bucketKey, 'student');
    expect(UserType.officeWorker.bucketKey, 'officeWorker');
    expect(UserType.entrepreneur.bucketKey, 'entrepreneur');
    expect(UserType.parent.bucketKey, 'parent');
    expect(UserType.senior.bucketKey, 'senior');
    expect(UserType.child.bucketKey, 'child');
  });

  test('UserType.fromBucketKey 反查正确 (6 个 key)', () {
    expect(UserTypeBucket.fromBucketKey('student'), UserType.student);
    expect(UserTypeBucket.fromBucketKey('officeWorker'), UserType.officeWorker);
    expect(UserTypeBucket.fromBucketKey('entrepreneur'), UserType.entrepreneur);
    expect(UserTypeBucket.fromBucketKey('parent'), UserType.parent);
    expect(UserTypeBucket.fromBucketKey('senior'), UserType.senior);
    expect(UserTypeBucket.fromBucketKey('child'), UserType.child);
  });

  test('UserType.fromBucketKey round-trip 不丢字段', () {
    for (final ut in UserType.values) {
      final key = ut.bucketKey;
      final back = UserTypeBucket.fromBucketKey(key);
      expect(back, ut, reason: '$ut → $key → $back');
    }
    print('✓ 6 UserType round-trip OK');
  });

  test('UserType.fromBucketKey 兜底 (unknown key → UserType.student)', () {
    expect(UserTypeBucket.fromBucketKey('invalid_key'), UserType.student);
    expect(UserTypeBucket.fromBucketKey(''), UserType.student);
    print('✓ fallback to UserType.student');
  });
}