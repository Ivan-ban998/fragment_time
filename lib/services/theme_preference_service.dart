// lib/services/theme_preference_service.dart
// 6/13 主题偏好：system / light / dark
// 存 SharedPreferences 'pref_theme_mode' = 'system' | 'light' | 'dark'

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferenceService {
  static final ThemePreferenceService instance = ThemePreferenceService._();
  ThemePreferenceService._();

  static const String _key = 'pref_theme_mode';
  static const String _kEyeProtection = 'pref_eye_protection';

  Future<ThemeMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key) ?? 'system';
    switch (s) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final s = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    await prefs.setString(_key, s);
  }

  String modeLabel(ThemeMode mode, {required bool isEn}) {
    switch (mode) {
      case ThemeMode.light: return isEn ? 'Light' : '白天';
      case ThemeMode.dark: return isEn ? 'Dark' : '夜晚';
      case ThemeMode.system: return isEn ? 'Follow system' : '跟随系统';
    }
  }

  // 6/13 护眼模式偏好
  // 含义：
  //   'on'    = 总是开
  //   'off'   = 总是关
  //   'auto'  = 跟随时段 19:00-7:00 开（默认）
  Future<String> getEyeProtectionMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEyeProtection) ?? 'auto';
  }

  Future<void> setEyeProtectionMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEyeProtection, mode);
  }

  /// 判断当前是否开启护眼（含 auto 时段判断）
  Future<bool> isEyeProtectionOn() async {
    final mode = await getEyeProtectionMode();
    if (mode == 'on') return true;
    if (mode == 'off') return false;
    // auto：19:00 - 7:00 开
    final hour = DateTime.now().hour;
    return hour >= 19 || hour < 7;
  }

  String eyeProtectionLabel(String mode, {required bool isEn}) {
    switch (mode) {
      case 'on':  return isEn ? 'Always on' : '总是开';
      case 'off': return isEn ? 'Off' : '关';
      default:    return isEn ? 'Auto (19:00-7:00)' : '自动（19:00-7:00）';
    }
  }
}
