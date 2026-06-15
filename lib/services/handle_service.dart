// lib/services/handle_service.dart
// 6/10 新增: 我的 handle 持久化（学习小组创建/加入/退出都靠它）
import 'package:shared_preferences/shared_preferences.dart';

class HandleService {
  static const String _key = 'my_handle_v1';
  static const String defaultHandle = '@你';

  Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultHandle;
  }

  Future<void> set(String handle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, handle.trim().isEmpty ? defaultHandle : handle.trim());
  }
}