import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/history_service.dart';
import 'content_reader_screen.dart';

/// 6/7 步骤 2：阅读历史
/// 宪法 §1.1 兼容：只存设备本地，SharedPreferences
class HistoryScreen extends StatefulWidget {
  final bool isElderlyMode;
  final bool isEn;
  const HistoryScreen({super.key, this.isElderlyMode = false, this.isEn = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await HistoryService.instance.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await HistoryService.instance.clear();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isEn ? 'History cleared' : '历史已清空')),
      );
    }
  }

  /// 6/8 修复：单条删除（长按弹确认框）
  /// 不点「取消」＝不删；点「删除」＝刷 SharedPreferences
  Future<void> _deleteOne(String id) async {
    final isEn = widget.isEn;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Delete this entry?' : '删除这条记录？'),
        content: Text(isEn
            ? 'This reading record will be removed from this device only.'
            : '该条阅读记录会从本机删除，不会影响其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isEn ? 'Cancel' : '取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEn ? 'Delete' : '删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryService.instance.removeById(id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEn ? 'Entry deleted' : '已删除')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
    final isEn = widget.isEn;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Reading History' : '阅读历史', style: TextStyle(fontSize: 18 * scale)),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: isEn ? 'Clear all' : '清空',
              onPressed: _clear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24 * scale),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64 * scale, color: AppTheme.textLight.withOpacity(0.4)),
                        SizedBox(height: 16 * scale),
                        Text(
                          isEn ? 'No history yet' : '还没有阅读记录',
                          style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w600, color: AppTheme.textLight),
                        ),
                        SizedBox(height: 8 * scale),
                        Text(
                          isEn
                              ? 'Articles and videos you open will show up here.'
                              : '打开过的内容和视频会出现在这里',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.all(16 * scale),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12 * scale),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _HistoryCard(
                      item: item,
                      scale: scale,
                      isEn: isEn,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContentReaderScreen(
                              item: item.toContentItem(),
                              isElderlyMode: widget.isElderlyMode,
                              isEn: isEn,
                            ),
                          ),
                        ).then((_) => _load());
                      },
                      onLongPress: () => _deleteOne(item.id),
                    );
                  },
                ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryItem item;
  final double scale;
  final bool isEn;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _HistoryCard({
    required this.item,
    required this.scale,
    required this.isEn,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.readAt);
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.all(14 * scale),
          child: Row(
            children: [
              Icon(
                _iconForContentType(item.contentTypeName),
                size: 20 * scale,
                color: AppTheme.primary,
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4 * scale),
                    Row(
                      children: [
                        Text(
                          item.source,
                          style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                        ),
                        SizedBox(width: 8 * scale),
                        Icon(Icons.access_time, size: 10 * scale, color: AppTheme.textLight),
                        SizedBox(width: 2 * scale),
                        Text(
                          dateStr,
                          style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForContentType(String name) {
    switch (name) {
      case 'video':
        return Icons.play_circle_outline;
      case 'audio':
        return Icons.headphones;
      case 'short':
        return Icons.flash_on;
      case 'card':
        return Icons.style;
      case 'quiz':
        return Icons.quiz;
      default:
        return Icons.article_outlined;
    }
  }
}
