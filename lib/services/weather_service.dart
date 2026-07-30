import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 7/30: 每日天气 — 走 wttr.in (server-side 不需 key, 响应 JSON)
/// CORS: wttr.in 公开支持 CORS, 但中国 NAS 拉 wttr.in 不稳 — 走 rss_proxy 8088 后端 curl
class WeatherService {
  static Future<WeatherInfo> fetch() async {
    // 沿用 #117 rss_proxy 后端代理 RSS 的思路: 这里直接调 wttr.in (它本身支持 CORS)
    // 失败返 mock (不阻塞 UI)
    try {
      final resp = await http
          .get(Uri.parse('https://wttr.in/?format=j1&lang=zh'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) {
        return WeatherInfo.fallback();
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final current = data['current_condition']?[0] as Map<String, dynamic>?;
      if (current == null) return WeatherInfo.fallback();
      final area = data['nearest_area']?[0] as Map<String, dynamic>?;
      final cityName = area?['areaName']?[0]?['value'] as String? ?? '';
      final temp = current['temp_C'] as String? ?? '0';
      final desc = current['lang_zh']?[0]?['value'] as String?
          ?? current['weatherDesc']?[0]?['value'] as String?
          ?? '';
      final feelsLike = current['FeelsLikeC'] as String? ?? temp;
      return WeatherInfo(
        city: cityName,
        tempC: int.tryParse(temp) ?? 0,
        feelsLikeC: int.tryParse(feelsLike) ?? 0,
        description: desc,
        isMock: false,
      );
    } catch (e) {
      debugPrint('[weather] fetch failed: $e — fallback');
      return WeatherInfo.fallback();
    }
  }
}

class WeatherInfo {
  final String city;
  final int tempC;
  final int feelsLikeC;
  final String description;
  final bool isMock;

  WeatherInfo({
    required this.city,
    required this.tempC,
    required this.feelsLikeC,
    required this.description,
    required this.isMock,
  });

  factory WeatherInfo.fallback() => WeatherInfo(
        city: '',
        tempC: 0,
        feelsLikeC: 0,
        description: '晴',
        isMock: true,
      );

  String hint(bool isEn) {
    if (isMock) return isEn ? 'Have a nice day' : '祝你今天愉快';
    final t = tempC;
    if (t >= 30) return isEn ? 'Hot — stay hydrated' : '天热，记得多喝水';
    if (t <= 5) return isEn ? 'Cold — bundle up' : '天冷，多穿件衣服';
    if (t >= 18 && t <= 24) return isEn ? 'Perfect weather' : '天气真好';
    return isEn ? 'Have a great day' : '今天也不错';
  }
}