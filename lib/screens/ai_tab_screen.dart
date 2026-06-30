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
          gradient: GlassStyle.sceneBackgroundOverlay(),
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
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
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
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
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
class _QuickPrompts extends StatelessWidget {
  static const _chips = <_ChipDef>[
    _ChipDef('🇬🇧', 'BBC 英语'),
    _ChipDef('🎧', '新概念英语'),
    _ChipDef('🧘', '5 分钟冥想'),
    _ChipDef('🌿', '白噪音'),
    _ChipDef('📰', '今日新闻'),
    _ChipDef('💼', '哈佛商业'),
    _ChipDef('📚', '樊登读书'),
    _ChipDef('🎓', '睡前英语'),
    _ChipDef('🔬', '今日科普'),
    _ChipDef('🏛', '中学古诗'),
    _ChipDef('📊', 'OKR 入门'),
    _ChipDef('🧠', '深度工作'),
    _ChipDef('💰', '谈加薪'),
    _ChipDef('🏆', '精益创业'),
    _ChipDef('📈', '增长黑客'),
    _ChipDef('👨‍👩‍👧', '正面管教'),
    _ChipDef('👨‍👦', '孩子磨蹭'),
    _ChipDef('🏃', '跑步热身'),
    _ChipDef('💪', '眼保健操'),
    _ChipDef('😴', '考前放空'),
    _ChipDef('🍅', '番茄钟'),
    _ChipDef('📐', '物理入门'),
    _ChipDef('🏛', '历史今天'),
    _ChipDef('🌙', '凌晨冥想'),
    _ChipDef('🌅', '会议拉伸'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _chips.map((c) => _ChipButton(def: c)).toList(),
    );
  }
}

class _ChipDef {
  final String emoji;
  final String label;
  const _ChipDef(this.emoji, this.label);
}

class _ChipButton extends StatelessWidget {
  final _ChipDef def;
  const _ChipButton({required this.def});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Text(def.emoji, style: const TextStyle(fontSize: 14)),
      label: Text(def.label, style: const TextStyle(fontSize: 13)),
      backgroundColor: const Color(0xFF7C5CFC).withOpacity(0.08),
      side: BorderSide(color: const Color(0xFF7C5CFC).withOpacity(0.3)),
      onPressed: () {
        // 6/30 00:18: chip 简化为弹 chat sheet, 走跟按钮一样的路径
        // 内部用 sheet 内的 25 chip 机制 (0 LLM)
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
    );
  }
}
