import 'package:flutter/material.dart';
import 'ai_assistant_screen.dart';
import '../services/robot_name_service.dart';

/// 6/30 00:15: AI 助手 tab 0 — 跟支付宝"支"首页布局类似
/// - 大紫色圆形头像 (support_agent icon)
/// - "AI 助手" 大标题
/// - 副标题
/// - 大紫按钮 "跟我聊聊" → 弹 chat sheet
/// - chip 行 (复用 25 chip, 点直接渲染紫卡)
class AiTabScreen extends StatelessWidget {
  const AiTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 大紫色圆形头像
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x407C5CFC),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.support_agent,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            // 6/30 00:20: 显示 AI 机器人昵称 (默认 "小O", 设置可改)
            ValueListenableBuilder<String>(
              valueListenable: RobotNameService.notifier,
              builder: (_, name, __) => Text(
                name,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '跟我聊 · 推荐 5 分钟阅读 · 解答疑问',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // 大紫按钮 — 弹 chat sheet
            SizedBox(
              width: double.infinity,
              child: Material(
                color: const Color(0xFF7C5CFC),
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
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
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.chat_bubble, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text(
                          '跟我聊聊',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // 快速推荐标题
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '快速推荐',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 提示: 点 chip 直接渲染紫卡 (从 ai_assistant_screen 复用)
            _QuickPrompts(),
          ],
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
