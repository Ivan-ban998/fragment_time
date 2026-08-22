// 8/28 P62-A 沿 SOUL #137 真凶链 + 用户"点标签可以进入, 给我推荐内容"治本:
//   真凶: 之前关注 tab 类目 chip 点 SnackBar 留此页, 用户看不到该类目内容
//   修: 创建 CategoryDetailScreen (沿 SourceDetailScreen 模式)
//     → ContentAggregator.fetchByCategory() 返回该类目所有内容
//   8/28 P62-A 沿 SOUL #169 不撒谎 + SOUL #103 治好不抢注意力:
//     类目 → 跳到 CategoryDetailScreen, 显示该类目文章 (24 桶过滤)
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/content_aggregator.dart';
import 'content_reader_screen.dart';

/// 8/28 P62-A: 类目详情屏 (沿 SourceDetailScreen 模式)
///   用户点类目 chip → 跳这里 → 看该类目所有文章
class CategoryDetailScreen extends StatefulWidget {
  final String categoryName;
  final bool isElderlyMode;
  final bool isEn;
  final UserType? userType;

  const CategoryDetailScreen({
    super.key,
    required this.categoryName,
    this.isElderlyMode = false,
    this.isEn = false,
    this.userType,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late Future<List<ContentItem>> _future;

  double get _scale => widget.isElderlyMode ? 1.3 : 1.0;
  bool get isEn => widget.isEn;

  @override
  void initState() {
    super.initState();
    _future = ContentAggregator().fetchByCategory(widget.categoryName);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ContentAggregator().fetchByCategory(widget.categoryName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _scale;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(widget.categoryName,
            style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: isEn ? 'Refresh' : '刷新',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<ContentItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.category_outlined, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      isEn
                          ? 'No content for "${widget.categoryName}"'
                          : '"${widget.categoryName}" 类目暂无内容',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: EdgeInsets.all(16 * s),
              itemCount: items.length,
              separatorBuilder: (_, __) => SizedBox(height: 12 * s),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    leading: Icon(item.contentType.icon, size: 28 * s, color: AppTheme.primary),
                    title: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          item.source,
                          style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight),
                        ),
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11 * s, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                    trailing: Icon(Icons.chevron_right, color: AppTheme.textLight),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContentReaderScreen(
                            item: item,
                            isElderlyMode: widget.isElderlyMode,
                            isEn: isEn,
                            userType: widget.userType ?? UserType.student,
                            scene: Scene.learn,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}