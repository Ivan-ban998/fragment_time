import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:ui';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/motivation_service.dart';
import '../services/handle_service.dart';
import '../services/theme_preference_service.dart';
import '../services/weekly_recap_service.dart';
import '../services/pack_io_helpers.dart';
import 'history_screen.dart';
import 'analytics_dashboard_screen.dart';
import 'study_group_screen.dart';
import 'scene_pack_screen.dart';
import 'about_screen.dart';

class SettingsTab extends StatelessWidget {
  // 6/10 加: build 版本号常量（dart-define 注入）
  static const String _kBuildVersion = String.fromEnvironment('BUILD_VERSION', defaultValue: 'dev');

  final AppConfig config;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final Future<void> Function() onToggleInternational;
  final Future<void> Function() onToggleLanguage;
  final Future<void> Function() onToggleElderlyMode;
  final Future<void> Function() onToggleTheme;
  final Future<void> Function() onToggleEyeProtection;
  // 6/24 v12: 切换角色 — main.dart 提供
  final UserType? selectedUserType;
  final Future<void> Function() onChangeUserType;

  const SettingsTab({
    super.key,
    required this.config,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
    required this.onToggleInternational,
    required this.onToggleLanguage,
    required this.onToggleElderlyMode,
    required this.onToggleTheme,
    required this.onToggleEyeProtection,
    this.selectedUserType,
    required this.onChangeUserType,
  });

  // 6/10 加: 编辑 handle dialog
  Future<void> _showHandleDialog(BuildContext context, String current, bool isEn) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'My Handle' : '我的昵称'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: isEn ? 'handle' : 'handle',
            hintText: '@你的名字',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isEn ? 'Cancel' : '取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(isEn ? 'Save' : '保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      await HandleService().set(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEn ? 'Handle saved' : 'handle 已保存')),
        );
      }
    }
  }

  // 6/12 加: 隐私政策弹窗
  Future<void> _showPrivacyPolicy(BuildContext context, bool isEn) async {
    final scale = isElderlyMode ? 1.3 : 1.0;
    final lines = isEn
        ? const [
            '1. fragment_time does NOT collect any personal data.',
            '2. Reading history, saved items, and weekly recap are stored locally on your device only.',
            '3. LLM summaries are sent to your local Ollama or cloud LLM — only the content text, not your identity.',
            '4. We do not use analytics, trackers, or third-party SDKs.',
            '5. Uninstalling the app removes all your local data.',
          ]
        : const [
            '1. fragment_time 不收集任何个人数据。',
            '2. 阅读历史、收藏、周回顾全部仅存于你设备本地。',
            '3. AI 总结会发送到你本地的 Ollama 或云 LLM——只发内容文本，不发你的身份。',
            '4. 我们不使用埋点、追踪器或第三方 SDK。',
            '5. 卸载 app = 你的所有本地数据被删。',
          ];
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Privacy Policy' : '隐私政策'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: lines
                .map((l) => Padding(
                      padding: EdgeInsets.only(bottom: 10 * scale),
                      child: Text(l, style: TextStyle(fontSize: 14 * scale, height: 1.5)),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'Got it' : '知道了'),
          ),
        ],
      ),
    );
  }

  // 6/12 加: 周回顾弹窗
  Future<void> _showWeeklyRecap(BuildContext context, bool isEn) async {
    final scale = isElderlyMode ? 1.3 : 1.0;
    // 6/12 动器: 先弹 loading 再装
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    WeeklyRecap recap;
    try {
      recap = await WeeklyRecapService.instance.generate();
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // 关 loading
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEn ? 'Recap failed: $e' : '回顾失败: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.pop(context); // 关 loading

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.purple),
            const SizedBox(width: 8),
            Text(isEn ? 'Weekly Recap' : '本周回顾'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 数字块
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _recapStat('📚', '${recap.total}', isEn ? 'items' : '条', scale),
                  _recapStat('📅', '${recap.daysActive}', '/7 ${isEn ? "days" : "天"}', scale),
                  _recapStat('🎯', recap.perSource.isEmpty ? '-' : recap.perSource.entries.reduce((a, b) => a.value > b.value ? a : b).key, isEn ? 'top source' : '主要来源', scale),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              // AI 总结
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.withOpacity(0.2)),
                ),
                child: Text(
                  recap.summary,
                  style: TextStyle(fontSize: 14 * scale, height: 1.5),
                ),
              ),
              if (recap.llmUsed) ...[
                const SizedBox(height: 6),
                Text(
                  isEn ? '— by AI coach' : '— AI 总结生成',
                  style: TextStyle(fontSize: 10 * scale, color: AppTheme.textLight),
                ),
              ],
              if (recap.topTitles.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  isEn ? 'Recent reads' : '最近 5 篇',
                  style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                ...recap.topTitles.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $t', style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight), maxLines: 2, overflow: TextOverflow.ellipsis),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'Close' : '关闭'),
          ),
        ],
      ),
    );
  }

  Widget _recapStat(String emoji, String num, String label, double scale) {
    return Column(
      children: [
        Text(emoji, style: TextStyle(fontSize: 24 * scale)),
        const SizedBox(height: 4),
        Text(num, style: TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = languageCode == 'en';
    final scale = isElderlyMode ? 1.3 : 1.0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEn ? 'Settings' : '设置', style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.bold)),
            SizedBox(height: 24 * scale),
            Card(
              child: Column(children: [
                // 6/24 v12: 切换角色 — 弹出 6 角色选择对话框
                ListTile(
                  leading: Icon(Icons.people_outline, size: 24 * scale),
                  title: Text(isEn ? 'My Identity' : '我的身份', style: TextStyle(fontSize: 16 * scale)),
                  subtitle: Text(
                    selectedUserType != null
                        ? (isEn ? _userTypeNameEn(selectedUserType!) : _userTypeNameZh(selectedUserType!))
                        : (isEn ? 'Tap to choose' : '点选'),
                    style: TextStyle(fontSize: 13 * scale),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onChangeUserType, // 6/24 v12: main.dart 提供
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.language, size: 24 * scale),
                  title: Text(isEn ? 'Region' : '地区模式', style: TextStyle(fontSize: 16 * scale)),
                  subtitle: Text(isEn ? 'International / Domestic' : '国内/国际', style: TextStyle(fontSize: 13 * scale)),
                  trailing: Switch(value: isInternational, onChanged: (_) => onToggleInternational()),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.translate, size: 24 * scale),
                  title: Text(isEn ? 'Language' : '语言', style: TextStyle(fontSize: 16 * scale)),
                  subtitle: Text(isEn ? '中文 / English' : '中文 / English', style: TextStyle(fontSize: 13 * scale)),
                  trailing: Switch(value: languageCode == 'en', onChanged: (_) => onToggleLanguage()),
                ),
                Divider(height: 1),
                // 6/13 主题模式：跟随系统 / 白天 / 夜晚 循环切换
                // label 从 ThemeData.brightness 推（只能知道当前是深还是浅，跟踪系统看不到）
                Builder(builder: (innerContext) {
                  final isDark = Theme.of(innerContext).brightness == Brightness.dark;
                  return ListTile(
                    leading: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      size: 24 * scale,
                    ),
                    title: Text(isEn ? 'Theme' : '主题', style: TextStyle(fontSize: 16 * scale)),
                    subtitle: Text(
                      isEn ? 'Tap to toggle (system / light / dark)' : '点击循环（系统 / 白天 / 夜晚）',
                      style: TextStyle(fontSize: 13 * scale),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onToggleTheme,
                  );
                }),
                Divider(height: 1),
                // 6/13 护眼模式：auto / on / off 三态
                FutureBuilder<String>(
                  future: ThemePreferenceService.instance.getEyeProtectionMode(),
                  builder: (ctx, snap) {
                    final mode = snap.data ?? 'auto';
                    return ListTile(
                      leading: const Icon(Icons.bedtime, size: 24),
                      title: Text(isEn ? 'Eye protection' : '护眼模式', style: TextStyle(fontSize: 16 * scale)),
                      subtitle: Text(
                        ThemePreferenceService.instance.eyeProtectionLabel(mode, isEn: isEn),
                        style: TextStyle(fontSize: 13 * scale),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: onToggleEyeProtection,
                    );
                  },
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.elderly, size: 24 * scale),
                  title: Text(isEn ? 'Elderly Mode' : '老人模式', style: TextStyle(fontSize: 16 * scale)),
                  subtitle: Text(isEn ? 'Large text & buttons' : '字体放大，按键加大', style: TextStyle(fontSize: 13 * scale)),
                  trailing: Switch(value: isElderlyMode, onChanged: (_) => onToggleElderlyMode()),
                ),
                // 6/10 加: 我的 handle（学习小组 / 加入退出用）
                Divider(height: 1),
                // 6/25 修 bug: 用 ValueListenableBuilder 替代 FutureBuilder
                // (之前 set 后 UI 不会 rebuild, 昵称看起来 '没保存')
                ValueListenableBuilder<String>(
                  valueListenable: HandleService.notifier,
                  builder: (ctx, h, _) {
                    return ListTile(
                      leading: Icon(Icons.alternate_email, size: 24 * scale),
                      title: Text(isEn ? 'My Handle' : '我的昵称', style: TextStyle(fontSize: 16 * scale)),
                      subtitle: Text(h, style: TextStyle(fontSize: 13 * scale, color: AppTheme.primary)),
                      trailing: Icon(Icons.edit, size: 18 * scale),
                      onTap: () => _showHandleDialog(context, h, isEn),
                    );
                  },
                ),
              ]),
            ),
            SizedBox(height: 16 * scale),
            // 6/12 改: “关注管理”入口从设置 Tab 删了
            // 理由: 收藏 Tab ⋮ 菜单和空状态都有，3 个入口是重复
            // 设置 Tab 只保留个人设置/工具/关于
            Card(
              child: ListTile(
                leading: Icon(Icons.history, size: 24 * scale, color: AppTheme.primary),
                title: Text(isEn ? 'Reading History' : '阅读历史', style: TextStyle(fontSize: 16 * scale)),
                subtitle: Text(
                  isEn ? 'Articles and videos you opened' : '你读过的内容和看过的视频',
                  style: TextStyle(fontSize: 13 * scale),
                ),
                trailing: Icon(Icons.chevron_right, size: 24 * scale, color: AppTheme.textLight),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
              ),
            ),
            SizedBox(height: 16 * scale),
            // 6/12 改: 工具 / 关于折叠
            Card(
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Icon(Icons.build, size: 24 * scale, color: AppTheme.primary),
                  title: Text(isEn ? 'Tools' : '工具', style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w600)),
                  subtitle: Text(isEn ? 'Dashboard, export, scene pack, groups' : '数据看板/导出/场景包/小组', style: TextStyle(fontSize: 12 * scale)),
                  initiallyExpanded: false,
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    // 6/8 加：自用数据看板入口
                    ListTile(
                      leading: Icon(Icons.analytics, size: 22 * scale),
                      title: Text(isEn ? 'Analytics (self-use)' : '数据看板（自用）', style: TextStyle(fontSize: 15 * scale)),
                      subtitle: Text(isEn ? 'Local usage stats' : '本地使用统计', style: TextStyle(fontSize: 12 * scale)),
                      trailing: Icon(Icons.chevron_right, size: 20 * scale),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AnalyticsDashboardScreen()),
                        );
                      },
                    ),
                    Divider(height: 1, indent: 56),
                    // 6/9 4：离线收藏包 — 导出 / 导入
                    ListTile(
                      leading: Icon(Icons.download, size: 22 * scale),
                      title: Text(isEn ? 'Export saved pack' : '导出我的收藏', style: TextStyle(fontSize: 15 * scale)),
                      subtitle: Text(isEn ? 'Copy JSON to another device' : '复制到另一个设备', style: TextStyle(fontSize: 12 * scale)),
                      onTap: () => PackIO.showExportDialog(context, isEn: isEn),
                    ),
                    ListTile(
                      leading: Icon(Icons.upload, size: 22 * scale),
                      title: Text(isEn ? 'Import pack from JSON' : '导入收藏包', style: TextStyle(fontSize: 15 * scale)),
                      subtitle: Text(isEn ? 'Paste exported JSON' : '粘贴之前导出的 JSON', style: TextStyle(fontSize: 12 * scale)),
                      onTap: () => PackIO.showImportDialog(context, isEn: isEn),
                    ),
                    Divider(height: 1, indent: 56),
                    // 6/9 场景包入口
                    ListTile(
                      leading: Icon(Icons.backpack, size: 22 * scale),
                      title: Text(isEn ? 'Build a Scene Pack' : '建场景包', style: TextStyle(fontSize: 15 * scale)),
                      subtitle: Text(isEn ? 'Pick 5 items, name it, ready in 1 tap' : '选 5 条起名，一键调出', style: TextStyle(fontSize: 12 * scale)),
                      trailing: Icon(Icons.chevron_right, size: 20 * scale),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ScenePackScreen(
                              userType: UserType.student,
                              scene: Scene.learn,
                              isEn: isEn,
                            ),
                          ),
                        );
                      },
                    ),
                    // 6/9 Sofa 启发：学习小组入口
                    ListTile(
                      leading: Icon(Icons.groups, size: 22 * scale),
                      title: Text(isEn ? 'Study Groups' : '学习小组', style: TextStyle(fontSize: 15 * scale)),
                      subtitle: Text(isEn ? 'Read together (student/entrepreneur)' : '创业者 / 学生可加入', style: TextStyle(fontSize: 12 * scale)),
                      trailing: Icon(Icons.chevron_right, size: 20 * scale),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudyGroupScreen(
                              userType: UserType.student, // default 入口；后续让用户选
                              isEn: isEn,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16 * scale),
            // 6/12 改: 本周回顾常驻卡，点开看 AI 总结
            InkWell(
              borderRadius: BorderRadius.circular(16 * scale),
              onTap: () => _showWeeklyRecap(context, isEn),
              child: _WeeklyRecapCard(isEn: isEn, scale: scale),
            ),
            SizedBox(height: 16 * scale),
            // 6/12 改: 关于 折叠
            Card(
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Icon(Icons.info_outline, size: 24 * scale, color: AppTheme.textLight),
                  title: Text(isEn ? 'About' : '关于', style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${config.appName} · ${SettingsTab._kBuildVersion}',
                    style: TextStyle(fontSize: 12 * scale),
                  ),
                  initiallyExpanded: false,
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    ListTile(
                      leading: Icon(Icons.security, size: 22 * scale),
                      title: Text(isEn ? 'Privacy Policy' : '隐私政策', style: TextStyle(fontSize: 15 * scale)),
                      subtitle: Text(isEn ? 'No data collected' : '不收集任何数据', style: TextStyle(fontSize: 12 * scale)),
                      trailing: Icon(Icons.chevron_right, size: 20 * scale),
                      onTap: () => _showPrivacyPolicy(context, isEn),
                    ),
                    Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(Icons.copyright, size: 22 * scale),
                      title: Text(isEn ? 'Copyright' : '版权声明', style: TextStyle(fontSize: 15 * scale)),
                      subtitle: Text(config.copyrightFooter, style: TextStyle(fontSize: 11 * scale)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 6/14 v5: 章鱼入口按钮组 (跟章鱼说话 + 关于页)
class _OctopusActionRow extends StatelessWidget {
  final double scale;
  final bool isEn;
  final VoidCallback onTalkToOctopus;
  final VoidCallback onAbout;
  const _OctopusActionRow({
    required this.scale,
    required this.isEn,
    required this.onTalkToOctopus,
    required this.onAbout,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildButton(
            context: context,
            icon: '🐙',
            label: isEn ? 'Talk to 章鱼' : '跟章鱼说话',
            onTap: onTalkToOctopus,
            primary: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildButton(
            context: context,
            icon: Icons.info_outline,
            label: isEn ? 'About' : '关于',
            onTap: onAbout,
            primary: false,
          ),
        ),
      ],
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required dynamic icon,  // String emoji OR IconData
    required String label,
    required VoidCallback onTap,
    required bool primary,
  }) {
    final accent = AppTheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 14 * scale, horizontal: 12 * scale),
              decoration: BoxDecoration(
                color: primary
                    ? accent.withOpacity(0.85)
                    : Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primary
                      ? Colors.white.withOpacity(0.4)
                      : Colors.white.withOpacity(0.5),
                  width: 1.2,
                ),
                boxShadow: [
                  if (primary)
                    BoxShadow(
                      color: accent.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon is String)
                    Text(icon, style: const TextStyle(fontSize: 18))
                  else
                    Icon(icon, size: 18, color: primary ? Colors.white : accent),
                  SizedBox(width: 8 * scale),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.w700,
                        color: primary ? Colors.white : AppTheme.textDark,
                      ),
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
}

// 6/14 v5: 章鱼反馈历史 (本地 prefs 读)
class _OctopusFeedbackList extends StatefulWidget {
  final double scale;
  final bool isEn;
  const _OctopusFeedbackList({required this.scale, required this.isEn});

  @override
  State<_OctopusFeedbackList> createState() => _OctopusFeedbackListState();
}

class _OctopusFeedbackListState extends State<_OctopusFeedbackList> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('feedback_log') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    // 倒序 (最新在前)
    list.sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
    if (mounted) setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(12 * widget.scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🐙', style: TextStyle(fontSize: 14)),
              SizedBox(width: 6 * widget.scale),
              Text(
                widget.isEn ? 'Recent feedback to 章鱼' : '最近跟章鱼说的话',
                style: TextStyle(
                  fontSize: 12 * widget.scale,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              if (_items.any((i) => i['synced'] != true))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.isEn ? 'unsynced' : '未同步',
                    style: TextStyle(fontSize: 9 * widget.scale, color: Colors.orange.shade800),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8 * widget.scale),
          ...(_items.take(3).map((it) => _buildItem(it))),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> it) {
    final ts = DateTime.fromMillisecondsSinceEpoch(it['ts'] as int);
    final msg = (it['msg'] as String).substring(0, (it['msg'] as String).length.clamp(0, 60));
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3 * widget.scale),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: it['synced'] == true ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8 * widget.scale),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(fontSize: 11 * widget.scale, color: AppTheme.textDark.withOpacity(0.75)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 9 * widget.scale, color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }
}

class _DialogOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _DialogOption({required this.icon, required this.title, required this.desc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.textLight, height: 1.4)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppTheme.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyRecapCard extends StatelessWidget {
  final bool isEn;
  final double scale;
  const _WeeklyRecapCard({required this.isEn, required this.scale});

  @override
  Widget build(BuildContext context) {
    final svc = StreakService();
    return FutureBuilder(
      future: svc.getWeeklyRecap(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final r = snap.data!;
        return Container(
          padding: EdgeInsets.all(16 * scale),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.withOpacity(0.08), Colors.transparent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16 * scale, color: AppTheme.primary),
                  SizedBox(width: 6 * scale),
                  Text(isEn ? 'This week' : '本周回顾',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 14 * scale,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
              SizedBox(height: 12 * scale),
              Row(
                children: [
                  _statItem('📖', '${r.watchedArticles}', isEn ? 'articles' : '篇文章', scale),
                  _statItem('🎧', '${r.listenedAudio}', isEn ? 'listened' : '次听', scale),
                  _statItem('🔖', '${r.savedCount}', isEn ? 'saved' : '个收藏', scale),
                  _statItem('⏱', '${r.minutesActive}', isEn ? 'min' : '分钟', scale),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String emoji, String num, String label, double scale) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: TextStyle(fontSize: 22)),
          SizedBox(height: 4 * scale),
          Text(num,
              style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w700, color: AppTheme.primary)),
          Text(label, style: TextStyle(fontSize: 11 * scale, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// 6/24 v12: 角色名 helper
String _userTypeNameZh(UserType t) {
  switch (t) {
    case UserType.student: return '学生';
    case UserType.officeWorker: return '上班族';
    case UserType.entrepreneur: return '创业者';
    case UserType.parent: return '宝爸宝妈';
    case UserType.senior: return '退休人群';
    case UserType.child: return '儿童';
  }
}

String _userTypeNameEn(UserType t) {
  switch (t) {
    case UserType.student: return 'Student';
    case UserType.officeWorker: return 'Office Worker';
    case UserType.entrepreneur: return 'Entrepreneur';
    case UserType.parent: return 'Parent';
    case UserType.senior: return 'Senior';
    case UserType.child: return 'Child';
  }
}


