// lib/widgets/tinder_recommendation_stack.dart
// 6/22 重写: 借鉴别的 AI 那个 537 行简化版的 GestureDetector 模式 (整卡包 GestureDetector,
//   onTap = 闭包 push prefill, onPan 跟 _dragOffset + _animateOut 飞出).
// 改用 GestureDetector 替换 6/16 那个 InkWell + IgnorePointer 嵌套 (1.5h 改 5 次没验过).
//
// 父 widget 接口 (ContentScreen 调用) 不变:
//   onTapItem: (it) async { await Navigator.push(...) }  ← 闭包
//   onAllDismissed: ()  ← 6 张全看完
//
// 三个动作:
//   1) ❌ Icons.close = 跳过 (推下一张, 写 pref_dismissed)
//   2) 👆 Icons.touch_app = 详情 (调 widget.onTapItem 闭包 push prefill)
//   3) ❤️ Icons.favorite = 收藏 (LocalSubscriptionService.subscribe + snackbar)

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/user_preference_service.dart';
import '../services/eye_protection_scope.dart';
import '../services/local_subscription_service.dart';
import '../theme/glass_decoration.dart';

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
    this.isElderlyMode = false,
    this.onTapItem,
    this.onAllDismissed,
  });

  @override
  State<TinderRecommendationStack> createState() =>
      _TinderRecommendationStackState();
}

class _TinderRecommendationStackState extends State<TinderRecommendationStack> {
  int _topIndex = 0;
  // 拖拽状态 (借鉴 537 行简化版)
  Offset _dragOffset = Offset.zero;
  double _dragAngle = 0;
  bool _isDragging = false;
  // 6/16 老版: 已交互 ids (view + like + dismiss)
  final Set<String> _seenIds = {};

  @override
  void initState() {
    super.initState();
    // 父 widget 传 items
  }

  void _onPanStart(DragStartDetails d) {
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset += d.delta;
      _dragAngle = _dragOffset.dx * 0.0008;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    final dx = _dragOffset.dx;
    if (dx < -80) {
      _animateOut(const Offset(-600, -50), onLeft: true);
    } else if (dx > 80) {
      _animateOut(const Offset(600, -50), onLeft: false);
    } else {
      setState(() {
        _dragOffset = Offset.zero;
        _dragAngle = 0;
        _isDragging = false;
      });
    }
  }

  Future<void> _animateOut(Offset direction, {required bool onLeft}) async {
    setState(() => _dragOffset = direction);
    // 调 pref_dismissed / pref_liked
    if (_topIndex < _items.length) {
      final item = _items[_topIndex];
      try {
        await UserPreferenceService.instance.record(
          action: onLeft ? PrefAction.dismiss : PrefAction.like,
          item: item,
          userType: widget.userType,
          scene: widget.scene,
        );
      } catch (_) {}
      _seenIds.add(item.id);
    }
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _topIndex++;
      _dragOffset = Offset.zero;
      _dragAngle = 0;
      _isDragging = false;
    });
    if (_topIndex >= _items.length) {
      widget.onAllDismissed?.call();
    }
  }

  // 3 圆按钮回调
  Future<void> _onDismiss(ContentItem item) async {
    await _animateOut(const Offset(-600, -50), onLeft: true);
  }

  Future<void> _onLike(ContentItem item) async {
    try {
      await LocalSubscriptionService.instance.subscribe(item);
      await UserPreferenceService.instance.record(
        action: PrefAction.like,
        item: item,
        userType: widget.userType,
        scene: widget.scene,
      );
    } catch (_) {}
    _seenIds.add(item.id);
    if (!mounted) return;
    setState(() => _topIndex++);
    if (_topIndex >= _items.length) {
      widget.onAllDismissed?.call();
    } else {
      // snackbar 反馈
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEn ? 'Saved: ${item.title}' : '已收藏：${item.title}'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onTapItem(ContentItem item) async {
    if (widget.onTapItem == null) return;
    try {
      await widget.onTapItem!(item);
    } catch (_) {}
    if (!mounted) return;
    // 详情返回后: 写 view + 推下一张
    _seenIds.add(item.id);
    try {
      await UserPreferenceService.instance.record(
        action: PrefAction.view,
        item: item,
        userType: widget.userType,
        scene: widget.scene,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _topIndex++);
    if (_topIndex >= _items.length) {
      widget.onAllDismissed?.call();
    }
  }

  List<ContentItem> get _items {
    // 过滤已 seen 的 (但保留顺序, 跳过的不删只 push 索引)
    return widget.items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty || _topIndex >= items.length) {
      return _buildEmpty();
    }
    final top = items[_topIndex];
    final mid = _topIndex + 1 < items.length ? items[_topIndex + 1] : null;
    final bot = _topIndex + 2 < items.length ? items[_topIndex + 2] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 进度
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                widget.isEn
                    ? 'Discover ${_topIndex + 1} / ${items.length}'
                    : '发现 ${_topIndex + 1} / ${items.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 460, // 借鉴简化版比例 (16+8+460+8+actionBar)
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 借鉴简化版 3 张叠放 (倒序绘制, bot 在最底)
              if (bot != null)
                _buildBackgroundCard(bot, offset: 2, scale: 0.94, opacity: 0.5),
              if (mid != null)
                _buildBackgroundCard(mid, offset: 1, scale: 0.97, opacity: 0.75),
              _buildTopCard(top),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 3 圆按钮 (借鉴简化版 _actionButton 模式)
        _buildActionBar(top),
      ],
    );
  }

  Widget _buildBackgroundCard(ContentItem item, {required int offset, required double scale, required double opacity}) {
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16.0 + offset * 6,
          8.0 + offset * 6,
          16.0 + offset * 6,
          8,
        ),
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: IgnorePointer(
              // 6/22 借鉴简化版: 背景卡包 IgnorePointer 避免 desktop 命中穿透
              child: _buildCard(item, isTop: false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopCard(ContentItem item) {
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        // 6/22 借鉴简化版关键: 整卡用 GestureDetector 包裹 (不是 InkWell 嵌套)
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onTap: () => _onTapItem(item),
          child: AnimatedContainer(
            duration: _isDragging
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            transform: Matrix4.identity()
              ..translate(_dragOffset.dx, _dragOffset.dy)
              ..rotateZ(_dragAngle),
            child: Stack(
              children: [
                _buildCard(item, isTop: true),
                // 拖动时的 label 提示 (借鉴简化版 _buildSwipeLabel)
                if (_dragOffset.dx < -30)
                  Positioned(
                    top: 24,
                    left: 24,
                    child: _buildSwipeLabel(
                      widget.isEn ? 'Skip' : '跳过',
                      Colors.red,
                      Icons.close,
                    ),
                  ),
                if (_dragOffset.dx > 30)
                  Positioned(
                    top: 24,
                    right: 24,
                    child: _buildSwipeLabel(
                      widget.isEn ? 'Like' : '喜欢',
                      Colors.pink,
                      Icons.favorite,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeLabel(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCard(ContentItem item, {required bool isTop}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWarm = EyeProtectionScope.of(context);
    final color = isWarm
        ? const Color(0xFFFAF0E6)
        : isDark
            ? const Color(0xFF2A2A2A)
            : Colors.white;
    final textColor = isWarm
        ? const Color(0xFF3D2817)
        : isDark
            ? Colors.white
            : const Color(0xFF3D2817);

    return Card(
      elevation: isTop ? 8 : 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 6/22 简化: 上半 = 渐变 + 大 icon (scene 色相)
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _gradForContent(item),
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      item.contentType.icon,
                      size: 72,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.contentType.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 下半 = 文字区 (白底 / 浅桃底 + 深棕字)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A237E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.source,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.access_time, size: 11, color: textColor.withOpacity(0.6)),
                      const SizedBox(width: 3),
                      Text(
                        item.duration,
                        style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.6)),
                      ),
                      const Spacer(),
                      if (isTop)
                        Text(
                          widget.isEn ? 'Read →' : '阅读 →',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1E40AF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _gradForContent(ContentItem item) {
    switch (item.contentType.name) {
      case 'article': return [const Color(0xFF7C5CFC), const Color(0xFFA48BFF)];
      case 'audio':   return [const Color(0xFF0891B2), const Color(0xFF67E8F9)];
      case 'video':   return [const Color(0xFFEA580C), const Color(0xFFFDBA74)];
      case 'short':   return [const Color(0xFF16A34A), const Color(0xFF86EFAC)];
      case 'card':    return [const Color(0xFFDB2777), const Color(0xFFFBCFE8)];
      default:        return [const Color(0xFF6B7280), const Color(0xFFD1D5DB)];
    }
  }

  Widget _buildActionBar(ContentItem item) {
    final size = widget.isElderlyMode ? 64.0 : 52.0;
    final iconSize = widget.isElderlyMode ? 30.0 : 24.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(
            icon: Icons.close,
            color: Colors.red,
            size: size,
            iconSize: iconSize,
            onTap: () => _onDismiss(item),
            label: widget.isEn ? 'Skip' : '跳过',
          ),
          _actionButton(
            icon: Icons.touch_app,
            color: const Color(0xFF7C5CFC),
            size: size,
            iconSize: iconSize,
            onTap: () => _onTapItem(item),
            label: widget.isEn ? 'Detail' : '详情',
          ),
          _actionButton(
            icon: Icons.favorite,
            color: Colors.pink,
            size: size,
            iconSize: iconSize,
            onTap: () => _onLike(item),
            label: widget.isEn ? 'Like' : '喜欢',
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required double size,
    required double iconSize,
    required VoidCallback onTap,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: color.withOpacity(0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.indigo.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            widget.isEn ? '🎉 All done!' : '🎉 看完啦！',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
