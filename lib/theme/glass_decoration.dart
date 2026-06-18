// lib/theme/glass_decoration.dart
// 6/13 玻璃磨砂风格 token（参考知乎图：iOS/macOS 毛玻璃弹窗）
// 关键设计原则：
//   1. 背景用渐变（蓝紫冷色调），不靠单色
//   2. 所有浮层 = 半透明 + BackdropFilter sigma 20
//   3. 圆角统一 20（卡片）/ 16（按钮）/ 24（弹窗）
//   4. 阴影 = 0 8px 32px rgba(0,0,0,0.1)
//   5. 不动 AppTheme 静态常量（避免 64 处引用炸）

import 'package:flutter/material.dart';
import 'app_theme.dart';

class GlassStyle {
  // ========== 背景渐变（按 scene 分 4 个色相 × 2 个亮度） ==========
  // 6/15 v3 极浅色 400→50（顶色 ≤ 400）：Brien 偏好浅色 + 老人友好
  // 学 = 蓝紫 / 听 = 青蓝 / 放松 = 绿 / 运动 = 橙
  // 顶色压到 300-400 区间，底色几乎白，玻璃透出 0.3 时背景"亮"不"压"
  static const Map<String, List<Color>> sceneGradients = {
    'learn':   [Color(0xFFA5B4FC), Color(0xFFEEF2FF)], // 蓝紫 400→50
    'listen':  [Color(0xFF67E8F9), Color(0xFFECFEFF)], // 青蓝 300→50
    'relax':   [Color(0xFF86EFAC), Color(0xFFF0FDF4)], // 绿 300→50
    'workout': [Color(0xFFFDBA74), Color(0xFFFFF7ED)], // 橙 300→50
  };

  // 6/15 v3 暗色：同色相 600→300（不再用 800 顶深，浅色宪法）
  static const Map<String, List<Color>> sceneGradientsDark = {
    'learn':   [Color(0xFF6366F1), Color(0xFFA5B4FC)], // 蓝紫 500→400
    'listen':  [Color(0xFF0891B2), Color(0xFF67E8F9)], // 青蓝 600→300
    'relax':   [Color(0xFF22C55E), Color(0xFF86EFAC)], // 绿 500→300
    'workout': [Color(0xFFF97316), Color(0xFFFDBA74)], // 橙 500→300
  };

  // 6/13 护眼（iOS Night Shift 暖琥珀）：所有 scene 统一暖色
  static const Map<String, List<Color>> sceneGradientsWarm = {
    'learn':   [Color(0xFFFFE8C5), Color(0xFFFFD9A0)], // 暖琥珀
    'listen':  [Color(0xFFFFE8C5), Color(0xFFFFD9A0)],
    'relax':   [Color(0xFFFFE8C5), Color(0xFFFFD9A0)],
    'workout': [Color(0xFFFFE8C5), Color(0xFFFFD9A0)],
  };

  // 6/13 顺序：护眼 > 暗色 > 白天
  static LinearGradient sceneBackground(String scene, {bool dark = false, bool warm = false}) {
    if (warm) {
      final colors = sceneGradientsWarm[scene] ?? sceneGradientsWarm['learn']!;
      return LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    final map = dark ? sceneGradientsDark : sceneGradients;
    final colors = map[scene] ?? map['learn']!;
    return LinearGradient(
      colors: colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // ========== 玻璃面板 ==========
  // 主玻璃卡：白 0.3 透 + 边框 + 阴影 + 圆角 20
  // 6/15 调薄：背景是顶深底浅高饱和渐变,玻璃太白(0.55-0.7)会"糊"在背景上
  // 0.3 透 + BackdropFilter 才有真磨砂感
  // 6/15 v2 改：dark mode (底色亮单色) 时玻璃卡调深 0.5, 文字不被白叠吃掉
  static BoxDecoration glassCard({
    double opacity = 0.3,
    double radius = 20,
    Color? borderColor,
    bool dark = false,
  }) {
    if (dark) opacity = 0.5;
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      // 6/14 双层边框：外圈细亮 + 内层柔
      border: Border.all(
        color: borderColor ?? Colors.white.withOpacity(0.6),
        width: 1.5,
      ),
      boxShadow: [
        // 主阴影
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 32,
          offset: const Offset(0, 8),
        ),
        // 6/14 高光：顶部细窄白边（模拟光打在玻璃上沿）
        BoxShadow(
          color: Colors.white.withOpacity(0.5),
          blurRadius: 0.5,
          offset: const Offset(0, -0.5),
          spreadRadius: -0.5,
        ),
      ],
    );
  }

  // 6/14 新增：强毛玻璃 helper（白透 0.45 + 高光双层 + 顶亮影）
  // 用法：BackdropFilter sigma 25 + glassFrosted() 才有"真磨砂"感
  static BoxDecoration glassFrosted({
    double opacity = 0.45,
    double radius = 20,
  }) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.55),
        width: 1.5,
      ),
      gradient: LinearGradient(
        // 6/14 玻璃高光：顶部稍亮 → 底部稍暗
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(opacity + 0.1),
          Colors.white.withOpacity(opacity - 0.05),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  // 浮层玻璃（更透一些）
  // 6/14 升级：白透 0.7→0.5 + 边框加亮
  static BoxDecoration glassOverlay({
    double opacity = 0.5,
    double radius = 16,
  }) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.4),
        width: 1.2,
      ),
    );
  }

  // 强调玻璃（深色背景上用，白 → 黑）
  static BoxDecoration glassOnDark({
    double opacity = 0.15,
    double radius = 20,
  }) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.2),
        width: 1,
      ),
    );
  }

  // ========== 毛玻璃 Wrap（用于 AppBar / 顶栏） ==========
  // 用法: ClipRect(child: BackdropFilter(sigma: 30, child: Container(decoration: GlassStyle.glassOverlay())))
  // 6/14 升级：sigma 20→30（更糊）
  static const double backdropSigma = 30;

  // 6/14 强毛玻璃（Tinder 大卡 / 精要 banner 用）
  static const double backdropSigmaStrong = 25;

  // ========== 文字色（在玻璃上） ==========
  static const Color onGlassPrimary = Color(0xFF1a1a1a);
  static const Color onGlassSecondary = Color(0xFF666666);
  // 6/13 暗色文字色（玻璃在深背景上）
  static const Color onGlassPrimaryDark = Color(0xFFE8E8E8);
  static const Color onGlassSecondaryDark = Color(0xFFB0B0B0);

  // 6/13 护眼文字色（琥珀背景上偏暖深色）
  static const Color onGlassPrimaryWarm = Color(0xFF3A2A14);
  static const Color onGlassSecondaryWarm = Color(0xFF6B4A2A);

  // 根据 brightness 返回文字色
  static Color onGlassText(BuildContext c, {bool primary = true}) {
    final isDark = Theme.of(c).brightness == Brightness.dark;
    if (primary) {
      return isDark ? onGlassPrimaryDark : onGlassPrimary;
    }
    return isDark ? onGlassSecondaryDark : onGlassSecondary;
  }

  // ========== 强调色（操作按钮 / 链接） ==========
  static const Color accent = Color(0xFF4A6CF7);
  static const Color danger = Color(0xFFFF3B30);

  // ========== 6/14 visionOS Liquid 高光 token ==========
  // 顶部高光渐变 (30% 高度白 0.5 → 0)，模拟 iOS 27 / visionOS 玻璃上沿反射
  static const double liquidHighlightTopHeight = 0.3;
  static const double liquidHighlightBottomHeight = 0.15;

  // 胶囊底部导航背景 (全宽,圆角 28)
  static BoxDecoration glassCapsule({double radius = 28}) {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.4),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.55),
        width: 1.2,
      ),
      boxShadow: [
        // 接触阴影
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        // 顶部高光
        BoxShadow(
          color: Colors.white.withOpacity(0.6),
          blurRadius: 0.5,
          offset: const Offset(0, -0.5),
          spreadRadius: -0.5,
        ),
      ],
    );
  }

  // 高亮胶囊（当前 tab）：纯黑黄膏，内嵌发光描边
  static BoxDecoration glassLiquidHighlight({double radius = 20, Color? base}) {
    final c = base ?? accent;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          c.withOpacity(0.85),
          c.withOpacity(0.65),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withOpacity(0.4),
        width: 1.2,
      ),
      boxShadow: [
        // 外发光
        BoxShadow(
          color: c.withOpacity(0.4),
          blurRadius: 16,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
        // 顶部高光
        BoxShadow(
          color: Colors.white.withOpacity(0.5),
          blurRadius: 0.5,
          offset: const Offset(0, -0.5),
        ),
      ],
    );
  }

  // 水滴形按钮（高级按钮：圆角胶囊 + 厚玻璃 + 顶亮高光）
  static BoxDecoration glassLiquidButton({
    double radius = 24,
    Color? borderColor,
    double opacity = 0.5,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(opacity + 0.15),
          Colors.white.withOpacity(opacity - 0.05),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? Colors.white.withOpacity(0.5),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        // 顶高光
        BoxShadow(
          color: Colors.white.withOpacity(0.7),
          blurRadius: 0.5,
          offset: const Offset(0, -0.5),
          spreadRadius: -0.5,
        ),
      ],
    );
  }

  // 顶部弧形高光（贴 Liquid 玻璃上沿）
  static LinearGradient liquidTopHighlight({double opacity = 0.5}) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withOpacity(opacity),
        Colors.white.withOpacity(0),
      ],
      stops: const [0, liquidHighlightTopHeight],
    );
  }

  // 6/15 场景背景柔化:叠 18% 白渐变（6/14 是 70% 太厚,闷死）
  // 玻璃卡本身就是 0.3 透(下面 glassCard 默认值),所以背景透出 82% 即可
  // 6/12 老人宪法: scene 渐变的方向/色相不动
  static LinearGradient sceneBackgroundOverlay({double opacity = 0.18}) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withOpacity(opacity),
        Colors.white.withOpacity(opacity * 0.5),
      ],
    );
  }

  // 6/14 v5: 亮背景下玻璃卡 (暗边框 + 深阴影, 玻璃感靠轮廓不是白度)
  static BoxDecoration glassCardOnLight({double opacity = 0.65, double radius = 20}) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.black.withOpacity(0.06),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.10),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.white.withOpacity(0.8),
          blurRadius: 0.5,
          offset: const Offset(0, -0.5),
          spreadRadius: -0.5,
        ),
      ],
    );
  }

  // 6/19 加: AppBar 玻璃背景 + 返回箭头可见性 修正
  // 之前 AppBar 无 backgroundColor/foregroundColor = 透明 + theme 默认色
  // 在杏橘/content 背景下 leading Icons.arrow_back 几乎不可见
  // 用法: AppBar(backgroundColor: GlassStyle.glassAppBarBg(), foregroundColor: GlassStyle.glassAppBarFg(), elevation: 0.5, leading: ...)
  static Color get glassAppBarBg => Colors.white.withOpacity(0.85);
  static Color get glassAppBarFg => AppTheme.primary;  // #6750A4 紫
  static double get glassAppBarElevation => 0.5;
}
