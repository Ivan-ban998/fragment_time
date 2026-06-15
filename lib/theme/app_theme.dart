// lib/theme/app_theme.dart
// 完整版：保留昨晚引用的 lightTheme getter + 静态常量 textLight/primary

import 'package:flutter/material.dart';

class AppTheme {
  // 静态常量（main.dart / scene_screen / user_type_screen 引用）
  static const Color textLight = Color(0xFF888888);
  static const Color textDark = Color(0xFF333333);
  static const Color primary = Color(0xFF6750A4);
  static const Color secondary = Color(0xFF8B5CF6);

  // 主题
  static ThemeData get lightTheme => light();
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ),
        cardTheme: const CardTheme(elevation: 2, margin: EdgeInsets.all(8)),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      );

  // 6/8 修复：dark theme 背景不要死黑，surface/卡片都拾亮一些
  // 原因：puppeteer 截到旧暗色下副标题/版权几乎不可见——背景太沉 + onSurface 太深
  // 6/8 实际 puppeteer 测试反馈
  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
        ).copyWith(
          // surface 提起一点（不充漆黑，抬升到近黑灰）
          surface: const Color(0xFF1C1B1F),
          // 卡片背景比 surface 亮一档，让【未激活】卡片边缘看得到
          surfaceContainerHighest: const Color(0xFF2A2830),
          onSurfaceVariant: const Color(0xFFCAC4D0), // 副标题/版权从 0xFF888888 抬到 0xFFCAC4D0
        ),
        cardTheme: const CardTheme(elevation: 2, margin: EdgeInsets.all(8)),
        // appBar 提一点亮度，避免和 surface 融一片
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0, surfaceTintColor: Color(0xFF2A2830)),
      );

  // 6/8 修复：brightness-aware hint color helper
  // 64 处 lib/screens/ 用 AppTheme.textLight，6/8 不全改（风险大）
  // 但给个新 helper，后续可以逐步替换
  // 返回调色亮色 = textLight（0xFF888888）；暗色 = white70（看得见）
  static Color hintColor(BuildContext c) {
    return Theme.of(c).brightness == Brightness.dark
        ? Colors.white70
        : textLight;
  }

  static Color bodyColor(BuildContext c) {
    return Theme.of(c).brightness == Brightness.dark
        ? Colors.white
        : textDark;
  }

  // 6/12 加: 老人模式按钮主题 — 加大点按区域 + 加大图标
  static ThemeData applyElderlyMode(ThemeData base, bool isElderly) {
    if (!isElderly) return base;
    return base.copyWith(
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(88, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }
}
