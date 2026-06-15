import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class LocaleService {
  static const String _isInternationalKey = 'is_international';
  static const String _languageCodeKey = 'language_code';
  static const String _isElderlyModeKey = 'is_elderly_mode';
  static const String _selectedUserTypeKey = 'selected_user_type';

  Future<bool> getIsInternational() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isInternationalKey) ?? false;
  }

  Future<void> setIsInternational(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isInternationalKey, value);
  }

  Future<String> getLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageCodeKey) ?? 'zh';
  }

  Future<void> setLanguageCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageCodeKey, code);
  }

  Future<bool> getIsElderlyMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isElderlyModeKey) ?? false;
  }

  Future<void> setIsElderlyMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isElderlyModeKey, value);
  }

  Future<String> getSelectedUserTypeName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedUserTypeKey) ?? '';
  }

  Future<void> setSelectedUserType(UserType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedUserTypeKey, type.name);
  }

  // 6/9 新增：首次启动判断 — 0 onboarding，直接进首页
  // 不要问 0 个问题（产品决策：不问）。首次打开 = 默认学生 + 默认场景
  Future<bool> getIsFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.containsKey('first_launched_at'));
  }

  Future<void> markFirstLaunched() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('first_launched_at', DateTime.now().toIso8601String());
  }
}