import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';

/// 6/12 加: 首次启动 30s 引导（3 步 + 跳过）
/// 完成后写 SharedPreferences 标记，下次不再弹
///
/// 6/30 12:11 DEPRECATED: Brien 6/18 判定 30s 引导是累赘, main.dart `_checkOnboarding` 强制写 prefs true + 设 `_showOnboarding=false`
/// 这个 widget 永远不会被渲染. 保留是为了: (1) 防止 main.dart import 报错 (2) 万一以后 Brien 要恢复可用
/// **不要在这个 widget 上加新逻辑, 也不要在 main.dart 调用它**
class OnboardingScreen extends StatefulWidget {
  static const _kShownKey = 'onboarding_shown_v1';

  static Future<bool> hasShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kShownKey) ?? false;
  }

  final bool isEn;
  final UserType? selectedUserType;
  final ValueChanged<UserType> onUserTypeSelected;
  final VoidCallback onSkip;

  const OnboardingScreen({
    super.key,
    required this.isEn,
    required this.onSkip,
    this.selectedUserType,
    required this.onUserTypeSelected,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _curPage = 0;

  Future<void> _markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen._kShownKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    // 6/14 v4 onboarding 玻璃化:场景柔化背景 + BackdropFilter
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFCE7F3), Color(0xFFE0E7FF)], // 玻璃下幕: 薄粉→淑紫
          ),
        ),
        child: Stack(
          children: [
            // 6/14 v4: 背景柔化叠层
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: GlassStyle.sceneBackgroundOverlay(opacity: 0.3),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // 跳过
                  Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: () async {
                        await _markShown();
                        widget.onSkip();
                      },
                      child: Text(widget.isEn ? 'Skip' : '跳过'),
                    ),
                  ),
                  // 页面
                  Expanded(
                    child: PageView.builder(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _curPage = i),
                      itemCount: pages.length,
                      itemBuilder: (_, i) => pages[i],
                    ),
                  ),
                  // 6/14 v4 圆点胶囊化
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(pages.length, (i) {
                              final sel = i == _curPage;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: sel ? 22 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  gradient: sel
                                      ? LinearGradient(colors: [GlassStyle.accent, GlassStyle.accent.withOpacity(0.6)])
                                      : null,
                                  color: sel ? null : Colors.white.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 底部按钮 (Liquid)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [GlassStyle.accent, GlassStyle.accent.withOpacity(0.7)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: GlassStyle.accent.withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  if (_curPage < pages.length - 1) {
                                    _pageCtrl.nextPage(
                                      duration: const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                    );
                                  } else {
                                    await _markShown();
                                    widget.onSkip();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Text(
                                    _curPage < pages.length - 1
                                        ? (widget.isEn ? 'Next' : '下一步')
                                        : (widget.isEn ? 'Get Started' : '开始使用'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  List<Widget> _buildPages() {
    final isEn = widget.isEn;
    return [
      _page(
        icon: Icons.access_time_filled,
        color: Colors.indigo,
        title: isEn ? '5-minute fragments' : '5 分钟碎片',
        body: isEn
            ? 'Pick a moment, get a 5-minute piece of content that fits.\nNo hour-long videos. No infinite scrolling.'
            : '挑个时间，给你 5 分钟合身的内容。\n不灌长视频，不无限滚。',
      ),
      _page(
        icon: Icons.tune,
        color: Colors.teal,
        title: isEn ? '6 roles × 4 scenes' : '6 角色 × 4 场景',
        body: isEn
            ? 'You\'re a student, a parent, an entrepreneur, or 60+.\nWe split content for you — not for everyone.'
            : '你是学生、家长、创业者、或 60+。\n按你分桶——不是按所有人。',
      ),
      _page(
        icon: Icons.psychology,
        color: Colors.deepPurple,
        title: isEn ? 'AI coach on demand' : 'AI 私教随叫随到',
        body: isEn
            ? 'Tap any content for an AI summary.\nGet a weekly recap of what you actually read.'
            : '点任意内容就有 AI 总结。\n每周回顾你真正读了什么。',
      ),
    ];
  }

  Widget _page({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 6/14 v4 图标圆 → 水滴 (大圆角胶囊)
          ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                width: 112,
                height: 112,
                decoration: GlassStyle.glassLiquidButton(
                  radius: 40,
                  borderColor: color.withOpacity(0.4),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            height: 45,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withOpacity(0.4),
                                  Colors.white.withOpacity(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Icon(icon, size: 52, color: color),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textDark.withOpacity(0.75),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
