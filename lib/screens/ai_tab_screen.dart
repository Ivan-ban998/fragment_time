import 'package:flutter/material.dart';
import 'ai_assistant_screen.dart';
import '../theme/glass_decoration.dart';

/// 6/30 09:32: AI 助手 tab 0 — 工具感
/// 删大紫圈头像/昵称/全宽按钮/25 chip
/// 改为: AppBar 简洁标题 + 3 个玻璃化能力卡 (自由聊/推荐/答疑)
/// 跟其他 Tab 视觉风格统一
class AiTabScreen extends StatelessWidget {
  const AiTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 8/7 加 (沿 SOUL #137): ThemeMode-aware 背景兑色
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: const Text(
          'AI 助手',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          // 7/19 fix v2: LinearGradient 全量清除
          // 8/7 改 (沿 SOUL #137): dark 参数跟 ThemeMode 走
          color: GlassStyle.sceneBackgroundOverlay(dark: isDark),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            children: const [
              Padding(
                padding: EdgeInsets.only(bottom: 24, left: 4),
                child: Text(
                  '对话 · 推荐 · 答疑',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
              _AbilityCard(
                icon: Icons.chat_bubble_outline,
                title: '自由聊',
                desc: '问啥都行，想聊就聊',
                color: Color(0xFF7C5CFC),
              ),
              SizedBox(height: 12),
              _AbilityCard(
                icon: Icons.auto_stories_outlined,
                title: '帮我推荐',
                desc: '5 分钟找点有意思的内容',
                color: Color(0xFF5B7CFA),
              ),
              SizedBox(height: 12),
              _AbilityCard(
                icon: Icons.lightbulb_outline,
                title: '答疑解惑',
                desc: '基于今天读过的内容帮你理清',
                color: Color(0xFF7C5CFC),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AbilityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  const _AbilityCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            builder: (_) => AiAssistantScreen(
              isEn: false,
              isElderlyMode: false,
              userTypeName: '你',
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  // 7/19 fix v2: LinearGradient 全量清除
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 6/30 00:15: chip 行 — 复用 25 chip, 简化版 (只显示 label, 弹 sheet 跟 AI 助手一样)


