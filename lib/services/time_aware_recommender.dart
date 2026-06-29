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
  /// 根据当前时间 + 当前用户角色返回推荐
  /// 6/25 修 bug: 之前只硬编码 6 种 userType 不看当前选择, 用户选上班族也会推荐学生党
  /// 6/26 Brien 反馈: scene 跟 userType 不联动, 上班族上午推 "学点东西" 违和 → 按 userType 选场景
  static TimeRecommendation recommendAt(DateTime now, {UserType? currentUserType}) {
    final h = now.hour;
    final ut = currentUserType ?? UserType.student;
    final name = _userTypeNameZh(ut);

    // 6/26: 按 userType 选时段场景
    // - 学生/小朋友/宝爸宝妈 → learn (学习场景)
    // - 上班族/创业者 → listen (资讯/通勤)
    // - 退休人群 → relax (慢节奏)
    bool preferLearn() => ut == UserType.student || ut == UserType.child || ut == UserType.parent;
    bool preferListen() => ut == UserType.officeWorker || ut == UserType.entrepreneur;
    bool preferRelax() => ut == UserType.senior;

    // 根据时间推荐场景
    Scene scene;
    String label;
    if (h >= 7 && h < 9) {
      // 早间: 通勤
      if (preferRelax()) {
        scene = Scene.relax; label = '$name - 放松一下';
      } else {
        scene = Scene.listen; label = '$name - 听一听';
      }
    } else if (h >= 9 && h < 12) {
      // 上午
      if (preferListen()) {
        scene = Scene.listen; label = '$name - 听一听';
      } else if (preferRelax()) {
        scene = Scene.relax; label = '$name - 放松一下';
      } else {
        scene = Scene.learn; label = '$name - 学点东西';
      }
    } else if (h >= 12 && h < 14) {
      scene = Scene.relax; label = '$name - 放松一下';
    } else if (h >= 14 && h < 18) {
      // 下午
      if (preferListen()) {
        scene = Scene.listen; label = '$name - 听一听';
      } else if (preferRelax()) {
        scene = Scene.relax; label = '$name - 放松一下';
      } else {
        scene = Scene.learn; label = '$name - 学点东西';
      }
    } else if (h >= 18 && h < 21) {
      // 下班通勤
      if (preferRelax()) {
        scene = Scene.relax; label = '$name - 放松一下';
      } else {
        scene = Scene.listen; label = '$name - 听一听';
      }
    } else {
      scene = Scene.relax; label = '$name - 放松一下';
    }
    return TimeRecommendation(ut, scene, label);
  }

  static String _userTypeNameZh(UserType t) {
    switch (t) {
      case UserType.student: return '学生党';
      case UserType.officeWorker: return '上班族';
      case UserType.entrepreneur: return '创业者';
      case UserType.parent: return '宝爸宝妈';
      case UserType.senior: return '退休人群';
      case UserType.child: return '小朋友';
    }
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

  /// 默认用 student (调用方应该传 currentUserType)
  static TimeRecommendation get current => recommendAt(DateTime.now());
}