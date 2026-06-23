// lib/widgets/skeleton.dart
// 骨架屏通用组件
import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: widget.borderRadius,
          ),
        ),
      ),
    );
  }
}

// 卡片骨架屏
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 420,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(children: [
          // 封面占位
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFFEEEEEE),
              child: const Center(
                child: SkeletonBox(width: 64, height: 64, borderRadius: BorderRadius.all(Radius.circular(32))),
              ),
            ),
          ),
          // 内容占位
          Expanded(
            flex: 4,
            child: Container(
              color: const Color(0xFFFAF0E6),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const SkeletonBox(width: 48, height: 20),
                  const SizedBox(width: 8),
                  const SkeletonBox(width: 32, height: 20),
                ]),
                const SizedBox(height: 12),
                const SkeletonBox(width: double.infinity, height: 18),
                const SizedBox(height: 8),
                const SkeletonBox(width: 200, height: 18),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: SkeletonBox(width: 72, height: 32, borderRadius: BorderRadius.circular(20)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// 列表项骨架屏
class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const SkeletonBox(width: 48, height: 48, borderRadius: BorderRadius.all(Radius.circular(10))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SkeletonBox(width: double.infinity, height: 14),
          const SizedBox(height: 6),
          SkeletonBox(width: MediaQuery.of(context).size.width * 0.4, height: 12),
        ])),
      ]),
    );
  }
}
