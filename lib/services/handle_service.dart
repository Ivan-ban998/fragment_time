// lib/services/handle_service.dart
// 6/10 新增: 我的 handle 持久化（学习小组创建/加入/退出都靠它）
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HandleService {
  static const String _key = 'my_handle_v1';
  static const String defaultHandle = '@你';

  // 6/25 修 bug: 加 ValueNotifier 让 set 后 UI 能 ValueListenableBuilder 重建
  // (之前 set 后 SettingsTab 不会 rebuild, 昵称看起来 '没保存')
  static final ValueNotifier<String> notifier = ValueNotifier<String>(defaultHandle);

  Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key) ?? defaultHandle;
    notifier.value = v; // 同步到 notifier
    return v;
  }

  Future<void> set(String handle) async {
    final prefs = await SharedPreferences.getInstance();
    final v = handle.trim().isEmpty ? defaultHandle : handle.trim();
    await prefs.setString(_key, v);
    notifier.value = v; // 通知 listeners
  }
}