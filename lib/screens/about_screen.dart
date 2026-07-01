// lib/screens/about_screen.dart
// 关于 FragmentTime
// 2026-06-06 改：从一行"v0.1.0" 升级为完整介绍页

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // 7/1: RenderRepaintBoundary 截图
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data'; // 7/1: ByteData base64Encode
import 'dart:ui' as ui; // 7/1: 反馈截图 ui.Image
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import 'dart:ui';

class AboutScreen extends StatelessWidget {
  final String languageCode;

  const AboutScreen({super.key, required this.languageCode});

  bool get isEn => languageCode == 'en';

  // 7/1: 公开静态入口, 让 settings_tab 也能调反馈 dialog (不需要 push AboutScreen)
  static Future<void> showFeedbackDialog(BuildContext context, String languageCode) async {
    final isEn = languageCode == 'en';
    final ctrl = TextEditingController();
    bool attachScreenshot = true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Row(
            children: [
              const Text('🐙 '),
              Text(isEn ? 'Talk to 章鱼' : '跟章鱼说话'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEn
                    ? 'Your message will be sent directly to the author\'s NAS. Optional screenshot helps locate bugs.'
                    : '反馈会直接发到作者 NAS。可选截图方便定位问题。',
                style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 5,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: isEn ? 'Bug report / idea / anything...' : 'Bug / 想法 / 任何事...',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: attachScreenshot,
                onChanged: (v) => setState(() => attachScreenshot = v ?? true),
                title: Text(isEn ? 'Attach screenshot (web only)' : '附带截图 (仅网页版)', style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isEn ? 'Cancel' : '取消')),
            FilledButton(
              onPressed: () async {
                final msg = ctrl.text.trim();
                if (msg.isEmpty) return;
                Navigator.pop(ctx, msg + '|||' + attachScreenshot.toString());
              },
              child: Text(isEn ? 'Send' : '发送'),
            ),
          ],
        );
      }),
    );
    if (result == null || !context.mounted) return;
    final parts = result.split('|||');
    final msg = parts[0];
    final attach = parts.length > 1 ? parts[1] == 'true' : true;
    String? screenshotB64;
    if (attach) {
      try {
        screenshotB64 = await _captureScreenshot();
      } catch (e) {
        // 忽略
      }
    }
    final ok = await _submitFeedback(msg, screenshotB64, languageCode);
    if (!context.mounted) return;
    _showFloatingSnackStatic(
      context,
      ok
          ? (isEn ? 'Sent to author NAS! 🐙' : '已发到作者 NAS! 🐙')
          : (isEn ? 'Saved locally, will retry later.' : '已本地保存,稍后重试。'),
    );
  }

  // 7/1: 静态 SnackBar 提示 (供 showFeedbackDialog 调用, 不依赖 instance)
  static void _showFloatingSnackStatic(BuildContext context, String msg) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(isEn ? 'About FragmentTime' : '关于 FragmentTime'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 头部 logo + 名称
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.schedule, size: 48, color: AppTheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  'FragmentTime',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(
                  isEn ? 'Your AI-powered time fragment companion' : 'AI 驱动的碎片时间陪伴',
                  style: TextStyle(fontSize: 14, color: AppTheme.textLight),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isEn ? 'v0.1.0 (pre-alpha)' : 'v0.1.0（早期内测）',
                    style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // 核心定位
          _buildSection(
            icon: Icons.auto_awesome,
            title: isEn ? 'What is it?' : '这是什么',
            content: isEn
                ? 'FragmentTime is a Flutter web app that turns your 5-minute time gaps into meaningful moments. '
                    'Pick who you are, what you want to do, and we generate a piece of content tailored to you — '
                    'in real time, by a local AI model.'
                : 'FragmentTime 是一款 Flutter Web 应用，把你的 5 分钟碎片时间变成有意义的瞬间。'
                    '选一个身份、选一个场景，本地 AI 实时为你生成一段内容。',
          ),
          const SizedBox(height: 20),

          // 6 个 user type
          _buildSection(
            icon: Icons.people_outline,
            title: isEn ? '6 identities, all ages' : '6 个身份，覆盖全年龄',
            content: isEn
                ? '• Student — exam prep, study, interests\n'
                    '• Office worker — career skills, commute learning\n'
                    '• Entrepreneur — business trends, management, decisions\n'
                    '• Parent — parenting, family time, education\n'
                    '• Senior — health, hobbies, slow life\n'
                    '• Child — stories, science, gentle fun'
                : '• 学生 — 考试考证、学业提升、兴趣拓展\n'
                    '• 上班族 — 职场技能、通勤学习\n'
                    '• 创业者 — 商业趋势、管理决策、行业动态\n'
                    '• 宝爸宝妈 — 亲子教育、家庭时光\n'
                    '• 退休人群 — 养生健康、兴趣爱好、慢节奏生活\n'
                    '• 儿童 — 启蒙故事、趣味科普',
          ),
          const SizedBox(height: 20),

          // 4 个 scene
          _buildSection(
            icon: Icons.theater_comedy_outlined,
            title: isEn ? '4 scenes, any moment' : '4 个场景，应对任意时刻',
            content: isEn
                ? '• Learn — knowledge and insights\n'
                    '• Listen — news and audio-style content\n'
                    '• Relax — mindfulness and breathing\n'
                    '• Workout — micro-exercises you can do anywhere'
                : '• 学 — 知识与见解\n'
                    '• 听 — 新闻与音频风格内容\n'
                    '• 放松 — 正念与呼吸\n'
                    '• 运动 — 任何地方都能做的小动作',
          ),
          const SizedBox(height: 20),

          // AI 来源
          _buildSection(
            icon: Icons.memory,
            title: isEn ? 'How content is generated' : '内容怎么来',
            content: isEn
                ? 'By default, content is generated by a local Ollama LLM (qwen2.5:7b) running on your device. '
                    'Nothing leaves your network. You can also switch to a remote LLM (MiniMax, OpenAI, etc.) '
                    'by providing an API key at build time.'
                : '默认由本地 Ollama（qwen2.5:7b）实时生成内容，'
                    '数据不出你的网络。也可以在 build 时通过 API key 切换到远端 LLM（MiniMax、OpenAI 等）。',
          ),
          const SizedBox(height: 20),

          // 隐私
          _buildSection(
            icon: Icons.shield_outlined,
            title: isEn ? 'Privacy' : '隐私',
            content: isEn
                ? 'No accounts. No tracking. No telemetry. Your selections stay on your device. '
                    'Generated text is ephemeral unless you save it.'
                : '无账号、无追踪、无埋点。你的选择仅存在本地设备上。'
                    '生成的内容不存储，除非你主动保存。',
          ),
          const SizedBox(height: 20),

          // 技术栈
          _buildSection(
            icon: Icons.code,
            title: isEn ? 'Tech stack' : '技术栈',
            content: isEn
                ? 'Flutter 3.5.4 (Dart) + Material 3 + local Ollama LLM. '
                    'Open source, self-hosted. Runs in your browser or as a native app.'
                : 'Flutter 3.5.4（Dart）+ Material 3 + 本地 Ollama LLM。'
                    '开源、自部署。可在浏览器或原生应用运行。',
          ),
          const SizedBox(height: 20),

          // 路线图
          _buildSection(
            icon: Icons.rocket_launch_outlined,
            title: isEn ? 'Roadmap' : '路线图',
            content: isEn
                ? '✓ 6 identities, 4 scenes, AI streaming\n'
                    '✓ Bilingual (zh/en) + region (domestic/international)\n'
                    '✓ Elderly mode (large text)\n'
                    '✓ Persisted user type (SharedPreferences)\n'
                    '→ Subscriptions (12 categories)\n'
                    '→ TTS audio (just_audio)\n'
                    '→ Daily streak tracking'
                : '✓ 6 个身份、4 个场景、AI 流式生成\n'
                    '✓ 中英双语 + 国内/国际版\n'
                    '✓ 老年模式（放大字体）\n'
                    '→ 订阅（12 个内容类目）\n'
                    '→ 偏好持久化（SharedPreferences）\n'
                    '→ TTS 音频（just_audio）\n'
                    '→ 每日连击',
          ),
          const SizedBox(height: 20),

          // 反馈
          _buildSection(
            icon: Icons.mail_outline,
            title: isEn ? 'Feedback' : '反馈',
            content: isEn
                ? 'This is an early version. Bugs and ideas welcome — talk to your local AI assistant (章鱼 🐙).'
                : '这是早期版本。Bug 和想法欢迎反馈——跟你的本地 AI 助手（章鱼 🐙）说就行。',
          ),
          const SizedBox(height: 12),
          // 6/14 v5: 反馈入口 — 对章鱼说话 / 看宪法
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context: context,
                  icon: Icons.chat_bubble_outline,
                  label: isEn ? 'Talk to 章鱼' : '对章鱼说话',
                  onTap: () => showFeedbackDialog(context, languageCode),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  context: context,
                  icon: Icons.menu_book_outlined,
                  label: isEn ? 'Constitution' : '项目宪法',
                  onTap: () => _showConstitutionDialog(context, isEn),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          Center(
            child: Text(
              isEn ? 'Made with care, late at night' : '深夜慢做',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight, fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 6/14 v5: 反馈入口按钮 (玻璃胶囊)
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
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

  // 7/1: 抓 Flutter web 截图 (canvaskit 不暴露 DOM canvas, 用 RenderRepaintBoundary + toImage)
  // 思路: 找 MaterialApp 的 root RenderRepaintBoundary → toImage → ByteData PNG → base64
  static Future<String?> _captureScreenshot() async {
    try {
      // 拿当前页面 RenderRepaintBoundary: dialog/popup 可能有自己 boundary
      // 简化: 用 WidgetsBinding.instance.rootElement + 层层找
      final RenderObject? root = WidgetsBinding.instance.rootElement?.renderObject;
      if (root == null) return null;
      // 递归找一个 RenderRepaintBoundary
      RenderRepaintBoundary? boundary;
      void visit(RenderObject node) {
        if (boundary != null) return;
        if (node is RenderRepaintBoundary) {
          boundary = node;
          return;
        }
        node.visitChildren(visit);
      }
      visit(root);
      if (boundary == null) return null;
      final ui.Image image = await boundary!.toImage(pixelRatio: 1.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return base64Encode(byteData.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  // 7/1: 提交反馈 (写 prefs + POST 到 NAS)
  static Future<bool> _submitFeedback(String msg, String? screenshotB64, String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    final entry = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'msg': msg,
      'hasScreenshot': screenshotB64 != null,
      'synced': false,
    };
    // 写本地 (FIFO 50)
    final raw = prefs.getString('feedback_log') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.add(entry);
    if (list.length > 50) list.removeRange(0, list.length - 50);
    await prefs.setString('feedback_log', jsonEncode(list));

    // POST 到 NAS
    try {
      final payload = <String, dynamic>{
        'ts': entry['ts'],
        'msg': msg,
        'appVersion': '0.7.0',
        'platform': 'web',
        'language': languageCode,
      };
      if (screenshotB64 != null) {
        payload['screenshot'] = screenshotB64;
      }
      final resp = await http.post(
        Uri.parse('${Uri.base.origin}/api/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        entry['synced'] = true;
        // 更新 prefs synced 标志
        list[list.length - 1]['synced'] = true;
        await prefs.setString('feedback_log', jsonEncode(list));
        return true;
      }
    } catch (_) {
      // 网络失败, prefs 已保留 synced: false
    }
    return false;
  }

  // 6/14 v5: 项目宪法 dialog (写死关键条文, 不读文件避免 web asset path 问题)
  Future<void> _showConstitutionDialog(BuildContext context, bool isEn) async {
    final lines = isEn
        ? const [
            '1. COPYRIGHT IS LIFEBLOOD',
            '   No scraping. No plagiarism. "去原站" always navigates to source.',
            '2. POSITIONING: dual-version × dual-language × elderly mode',
            '   24 buckets (6 user types × 4 scenes). 双版本 国内/国际. 双语 中/英. 老年模式 全屏放大.',
            '3. FAKE DATA IS OK, REAL DATA NEEDS CARE',
            '   Pre-cached content can ship. Real LLM data must pass safety (child HARD RULE).',
            '4. CHILD SAFETY: HARD RULE',
            '   AI prompt + UI green shield for child content.',
            '5. ENGINEERING DISCIPLINE',
            '   Material Icons only. Interface alignment = grep. Release = build_and_serve.sh.',
            '6. COLLAB DISCIPLINE',
            '   Diagnose first. Don\'t grab attention. Leave a trail (memory/YYYY-MM-DD.md).',
          ]
        : const [
            '1. 版权是命根子',
            '   不抓取、不抄袭。"去原站"永远跳到原平台。',
            '2. 定位：双版本 × 双语 × 老年模式',
            '   24 桶（6 角色 × 4 场景）。双版本 国内/国际。双语 中/英。老年模式 全屏放大。',
            '3. 假数据可上线，真数据要谨慎',
            '   预准备内容可直接发。LLM 真实内容必须过安全（儿童 HARD RULE）。',
            '4. 儿童安全：硬规则',
            '   AI prompt + UI 绿色盾牌双层防护。',
            '5. 工程纪律',
            '   全用 Material Icons。接口对齐要 grep。发布走 build_and_serve.sh。',
            '6. 协作纪律',
            '   诊断优先。不抢用户注意力。留痕（memory/YYYY-MM-DD.md）。',
          ];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Constitution (项目宪法)' : '项目宪法'),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: lines.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(l, style: const TextStyle(fontSize: 12, height: 1.5)),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isEn ? 'Close' : '关闭')),
        ],
      ),
    );
  }

  Widget _buildSection({required IconData icon, required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Text(content, style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87)),
      ],
    );
  }
}


// 6/30 11:52 SOUL #32: 浮起 SnackBar, 不挡底部 nav
void _showFloatingSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      duration: const Duration(seconds: 3),
    ),
  );
}
