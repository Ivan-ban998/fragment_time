// lib/services/time_aware_recommender.dart
// 按时段自动推荐场景 — 6/23 从精简版挑过来
// 6/23 fix: 用原版 Scene enum 值 (learn / listen / relax / workout),不用 v2 (news/podcast)
import '../models/models.dart';

class TimeRecommendation {
  final UserType userType;
  final Scene scene;
  final String label;
  const TimeRecommendation(this.userType, this.scene, this.label);
}

class TimeAwareRecommender {
  /// 根据当前时间返回推荐
  static TimeRecommendation recommendAt(DateTime now) {
    final h = now.hour;

    if (h >= 7 && h < 9) {
      return const TimeRecommendation(UserType.officeWorker, Scene.listen, '上班族 - 听一听');
    }
    if (h >= 9 && h < 12) {
      return const TimeRecommendation(UserType.entrepreneur, Scene.learn, '创业者 - 学点东西');
    }
    if (h >= 12 && h < 14) {
      return const TimeRecommendation(UserType.officeWorker, Scene.relax, '上班族 - 放松一下');
    }
    if (h >= 14 && h < 18) {
      return const TimeRecommendation(UserType.student, Scene.learn, '学生党 - 学点东西');
    }
    if (h >= 18 && h < 21) {
      return const TimeRecommendation(UserType.officeWorker, Scene.listen, '上班族 - 听一听');
    }
    return const TimeRecommendation(UserType.senior, Scene.relax, '退休人群 - 放松一下');
  }

  /// 字符串描述 (遵守宪法: 不用 emoji 字符)
  static String greetingFor(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 9) return '早上好,出门了吗?';
    if (h >= 9 && h < 12) return '上午好,学点新东西?';
    if (h >= 12 && h < 14) return '午休时间,放松一下';
    if (h >= 14 && h < 18) return '下午好,刷会儿内容';
    if (h >= 18 && h < 21) return '下班了,通勤路上看看?';
    return '夜深了,摸鱼前看点有用的';
  }

  static TimeRecommendation get current => recommendAt(DateTime.now());
}