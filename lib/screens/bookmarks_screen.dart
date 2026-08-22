// 8/28 P53-4 沿 SOUL #169 不撒谎 + SOUL #188 透明: 我收藏的 内容列表
//   真凶: 之前用户收藏条目后, 没地方看 → 主入口场景 tab 才能看到
//   修: 独立 screen + 跟主入口场景同骨架
//   SOUL #103 治好不抢注意力: 简化 UI (只列条目 + 显示"优质最新")
import 'package:flutter/material.dart';
import '../services/bookmark_service.dart';
import '../models/models.dart';
import 'content_reader_screen.dart';

class BookmarksScreen extends StatefulWidget {
  final bool isEn;
  const BookmarksScreen({super.key, required this.isEn});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<BookmarkEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // 8/28 P53-4: 加 listener 自动刷新
    BookmarkService.instance.addListener(_load);
  }

  @override
  void dispose() {
    BookmarkService.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await BookmarkService.instance.getRecent(limit: 100);
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(widget.isEn ? 'Loading bookmarks...' : '加载收藏中...'),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return _EmptyState(isEn: widget.isEn);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) => _BookmarkTile(
          entry: _entries[i],
          isEn: widget.isEn,
          onTap: () => _openEntry(_entries[i]),
          onRemove: () async {
            await BookmarkService.instance.remove(_entries[i].id);
          },
        ),
      ),
    );
  }

  void _openEntry(BookmarkEntry e) {
    // 8/28 P53-4: 构造 ContentItem (沿 SOUL #169 snapshot 真实数据)
    final item = ContentItem(
      id: e.id,
      title: e.title,
      description: e.description,
      duration: '5min',
      source: e.source,
      sourceType: ContentSource.rss,
      contentType: ContentType.article,
      externalUrl: e.url,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ContentReaderScreen(
        item: item,
        isEn: widget.isEn,
        userType: UserType.student,
        scene: Scene.learn,
      ),
    ));
  }
}

class _BookmarkTile extends StatelessWidget {
  final BookmarkEntry entry;
  final bool isEn;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _BookmarkTile({
    required this.entry,
    required this.isEn,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bookmark, color: Color(0xFF7C5CFC)),
      title: Text(
        entry.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            entry.source,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
          const SizedBox(height: 4),
          // 8/28 P53-4: 显示"收藏时间" (沿 SOUL #188 透明)
          Text(
            _formatTime(entry.addedAt),
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 20),
        color: Colors.grey,
        tooltip: isEn ? 'Remove' : '取消收藏',
        onPressed: onRemove,
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return isEn ? 'just now' : '刚刚';
    if (diff.inHours < 1) return isEn ? '${diff.inMinutes}m ago' : '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return isEn ? '${diff.inHours}h ago' : '${diff.inHours} 小时前';
    if (diff.inDays < 7) return isEn ? '${diff.inDays}d ago' : '${diff.inDays} 天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  final bool isEn;
  const _EmptyState({required this.isEn});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              isEn ? 'No bookmarks yet' : '还没有收藏',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              isEn
                  ? 'Tap the bookmark on any article to save it here.'
                  : '在文章详情页点收藏按钮, 即可在此查看。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}