// lib/widgets/tinder_recommendation_stack.dart
// 6/13 Tinder 风格推荐卡
// 一次只看 1 张大卡（顶），后面 2 张缩略压在下面
// 三个动作：
//   1) ❌ 点不喜：自动推下一张 + 写 pref_dismissed
//   2) ❤️ 点收藏：写 pref_liked + 弹 snackbar + 调 LocalSubscriptionService.subscribe
//   3) 👆 点卡片 = 进详情/听/跳原站（调原来 onTap 逻辑）
// 老人模式：按钮加大（minSize 56x56）；普通模式按钮标准

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/user_preference_service.dart';
import '../services/eye_protection_scope.dart';
import '../services/local_subscription_service.dart';
import '../theme/glass_decoration.dart';
import 'dart:ui';

class TinderRecommendationStack extends StatefulWidget {
  final List<ContentItem> items;
  final UserType userType;
  final Scene scene;
  final bool isEn;
  final bool isElderlyMode;
  final Future<void> Function(ContentItem item)? onTapItem;
  final VoidCallback? onAllDismissed;

  const TinderRecommendationStack({
    super.key,
    required this.items,
    required this.userType,
    required this.scene,
    required this.isEn,
    required this.isElderlyMode,
    this.onTapItem,
    this.onAllDismissed,
  });

  @override
  State<TinderRecommendationStack> createState() =>
      _TinderRecommendationStackState();
}

class _TinderRecommendationStackState extends State<TinderRecommendationStack>
    with SingleTickerProviderStateMixin {
  late List<ContentItem> _items;
  int _topIndex = 0; // 当前顶卡在 _items 里的 index
  late AnimationController _swipeCtrl;
  bool _swiping = false;

  // 已交互过的 id（view + like + dismiss）—— 都不再推
  Set<String> _seenIds = {};

  double get _scale => widget.isElderlyMode ? 1.3 : 1.0;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _items = List.from(widget.items);
    // 老人模式强制按钮（不接 swipe gesture）
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    super.dispose();
  }

  void _animateOut({required bool toLeft, required VoidCallback onDone}) {
    if (_swiping) return;
    _swiping = true;
    final begin = 0.0;
    final end = 1.0;
    _swipeCtrl
      ..reset()
      ..forward()
      .whenComplete(() {
        _swiping = false;
        onDone();
      });
  }

  Future<void> _onDismiss(ContentItem item) async {
    setState(() {
      _seenIds.add(item.id);
      _topIndex = (_topIndex + 1).clamp(0, _items.length - 1);
    });
    await UserPreferenceService.instance.record(
      action: PrefAction.dismiss,
      item: item,
      userType: widget.userType,
      scene: widget.scene,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isEn ? 'Skipped: ${item.title}' : '已跳过：${item.title}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (_topIndex >= _items.length) {
      widget.onAllDismissed?.call();
    }
  }

  Future<void> _onLike(ContentItem item) async {
    setState(() {
      _seenIds.add(item.id);
      _topIndex = (_topIndex + 1).clamp(0, _items.length - 1);
    });
    await UserPreferenceService.instance.record(
      action: PrefAction.like,
      item: item,
      userType: widget.userType,
      scene: widget.scene,
    );
    await LocalSubscriptionService.instance.subscribe(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.isEn ? 'Saved: ${item.title}' : '已收藏：${item.title}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (_topIndex >= _items.length) {
      widget.onAllDismissed?.call();
    }
  }

  /// 点入 = 进详情。看完返回后自动 skip。
  Future<void> _onTapItem(ContentItem item) async {
    if (widget.onTapItem == null) return;
    // onTapItem 内部 await Navigator.push —— 详情页返回 = future 完成
    await widget.onTapItem!(item);
    if (!mounted) return;
    // 详情返回后：写 view + 推下一条
    setState(() {
      _seenIds.add(item.id);
      _topIndex = (_topIndex + 1).clamp(0, _items.length - 1);
    });
    await UserPreferenceService.instance.record(
      action: PrefAction.view,
      item: item,
      userType: widget.userType,
      scene: widget.scene,
    );
    if (!mounted) return;
    if (_topIndex >= _items.length) {
      widget.onAllDismissed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWarm = EyeProtectionScope.of(context);
    if (_items.isEmpty || _topIndex >= _items.length) {
      return _buildEmpty(isDark: isDark, isWarm: isWarm);
    }
    // 顶卡 + 后两张缩略
    final top = _items[_topIndex];
    final mid = _topIndex + 1 < _items.length ? _items[_topIndex + 1] : null;
    final bot = _topIndex + 2 < _items.length ? _items[_topIndex + 2] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部进度指示
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                widget.isEn
                    ? 'Discover ${_topIndex + 1} / ${_items.length}'
                    : '发现 ${_topIndex + 1} / ${_items.length}',
                style: TextStyle(
                  fontSize: 12 * _scale,
                  color: (isDark ? GlassStyle.onGlassPrimaryDark : GlassStyle.onGlassPrimary).withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 6/15 v2: 240→520 卡高 ≈屏 70% (Tinder 真实比例)
        SizedBox(
          height: 520,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 6/14 v5.3: 14→8 / 8→4 后面卡不推那么下
              // 6/18 修: 背景卡包 IgnorePointer,desktop 端点顶卡下半不会先 hit 到 mid
              if (bot != null)
                IgnorePointer(
                  child: _buildBackgroundCard(bot, scale: 0.86, offsetY: 8, opacity: 0.6, isDark: isDark, isWarm: isWarm),
                ),
              if (mid != null)
                IgnorePointer(
                  child: _buildBackgroundCard(mid, scale: 0.93, offsetY: 4, opacity: 0.85, isDark: isDark, isWarm: isWarm),
                ),
              _buildTopCard(top, isDark: isDark, isWarm: isWarm),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 三个动作按钮
        _buildActionRow(top),
      ],
    );
  }

  Widget _buildTopCard(ContentItem item, {required bool isDark, required bool isWarm}) {
    return _buildCard(item, isTop: true, isDark: isDark, isWarm: isWarm);
  }

  Widget _buildBackgroundCard(
    ContentItem item, {
    required double scale,
    required double offsetY,
    required double opacity,
    required bool isDark,
    required bool isWarm,
  }) {
    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: _buildCard(item, isTop: false, isDark: isDark, isWarm: isWarm),
        ),
      ),
    );
  }
  Widget _buildCard(ContentItem item,
      {double scale = 1.0, bool isTop = true, required bool isDark, required bool isWarm}) {
    final isVideo = item.contentType == ContentType.video;
    final primary = isWarm
        ? GlassStyle.onGlassPrimaryWarm
        : isDark
            ? GlassStyle.onGlassPrimaryDark
            : GlassStyle.onGlassPrimary;
    final secondary = isWarm
        ? GlassStyle.onGlassSecondaryWarm
        : isDark
            ? GlassStyle.onGlassSecondaryDark
            : GlassStyle.onGlassSecondary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.05), width: 1),
            boxShadow: [
              // 6/15 v2: 0 4 12 0.08 (Tinder 真实阴影)
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: isTop ? () => _onTapItem(item) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 6/15 v2: 上 75% = scene 色相大色块 + 中心大 icon (当图用)
                  Expanded(
                    flex: 3,
                    child: _buildImageArea(item, isTop: isTop),
                  ),
                  // 6/15 v2: 下 25% = 标题+元数据, 紧贴上图 0px
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 * _scale, 10 * _scale, 16 * _scale, 14 * _scale,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17 * _scale,
                              fontWeight: FontWeight.w700,
                              color: primary,
                              height: 1.15,
                            ),
                          ),
                          SizedBox(height: 4 * _scale),
                          Row(
                            children: [
                              Text(
                                item.source,
                                style: TextStyle(
                                  fontSize: 11 * _scale,
                                  color: primary,  // 6/15 v2.1
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('·', style: TextStyle(fontSize: 11, color: primary)),
                              const SizedBox(width: 6),
                              Icon(Icons.access_time, size: 11, color: primary),
                              const SizedBox(width: 3),
                              Text(
                                item.duration,
                                style: TextStyle(
                                  fontSize: 11 * _scale,
                                  color: primary,  // 6/15 v2.1
                                ),
                              ),
                              const Spacer(),
                              if (isTop)
                                Text(
                                  widget.isEn ? 'Tap →' : '阅读 →',
                                  style: TextStyle(
                                    fontSize: 11 * _scale,
                                    color: GlassStyle.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 6/15 v2: 上半 75% 图区域 — scene 色相渐变 + 中心大 icon
  Widget _buildImageArea(ContentItem item, {required bool isTop}) {
    final gradColors = _gradForContent(item);
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Center(
          child: Icon(
            item.contentType.icon,
            size: 64 * _scale,
            color: Colors.white.withOpacity(0.85),
          ),
        ),
        if (isTop)
          Positioned(
            top: 12 * _scale,
            left: 12 * _scale,
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: 10 * _scale, vertical: 4 * _scale),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item.contentType.name,
                style: TextStyle(
                  fontSize: 11 * _scale,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 按内容类型给 2 色渐变
  List<Color> _gradForContent(ContentItem item) {
    switch (item.contentType.name) {
      case 'article': return [const Color(0xFF7C5CFC), const Color(0xFFA48BFF)];
      case 'audio':   return [const Color(0xFF0891B2), const Color(0xFF67E8F9)];
      case 'video':   return [const Color(0xFFEA580C), const Color(0xFFFDBA74)];
      case 'short':   return [const Color(0xFF16A34A), const Color(0xFF86EFAC)];
      case 'card':    return [const Color(0xFFDB2777), const Color(0xFFFBCFE8)];
      default:        return [const Color(0xFF6B7280), const Color(0xFFD1D5DB)];
    }
  }  Widget _buildActionRow(ContentItem item) {
    final btnSize = widget.isElderlyMode ? 64.0 : 52.0;
    final iconSize = widget.isElderlyMode ? 30.0 : 24.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // ❌ 跳过
        _ActionButton(
          size: btnSize,
          icon: Icons.close,
          color: GlassStyle.danger,
          tooltip: widget.isEn ? 'Skip' : '跳过',
          onTap: () => _onDismiss(item),
        ),
        // 👆 进入
        _ActionButton(
          size: btnSize,
          icon: Icons.touch_app,
          color: GlassStyle.accent,
          tooltip: widget.isEn ? 'Open' : '进入',
          onTap: () => _onTapItem(item),
        ),
        // ❤️ 收藏
        _ActionButton(
          size: btnSize,
          icon: Icons.favorite,
          color: const Color(0xFFFF6B9D),
          tooltip: widget.isEn ? 'Save' : '收藏',
          onTap: () => _onLike(item),
        ),
      ],
    );
  }

  Widget _buildEmpty({required bool isDark, required bool isWarm}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration, size: 48, color: (isWarm
              ? GlassStyle.onGlassPrimaryWarm
              : isDark
                  ? GlassStyle.onGlassPrimaryDark
                  : GlassStyle.onGlassPrimary).withOpacity(0.7)),
          const SizedBox(height: 12),
          Text(
            widget.isEn ? 'You\'ve seen them all!' : '看完啦！',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isWarm
                  ? GlassStyle.onGlassPrimaryWarm
                  : isDark
                      ? GlassStyle.onGlassPrimaryDark
                      : GlassStyle.onGlassPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isEn
                ? 'Your preferences are saved. Coming recommendations will be smarter.'
                : '偏好已记录，下次推荐会更懂你。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: (isWarm
                      ? GlassStyle.onGlassPrimaryWarm
                      : isDark
                          ? GlassStyle.onGlassPrimaryDark
                          : GlassStyle.onGlassPrimary)
                  .withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final double size;
  final double iconSize;
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.size,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    // 6/14 visionOS 风格：圆形 → 大圆角胶囊(更像水滴)
    final radius = size * 0.42; // 接近正圆但保留小角度偏移感
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          // 6/14 升级：20→30 (Liquid 高模糊)
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Material(
            // 6/14 升级：glassLiquidButton 渐变高光
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
            child: InkWell(
              onTap: onTap,
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              child: Container(
                width: size,
                height: size,
                decoration: GlassStyle.glassLiquidButton(
                  radius: radius,
                  borderColor: color.withOpacity(0.45),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 6/14 顶亮高光：上半部圆弧白渐变
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            height: size * 0.4,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withOpacity(0.35),
                                  Colors.white.withOpacity(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Icon(icon, color: color, size: iconSize),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
