import 'package:flutter/material.dart';
import '../theme/glass_decoration.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/local_subscription_service.dart';
import '../services/subscription_service.dart';
import '../services/pack_io_helpers.dart';
import '../services/handle_service.dart';
import '../widgets/skeleton.dart';
import 'content_reader_screen.dart';
import 'subscription_screen.dart';

class MySubscriptionsScreen extends StatefulWidget {
  final bool isElderlyMode;
  final bool isEn;

  const MySubscriptionsScreen({
    super.key,
    this.isElderlyMode = false,
    this.isEn = false,
  });

  // 6/24 v8: GlobalKey 让详情页订阅后能 reload
  static final reloadKey = GlobalKey<_MySubscriptionsScreenState>();

  @override
  State<MySubscriptionsScreen> createState() => _MySubscriptionsScreenState();
}

class _MySubscriptionsScreenState extends State<MySubscriptionsScreen>
    with WidgetsBindingObserver {
  final LocalSubscriptionService _subService = LocalSubscriptionService.instance;
  List<ContentItem> _items = [];
  bool _loading = true;
  int _followingPlatforms = 0;
  int _followingCategories = 0;
  String _handle = '@你'; // 6/25 昵称扩展: 顶部显示

  // 6/24 v8: 公开方法, main.dart 切 tab 时调用
  void reload() {
    debugPrint('[MySubs] reload() called, _items.length=${_items.length}');
    _load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final items = await _subService.getSubscribedItems();
    final sources = await SubscriptionService.instance.getSubscribedSources();
    final categories = await SubscriptionService.instance.getSubscribedCategories();
    final handle = await HandleService().get();
    if (!mounted) return;
    setState(() {
      _items = items;
      _followingPlatforms = sources.length;
      _followingCategories = categories.length;
      _handle = handle;
      _loading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _unsubscribe(ContentItem item) async {
    await _subService.unsubscribe(item);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEn ? 'Removed from Saved' : '已从收藏中移除'),
          action: SnackBarAction(
            label: widget.isEn ? 'Undo' : '撤销',
            onPressed: () async {
              await _subService.subscribe(item);
              await _load();
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
    final isEn = widget.isEn;
    // 6/24 v14: ListenableBuilder 监听 service — 任何 subscribe/unsubscribe 触发自动 rebuild
    return ListenableBuilder(
      listenable: LocalSubscriptionService.instance,
      builder: (context, _) => Scaffold(
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(
          isEn ? 'My Saved' : '我的收藏',
          style: TextStyle(fontSize: 18 * scale),
        ),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: isEn ? 'Refresh' : '刷新',
              onPressed: _load,
            ),
          // 6/12 加: 收藏包导入/导出
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: isEn ? 'More' : '更多',
            onSelected: (v) {
              if (v == 'export') {
                PackIO.showExportDialog(context, isEn: isEn);
              } else if (v == 'import') {
                PackIO.showImportDialog(context, isEn: isEn, onDone: _load);
              } else if (v == 'manage') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'export',
                child: Row(children: [
                  const Icon(Icons.download, size: 20),
                  const SizedBox(width: 12),
                  Text(isEn ? 'Export saved' : '导出我的收藏'),
                ]),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(children: [
                  const Icon(Icons.upload, size: 20),
                  const SizedBox(width: 12),
                  Text(isEn ? 'Import from JSON' : '导入收藏包'),
                ]),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'manage',
                child: Row(children: [
                  const Icon(Icons.subscriptions, size: 20),
                  const SizedBox(width: 12),
                  Text(isEn ? 'Manage Following' : '关注管理'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          // 6/23: 骨架屏替换 loading 圈
          ? ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 4,
              itemBuilder: (_, __) => const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: ListItemSkeleton(),
              ),
            )
          : Column(
              children: [
                _buildFollowSummary(scale, isEn),
                Expanded(
                  child: _items.isEmpty
                      ? _buildEmpty(scale, isEn)
                      : ListView.separated(
                          padding: EdgeInsets.all(16 * scale),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => SizedBox(height: 12 * scale),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _SubscribedCard(
                              item: item,
                              scale: scale,
                              isEn: isEn,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ContentReaderScreen(
                                      item: item,
                                      isElderlyMode: widget.isElderlyMode,
                                      isEn: isEn,
                                    ),
                                  ),
                                );
                              },
                              onRemove: () => _unsubscribe(item),
                            );
                          },
                        ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildFollowSummary(double scale, bool isEn) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubscriptionScreen(isEn: isEn),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 0),
        padding: EdgeInsets.all(14 * scale),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.subscriptions, color: AppTheme.primary, size: 20 * scale),
            SizedBox(width: 10 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn
                        ? '${_handle}·s collection · Following ${_followingPlatforms} platforms · ${_followingCategories} categories · ${_items.length} saved'
                        : '${_handle}的收藏 · 已关注 ${_followingPlatforms} 个平台 · ${_followingCategories} 个类目 · ${_items.length} 篇',
                    style: TextStyle(
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    isEn
                        ? 'Tap to manage what you follow →'
                        : '点击管理你关注的内容 →',
                    style: TextStyle(
                      fontSize: 11 * scale,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.primary, size: 20 * scale),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(double scale, bool isEn) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 64 * scale, color: AppTheme.textLight.withOpacity(0.4)),
            SizedBox(height: 16 * scale),
            Text(
              isEn ? 'No saved items yet' : '还没有收藏',
              style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w600, color: AppTheme.textLight),
            ),
            SizedBox(height: 8 * scale),
            Text(
              isEn
                  ? 'Tap the bookmark icon on any article to save it here.'
                  : '在内容页点击 🔖 图标添加到这里',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
            ),
            SizedBox(height: 24 * scale),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubscriptionScreen(isEn: isEn),
                  ),
                );
              },
              icon: Icon(Icons.subscriptions, size: 16 * scale),
              label: Text(
                isEn ? 'Manage Following' : '管理关注',
                style: TextStyle(fontSize: 13 * scale),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscribedCard extends StatelessWidget {
  final ContentItem item;
  final double scale;
  final bool isEn;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SubscribedCard({
    required this.item,
    required this.scale,
    required this.isEn,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.contentType.icon, size: 20 * scale, color: AppTheme.primary),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Text(
                      item.source,
                      style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.priceType.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.priceType.label,
                      style: TextStyle(fontSize: 10 * scale, color: item.priceType.color),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8 * scale),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4 * scale),
              Text(
                item.description ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight),
              ),
              SizedBox(height: 8 * scale),
              Row(
                children: [
                  Icon(Icons.access_time, size: 12 * scale, color: AppTheme.textLight),
                  SizedBox(width: 4 * scale),
                  Text(
                    item.duration,
                    style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                  ),
                  Spacer(),
                  TextButton.icon(
                    onPressed: onRemove,
                    icon: Icon(Icons.bookmark, size: 14 * scale, color: AppTheme.primary),
                    label: Text(
                      isEn ? 'Saved' : '已收藏',
                      style: TextStyle(fontSize: 12 * scale, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
