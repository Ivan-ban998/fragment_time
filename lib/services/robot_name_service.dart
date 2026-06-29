// 6/30 00:20: AI 机器人昵称 — 跟用户 handle 分离
// 默认 "小O" (IDENTITY.md 6/29 命名), 用户设置里改
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RobotNameService {
  static const String _key = 'robot_name_v1';
  static const String defaultRobotName = '小O';

  static final ValueNotifier<String> notifier = ValueNotifier<String>(defaultRobotName);

  Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key) ?? defaultRobotName;
    notifier.value = v;
    return v;
  }

  Future<void> set(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final v = name.trim().isEmpty ? defaultRobotName : name.trim();
    await prefs.setString(_key, v);
    notifier.value = v;
  }
}
