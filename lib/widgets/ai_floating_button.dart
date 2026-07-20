import 'package:flutter/material.dart';

/// 6/29 v1: AI 助手悬浮气泡 (内层, 圆形 + icon + badge)
class AiFloatingFab extends StatelessWidget {
  final VoidCallback onTap;
  final bool isElderlyMode;
  final String? badgeText;

  const AiFloatingFab({
    super.key,
    required this.onTap,
    this.isElderlyMode = false,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    final size = isElderlyMode ? 80.0 : 64.0;
    final iconSize = isElderlyMode ? 32.0 : 26.0;
    final fontSize = isElderlyMode ? 13.0 : 11.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            // 7/19 fix v2: LinearGradient 全量清除
            color: const Color(0xFF7C5CFC),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C5CFC).withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.support_agent,
                color: Colors.white,
                size: iconSize,
              ),
              // 顶部高光弧 (玻璃感)
              Positioned(
                top: 6,
                left: 8,
                right: 8,
                child: Container(
                  height: size * 0.25,
                  decoration: BoxDecoration(
                    // 7/19 fix v2: 顶高光弧 LinearGradient 全量清除
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(size / 2),
                  ),
                ),
              ),
              if (badgeText != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4B6E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      badgeText!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 6/29 v1: Scaffold.floatingActionButton 用的封装 (贴右下角, 老人模式大一点)
class AiFloatingButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isElderlyMode;
  final String? badgeText;

  const AiFloatingButton({
    super.key,
    required this.onTap,
    this.isElderlyMode = false,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        right: 0,
        bottom: isElderlyMode ? 24.0 : 16.0,
      ),
      child: AiFloatingFab(
        onTap: onTap,
        isElderlyMode: isElderlyMode,
        badgeText: badgeText,
      ),
    );
  }
}
