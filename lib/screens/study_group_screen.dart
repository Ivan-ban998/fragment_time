// 6/9 Sofa 启发：学习小组 screen
import 'package:flutter/material.dart';
import '../theme/glass_decoration.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../models/study_group.dart';
import '../services/study_group_service.dart';
import '../services/handle_service.dart';
import '../theme/app_theme.dart';
import '../widgets/skeleton.dart';
import 'content_reader_screen.dart';

class StudyGroupScreen extends StatefulWidget {
  final UserType userType;
  final bool isEn;
  const StudyGroupScreen({super.key, required this.userType, required this.isEn});

  @override
  State<StudyGroupScreen> createState() => _StudyGroupScreenState();
}

class _StudyGroupScreenState extends State<StudyGroupScreen> {
  late Future<List<StudyGroup>> _future;
  String _myHandle = HandleService.defaultHandle; // 6/10 加: 从 handle service 取

  @override
  void initState() {
    super.initState();
    _future = StudyGroupService.instance.getForRole(widget.userType);
    _loadHandle();
  }

  Future<void> _loadHandle() async {
    final h = await HandleService().get();
    if (mounted) setState(() => _myHandle = h);
  }

  // 6/10 加: 创建小组的对话框
  Future<void> _showCreateDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final topicCtrl = TextEditingController();
    final handleCtrl = TextEditingController(text: _myHandle); // 6/10: 从 service 取
    final isEn = widget.isEn;
    Set<UserType> selectedRoles = {widget.userType}; // 默认含当前 role

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(isEn ? 'New Study Group' : '创建学习小组'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: isEn ? 'Name' : '小组名',
                      hintText: isEn ? 'e.g. OKR Weekly' : '如：OKR 周复盘',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: topicCtrl,
                    decoration: InputDecoration(
                      labelText: isEn ? 'Topic' : '主题',
                      hintText: isEn ? 'what you read together' : '一起读什么',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: handleCtrl,
                    decoration: InputDecoration(
                      labelText: isEn ? 'Your handle' : '你的 handle',
                      // 6/26 Brien 反馈: @ 符号让人误以为要保留, 删了
                      hintText: isEn ? 'Your name' : '你的昵称',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(isEn ? 'Allowed roles' : '允许的角色', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: UserType.values.map((r) {
                      final selected = selectedRoles.contains(r);
                      return FilterChip(
                        label: Text(r.name, style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        onSelected: (v) => setLocal(() {
                          if (v) {
                            selectedRoles.add(r);
                          } else {
                            selectedRoles.remove(r);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(isEn ? 'Cancel' : '取消')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty || topicCtrl.text.trim().isEmpty || handleCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(isEn ? 'fill all fields' : '填全部字段')));
                    return;
                  }
                  await StudyGroupService.instance.create(
                    name: nameCtrl.text.trim(),
                    topic: topicCtrl.text.trim(),
                    allowedRoles: selectedRoles,
                    myHandle: handleCtrl.text.trim(),
                  );
                  // 6/10 加: 同步 handle 到 service
                  await HandleService().set(handleCtrl.text.trim());
                  if (mounted) Navigator.pop(ctx, true);
                },
                child: Text(isEn ? 'Create' : '创建'),
              ),
            ],
          ),
        );
      },
    );

    if (result == true && mounted) {
      setState(() {
        _future = StudyGroupService.instance.getForRole(widget.userType);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(widget.isEn ? 'Study Groups' : '学习小组'),
      ),
      // 6/10 加: 创建小组按钮
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: Text(widget.isEn ? 'New Group' : '创建小组'),
      ),
      body: FutureBuilder<List<StudyGroup>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const CardSkeleton();
          }
          final groups = snap.data!;
          if (groups.isEmpty) {
            return Center(
              child: Text(widget.isEn
                  ? 'No study group for this role yet'
                  : '该角色还没小组'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (_, i) => _GroupCard(
              group: groups[i],
              isEn: widget.isEn,
              myHandle: _myHandle, // 6/10: 从 state 取
              onJoin: () async {
                await StudyGroupService.instance.join(groups[i].id, _myHandle);
                if (mounted) {
                  setState(() {
                    _future = StudyGroupService.instance.getForRole(widget.userType);
                  });
                }
              },
              onLeave: () async {
                await StudyGroupService.instance.leave(groups[i].id, _myHandle);
                if (mounted) {
                  setState(() {
                    _future = StudyGroupService.instance.getForRole(widget.userType);
                  });
                }
              },
              onAdvance: () async {
                await StudyGroupService.instance.advance(groups[i]);
                if (mounted) {
                  setState(() {
                    _future = StudyGroupService.instance.getForRole(widget.userType);
                  });
                }
              },
              onTap: () {
                // 跳到 group 当前的 content
                final queue = groups[i].contentQueue;
                if (queue.isEmpty) return;
                final id = queue[groups[i].currentContentIndex];
                // 简化为 fake 跳 content_screen 的别名
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContentReaderScreen(
                      item: ContentItem(
                        id: id,
                        title: '${groups[i].name} · 第${groups[i].currentContentIndex + 1}篇',
                        description: '组内正在读 — ${groups[i].topic}',
                        duration: '5min',
                        source: 'Study Group',
                        sourceType: ContentSource.news36kr,
                        contentType: ContentType.article,
                        externalUrl: 'https://search.bilibili.com/all?keyword=${Uri.encodeComponent(groups[i].topic)}',
                      ),
                    ),
                  ),
                );
              },
              onShare: () {
                // 6/9 share-link：复制 URL 到剪贴板
                final url = 'http://100.89.204.123:9090/#/study/${groups[i].id}';
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.isEn ? 'Link copied: $url' : '链接已复制：$url')),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final StudyGroup group;
  final bool isEn;
  final String myHandle;
  final VoidCallback onTap;
  final VoidCallback onAdvance;
  final VoidCallback onShare;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  const _GroupCard({
    required this.group,
    required this.isEn,
    required this.myHandle,
    required this.onTap,
    required this.onAdvance,
    required this.onShare,
    required this.onJoin,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final progress = group.contentQueue.isEmpty
        ? 0.0
        : (group.currentContentIndex + 1) / group.contentQueue.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${group.memberIds.length} ${isEn ? 'members' : '人'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              IconButton(
                icon: const Icon(Icons.share, size: 16),
                onPressed: onShare,
                tooltip: isEn ? 'Copy invite link' : '复制邀请链接',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(group.topic, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),
          // 组进度条
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isEn
                ? 'Day ${group.currentContentIndex + 1} of ${group.contentQueue.length}'
                : '第 ${group.currentContentIndex + 1} / ${group.contentQueue.length} 篇',
            style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.menu_book, size: 14),
                  label: Text(isEn ? 'Read together' : '一起读'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onAdvance,
                  icon: const Icon(Icons.skip_next, size: 14),
                  label: Text(isEn ? 'Move on' : '下一篇'),
                ),
              ),
            ],
          ),
          // 6/10 加: 加入 / 退出 按钮
          const SizedBox(height: 8),
          if (group.memberIds.contains(myHandle))
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLeave,
                icon: Icon(Icons.exit_to_app, size: 14, color: Colors.red[400]),
                label: Text(
                  isEn ? 'Leave group' : '退出小组',
                  style: TextStyle(color: Colors.red[400]),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onJoin,
                icon: const Icon(Icons.person_add, size: 14),
                label: Text(isEn ? 'Join group' : '加入小组'),
              ),
            ),
          // 成员头像
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: group.memberIds
                .map((m) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(m, style: TextStyle(fontSize: 10, color: AppTheme.primary)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
