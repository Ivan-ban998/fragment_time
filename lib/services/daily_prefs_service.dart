import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 7/30: 每日推荐 — 用户偏好开关 (问候/天气/引导)
/// 默认全部开启, 用户可在 settings 关
class DailyPrefsService {
  static final DailyPrefsService instance = DailyPrefsService._();
  DailyPrefsService._();

  static const String _kGreeting = 'daily_greeting_on';
  static const String _kWeather = 'daily_weather_on';
  static const String _kGuide = 'daily_guide_on';

  static final ValueNotifier<bool> greetingNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> weatherNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> guideNotifier =
      ValueNotifier<bool>(true);

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    greetingNotifier.value = prefs.getBool(_kGreeting) ?? true;
    weatherNotifier.value = prefs.getBool(_kWeather) ?? true;
    guideNotifier.value = prefs.getBool(_kGuide) ?? true;
  }

  Future<bool> getGreetingOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGreeting) ?? true;
  }

  Future<bool> getWeatherOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kWeather) ?? true;
  }

  Future<bool> getGuideOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGuide) ?? true;
  }

  Future<void> setGreetingOn(bool v) async {
    greetingNotifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGreeting, v);
  }

  Future<void> setWeatherOn(bool v) async {
    weatherNotifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWeather, v);
  }

  Future<void> setGuideOn(bool v) async {
    guideNotifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGuide, v);
  }

  /// 7/30: 异步初始化 — App 启动时调用一次
  static Future<void> init() async {
    await DailyPrefsService.instance._init();
  }
}