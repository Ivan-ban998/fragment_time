import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/content_aggregator.dart';
import 'content_reader_screen.dart';
import 'in_app_webview_screen.dart';

/// 7/30 tab-收藏新加: 点关注平台/类别 → 跳到这里看"该平台/类别的最新热门"
/// 7/30 复用 24 桶假数据 (沿用 #103 不接 RSS 避免 CORS 坑), 后续可换真 RSS
class SourceDetailScreen extends StatefulWidget {
  final ContentSource source;
  final bool isElderlyMode;
  final bool isEn;

  const SourceDetailScreen({
    super.key,
    required this.source,
    this.isElderlyMode = false,
    this.isEn = false,
  });

  @override
  State<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends State<SourceDetailScreen> {
  late Future<List<ContentItem>> _future;

  double get _scale => widget.isElderlyMode ? 1.3 : 1.0;
  bool get isEn => widget.isEn;

  @override
  void initState() {
    super.initState();
    _future = ContentAggregator().fetchBySource(widget.source);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ContentAggregator().fetchBySource(widget.source);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.source.icon, size: 22 * _scale, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(widget.source.name, style: TextStyle(fontSize: 18 * _scale)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isEn ? 'Refresh' : '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<ContentItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isEn ? 'Failed to load' : '加载失败: ${snap.error}',
                  style: TextStyle(fontSize: 14 * _scale, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 64, color: Colors.black26),
                    const SizedBox(height: 12),
                    Text(
                      isEn
                          ? 'No content from ${widget.source.name} yet'
                          : '暂无 ${widget.source.name} 的内容',
                      style: TextStyle(fontSize: 16 * _scale, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      isEn
                          ? '${items.length} items · Tap to read'
                          : '${items.length} 条 · 点击阅读',
                      style: TextStyle(
                        fontSize: 13 * _scale,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                final item = items[i - 1];
                return _SourceContentCard(
                  item: item,
                  scale: _scale,
                  isEn: isEn,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SourceContentCard extends StatelessWidget {
  final ContentItem item;
  final double scale;
  final bool isEn;

  const _SourceContentCard({
    required this.item,
    required this.scale,
    required this.isEn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // item 详情: 有 externalUrl 推 in-app webview, 否则推 ContentReaderScreen
            if (item.externalUrl != null && item.externalUrl!.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InAppWebViewScreen(
                    url: item.externalUrl!,
                    title: item.title,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContentReaderScreen(
                    item: item,
                    isEn: isEn,
                  ),
                ),
              );
            }
          },
          child: Padding(
            padding: EdgeInsets.all(14 * scale),
            child: Row(
              children: [
                // 类型 icon
                Container(
                  width: 44 * scale,
                  height: 44 * scale,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _typeIcon(item.contentType),
                    size: 22 * scale,
                    color: AppTheme.primary,
                  ),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15 * scale,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.description.isNotEmpty) ...[
                        SizedBox(height: 4 * scale),
                        Text(
                          item.description,
                          style: TextStyle(
                            fontSize: 12 * scale,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      SizedBox(height: 6 * scale),
                      Row(
                        children: [
                          if (item.duration.isNotEmpty)
                            Text(
                              item.duration,
                              style: TextStyle(fontSize: 11 * scale, color: Colors.black45),
                            ),
                          if (item.duration.isNotEmpty) const SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.contentType.name,
                              style: TextStyle(fontSize: 10 * scale, color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.black26, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(ContentType type) {
    switch (type) {
      case ContentType.article: return Icons.menu_book_outlined;
      case ContentType.audio: return Icons.headphones;
      case ContentType.video: return Icons.play_circle_outline;
      case ContentType.short: return Icons.flash_on;
      case ContentType.card: return Icons.style_outlined;
      case ContentType.quiz: return Icons.quiz_outlined;
    }
  }
}
