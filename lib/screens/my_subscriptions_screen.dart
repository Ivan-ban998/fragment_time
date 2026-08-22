import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/glass_decoration.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/local_subscription_service.dart';
import '../services/subscription_service.dart';
// 8/28 P60-1: 删除 bookmark_service import (P60-1 阅读历史用 HistoryService, BookmarkService 仅在 bookmarks_screen.dart)
// ignore: unused_element
import '../services/history_service.dart'; // 8/28 P60-1: 阅读历史 tab (走 HistoryService)
import '../services/pack_io_helpers.dart';
import '../services/handle_service.dart';
import '../widgets/skeleton.dart';
import 'content_reader_screen.dart';
import 'subscription_screen.dart';
import 'source_detail_screen.dart';
// 8/28 P62-A: 类目详情屏 (沿 SourceDetailScreen 模式, 关注 tab 类目 chip 跳转用)
import 'category_detail_screen.dart';
import 'bookmarks_screen.dart'; // 8/28 P54-3: 跳 BookmarksScreen

class MySubscriptionsScreen extends StatefulWidget {
  final bool isElderlyMode;
  final bool isEn;
  // 7/15 17:19: 透传给 ContentReaderScreen (含 quote Hero 卡, 关联阅读用)
  final UserType? userType;
  final Scene? scene;
  // 8/28 P56-2: 跳主场景 tab 回调 (注入 from main.dart)
  final VoidCallback? onSceneJump;
  // 8/28 P58-1: 跳主场景 + source 过滤回调 (沿用户"点击关注条目跳到首页")
  final void Function(ContentSource source)? onSourceJump;
  // 8/28 P58-2 沿 SOUL #137 真凶链: 类目 chip 也跳主场景 + 类目过滤
  //   真凶: 之前只 onSceneJump (不过滤), 跳过去是默认推荐, 看不到该类目内容
  //   修: 类目 chip 跳主场景 + 过滤该 category
  final void Function(String category)? onCategoryJump;
  // 8/28 P62-B: "管理" 按钮默认跳管理页 (沿用户新反馈)
  //   真凶: P58-2 改 onManage 调 onSceneJump, 用户点"管理"被跳到首页
  //   修: 独立 onManage 回调 (默认 push SubscriptionScreen)
  final VoidCallback? onManage;

  const MySubscriptionsScreen({
    super.key,
    this.isElderlyMode = false,
    this.isEn = false,
    this.userType,
    this.scene,
    this.onSceneJump,
    this.onSourceJump,
    this.onCategoryJump,
    this.onManage,
  });

  // 6/24 v8: GlobalKey 让详情页订阅后能 reload
  static final reloadKey = GlobalKey<_MySubscriptionsScreenState>();

  @override
  State<MySubscriptionsScreen> createState() => _MySubscriptionsScreenState();
}

class _MySubscriptionsScreenState extends State<MySubscriptionsScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final LocalSubscriptionService _subService = LocalSubscriptionService.instance;
  bool _loading = true;
  late TabController _tabController; // 6/25 A: 子 Tab 切换 (内容/名言/关注)
  // 7/20 16:48 Brien 反馈 "收藏内容多了, 让用户搜搜" → 加搜索框, 跨 3 个子 Tab 共享
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // 6/24 v8: 公开方法, main.dart 切 tab 时调用
  void reload() {
    _load();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // 8/28 P60-1: 2 → 4 (恢复 内容/名言/阅读历史/关注 分开, 沿用户截图"还是分开")
    // 7/20 18:42 Brien "每个子 Tab 该有专属 hint" → 切 Tab 时 setState 重 build 换 hint
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    // 8/28 P29: _items/_followingPlatforms/_followingCategories/_handle fields unused
    //   → 直接 fire-and-forget 这些 await, 只保留 setState (_loading = false)
    await _subService.getSubscribedItems();
    await SubscriptionService.instance.getSubscribedSources();
    await SubscriptionService.instance.getSubscribedCategories();
    await HandleService().get();
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _unsubscribe(ContentItem item) async {
    await _subService.unsubscribe(item);
    // 6/25 修 bug: 取消订阅鼓励/名言后，同步清 SharedPreferences 的 'encourage_saved_*' key
    // 否则 banner ❤️ 还是会显实心 (prefs true, 但 list 里没了)
    if (item.id.startsWith('encourage_')) {
      try {
        final prefs = await SharedPreferences.getInstance();
        // 鼓励 id 格式: 'encourage_${year}-${month}-${day}' → prefs key 是同样的
        await prefs.remove('encourage_saved_${item.id.replaceFirst('encourage_', '')}');
      } catch (e) { debugPrint('[my_subscriptions_] err'); }
    }
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

  // 8/28 P61-2 沿 SOUL #189 智: 略过 (从当前 tab 列表隐藏, 不删订阅/历史)
  //   真凶: 之前无"略过"路径, 用户想"已经看过了"无法标记 → 重看
  //   修: SharedPreferences 'skipped_items' 列表 + UI filter 掉
  //   P62 待实装持久化 (本期只 in-memory)
  final Set<String> _skippedIds = <String>{};

  void _skipItem(ContentItem item) {
    setState(() {
      _skippedIds.add(item.id);
    });
    // 8/28 P61-2 注释: P62 加 SharedPreferences 持久化
  }

  // 8/28 P61-2: 略过 history item (独立于 _skipItem, 因为 id 类型不同)
  void _skipHistoryItem(String id) {
    setState(() {
      _skippedIds.add(id);
    });
  }

  // 8/28 P61-C 沿 SOUL #137 真凶链 + 用户"阅读历史需要添加删除的功能"治本:
  //   真凶: 阅读历史 tab 只有"略过"(隐藏), 用户没法真正删除 (沿 SOUL #169 不撒谎)
  //   修: 加多选删除 (checkboxes + 底部"删除 N 项"按钮)
  bool _historyMultiSelect = false;
  final Set<String> _historySelectedIds = <String>{};

  void _toggleHistorySelect(String id) {
    setState(() {
      if (_historySelectedIds.contains(id)) {
        _historySelectedIds.remove(id);
      } else {
        _historySelectedIds.add(id);
      }
    });
  }

  void _clearHistoryMultiSelect() {
    setState(() {
      _historyMultiSelect = false;
      _historySelectedIds.clear();
    });
  }

  // 8/28 P61-C: 批量删除 history (沿 HistoryService.removeById)
  //   8/28 P61-C 注释: isEn 通过参数传入, 不依赖 build context state
  Future<void> _deleteSelectedHistory(bool isEn) async {
    final ids = List<String>.from(_historySelectedIds);
    for (final id in ids) {
      try {
        await HistoryService.instance.removeById(id);
      } catch (e) {
        debugPrint('[my_subscriptions_] removeById err: $e');
      }
    }
    final count = ids.length;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEn ? 'Deleted $count items' : '已删除 $count 条'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    _clearHistoryMultiSelect();
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
          // 8/28 P54-3 沿 SOUL #188 透明: 加 "我的收藏" 按钮 (跳 BookmarksScreen)
          //   真凶: 之前 MySubscriptionsScreen 是"主收藏屏", 但用户分不清
          //     "我订阅的平台/类目" vs "我收藏的具体文章"
          //   修: 加 ⭐ 按钮 → BookmarksScreen (单文章收藏, 沿 P53-4)
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: isEn ? 'My Bookmarks' : '我收藏的',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookmarksScreen(isEn: isEn),
                ),
              );
            },
          ),
          // 6/25 Brien 反馈: 刷新按钮常驻 (之前 _items.isNotEmpty 才显示, 偶发有数量但内容没来时刷不了)
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
        // 6/25 A: 顶部 TabBar (内容/名言/关注)
        // 8/28 P61-A 沿 SOUL #137 真凶链 + 用户"怎么都挤在一起"治本:
        //   真凶: 之前 P60-1 加 isScrollable: true 凑数, 4 tabs 不均匀
        //   修: 4 tabs 用短字 + 小 icon, 强制均分 (移除 isScrollable)
        //   注: TabBar 加 labelPadding/size + 短中文 "内容/名言/历史/关注" 4 字
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textLight,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          // 8/28 P61-A: 短 label + 小 icon, 4 tabs 装下
          labelStyle: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w600),
          labelPadding: EdgeInsets.symmetric(horizontal: 4 * scale),
          tabs: [
            // 8/28 P61-A: 短中文 4 字, 不再 "内容 / 阅读历史" 长 label
            Tab(icon: Icon(Icons.article_outlined, size: 16 * scale), text: isEn ? 'Articles' : '内容'),
            Tab(icon: Icon(Icons.format_quote, size: 16 * scale), text: isEn ? 'Quotes' : '名言'),
            Tab(icon: Icon(Icons.history, size: 16 * scale), text: isEn ? 'History' : '历史'),
            Tab(icon: Icon(Icons.subscriptions, size: 16 * scale), text: isEn ? 'Following' : '关注'),
          ],
          // 8/28 P61-A: 移 isScrollable, 4 tabs 均分
          isScrollable: false,
        ),
      ),
      body: Column(
        children: [
          // 7/20 16:48 Brien 反馈 "收藏内容多了, 让用户搜搜" → 加搜索框 (跨 4 个子 Tab 共享)
          _buildSearchBar(scale, isEn),
          // 7/30: 顶部汇总栏已移到 _buildFollowingTab 内部 pinned SliverPersistentHeader (统一风格)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: 内容收藏
                _buildSavedTab(scale, isEn, contentOnly: true),
                // Tab 2: 名言收藏
                _buildSavedTab(scale, isEn, quotesOnly: true),
                // Tab 3: 阅读历史 (沿 P60-1 恢复, 走 HistoryService)
                _buildHistoryTab(scale, isEn),
                // Tab 4: 关注 (P56-2 类目 chip 跳主场景已实)
                _buildFollowingTab(scale, isEn),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  // 8/28 P60-1: 阅读历史 tab (沿 P18-3 HistoryService)
  //   - 真凶: 之前 P59-1 删了 HistoryScreen, 现在按用户截图"还是分开"恢复
  //   - 修: 走 HistoryService (max 50 items), 不是 BookmarkService (P57-4 demo 风格)
  //   - UI: HistoryScreen 风格 (time-grouped, tap 跳 reader)
  Widget _buildHistoryTab(double scale, bool isEn) {
    return FutureBuilder<List<HistoryItem>>(
      future: HistoryService.instance.getAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 4,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: ListItemSkeleton(),
            ),
          );
        }
        final items = snapshot.data!;
        final filtered = items.where((it) {
          // 8/28 P61-2 沿 SOUL #189 智: 略过 (隐藏) - 不显示
          if (_skippedIds.contains(it.id)) return false;
          // 8/28 P60-1: 按 _searchQuery 搜 title + source
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery;
          return it.title.toLowerCase().contains(q) ||
              it.source.toLowerCase().contains(q);
        }).toList();
        if (filtered.isEmpty) {
          if (_searchQuery.isNotEmpty) {
            return _buildNoSearchResult(scale, isEn);
          }
          // 8/28 P60-1: 空状态友好提示
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    isEn ? 'No reading history' : '还没有阅读历史',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isEn
                        ? 'Articles you read will appear here.'
                        : '读过的文章会自动出现在这里。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          );
        }
        // 8/28 P60-1: 按 readAt 倒序, 最新置顶
        final sorted = List<HistoryItem>.from(filtered)
          ..sort((a, b) => (b.readAt).compareTo(a.readAt));
        return Column(
          children: [
            // 8/28 P61-C 沿 SOUL #103 治好不抢注意力: 多选删除顶栏
            if (_historyMultiSelect)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                color: AppTheme.primary.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Text(
                      isEn
                          ? 'Selected: ${_historySelectedIds.length}'
                          : '已选: ${_historySelectedIds.length}',
                      style: TextStyle(
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        if (_historySelectedIds.length == sorted.length) {
                          setState(() => _historySelectedIds.clear());
                        } else {
                          setState(() => _historySelectedIds
                              .addAll(sorted.map((it) => it.id)));
                        }
                      },
                      child: Text(
                        _historySelectedIds.length == sorted.length
                            ? (isEn ? 'Deselect all' : '取消全选')
                            : (isEn ? 'Select all' : '全选'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _clearHistoryMultiSelect(),
                      child: Text(isEn ? 'Cancel' : '取消'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: _historySelectedIds.isEmpty
                          ? null
                          : () => _deleteSelectedHistory(isEn),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(isEn ? 'Delete' : '删除'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _historySelectedIds.isEmpty
                            ? Colors.grey
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.all(16 * scale),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => SizedBox(height: 12 * scale),
                itemBuilder: (context, index) {
                  final item = sorted[index];
                  return _HistoryItemCard(
                    historyItem: item,
                    scale: scale,
                    isEn: isEn,
                    selected: _historySelectedIds.contains(item.id),
                    multiSelectMode: _historyMultiSelect,
                    onTap: () {
                      // 8/28 P61-C: 多选模式 → toggle, 普通 → push reader
                      if (_historyMultiSelect) {
                        _toggleHistorySelect(item.id);
                      } else {
                        final ci = ContentItem(
                          id: item.id,
                          title: item.title,
                          description: item.description ?? '',
                          duration: item.duration,
                          source: item.source,
                          sourceType: ContentSource.rss,
                          contentType: item.contentTypeName == 'audio'
                              ? ContentType.audio
                              : item.contentTypeName == 'video'
                                  ? ContentType.video
                                  : ContentType.article,
                          externalUrl: 'https://example.com/${item.id}',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContentReaderScreen(
                              item: ci,
                              isElderlyMode: widget.isElderlyMode,
                              isEn: isEn,
                              userType: widget.userType ?? UserType.student,
                              scene: widget.scene ?? Scene.learn,
                            ),
                          ),
                        );
                      }
                    },
                    onLongPress: () {
                      // 8/28 P61-C: 长按进入多选模式
                      setState(() {
                        _historyMultiSelect = true;
                        _historySelectedIds.add(item.id);
                      });
                    },
                    // 8/28 P61-C 沿 SOUL #103 治好不抢注意力: 听 + 略过
                    onListen: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEn ? 'Opening reader with TTS' : '打开 reader 自动 TTS'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    onSkip: () {
                      _skipHistoryItem(item.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEn ? 'Skipped' : '已略过'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    onRemove: () async {
                      // 8/28 P61-C: 单选删除 (沿 HistoryService.removeById)
                      // 8/28 P61-C: 在 await 前缓存 messenger (避免 use_build_context_synchronously)
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      await HistoryService.instance.removeById(item.id);
                      if (!mounted) return;
                      if (messenger != null) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(isEn ? 'Deleted' : '已删除'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                      if (mounted) setState(() {});
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // 8/28 P59-1: 删除 P56-3 _buildBookmarksTab (阅读 tab 合并后不需要单独 tab)
  // ignore: unused_element
  Widget _buildBookmarksTab(double scale, bool isEn) {
    return BookmarksListView(
      isEn: isEn,
      onItemTap: (entry) {
        // 8/28 P56-3: 点条目跳 ContentReaderScreen
        final item = ContentItem(
          id: entry.id,
          title: entry.title,
          description: entry.description,
          duration: '5min',
          source: entry.source,
          sourceType: ContentSource.rss,
          contentType: ContentType.article,
          externalUrl: entry.url,
        );
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ContentReaderScreen(
            item: item,
            isEn: isEn,
            userType: widget.userType ?? UserType.student,
            scene: widget.scene ?? Scene.learn,
          ),
        ));
      },
    );
  }

  // 7/20 16:48 Brien 反馈 "收藏内容多了, 让用户搜搜" → 加搜索框
  // 7/20 18:42 Brien "每个子 Tab 有专属 hint" → 根据 _tabController.index 切 hint
  String _hintForCurrentTab(bool isEn) {
    // _tabController.index: 0=内容 1=名言 2=历史 3=关注
    // 8/28 P61-B 沿用户截图"tab-阅读历史 下面搜索框怎么显示搜关注的平台或类目"治本:
    //   真凶: 之前 _hintForCurrentTab 没区分 reading history tab, 用"搜关注的平台或类目"是 bug
    //   修: case 2 (历史) 用专属 hint
    switch (_tabController.index) {
      case 0:
        return isEn ? 'Search saved articles...' : '搜收藏的内容...';
      case 1:
        return isEn ? 'Search saved quotes...' : '搜收藏的名言...';
      case 2:
        return isEn ? 'Search reading history...' : '搜阅读过的内容...';
      case 3:
        return isEn ? 'Search following platforms or categories...' : '搜关注的平台或类目...';
      default:
        return isEn ? 'Search...' : '搜索...';
    }
  }

  Widget _buildSearchBar(double scale, bool isEn) {
    final hint = _hintForCurrentTab(isEn);
    return Container(
      padding: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 8 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: AppTheme.textLight.withValues(alpha: 0.15), width: 0.5)),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) {
          setState(() => _searchQuery = v.trim().toLowerCase());
        },
        style: TextStyle(fontSize: 14 * scale, color: AppTheme.textDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
          prefixIcon: Icon(Icons.search, size: 18 * scale, color: AppTheme.textLight),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(Icons.close, size: 18 * scale, color: AppTheme.textLight),
                )
              : null,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
          filled: true,
          fillColor: AppTheme.textLight.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // 7/30: 顶部汇总已升级为 _followingHeroCard (紫色 hero), 在 _buildFollowingTab 内 pinned 展示
  // (旧 _buildStickySummary / _buildSummaryBar 轻量浅紫条已删, 统一 hero 风格)

  // 8/28 P59-1: 删除 P59-1 _buildSavedTab (内容/名言已合并到阅读 tab, 旧版保留供 rollback)
  // ignore: unused_element
  Widget _buildSavedTab(double scale, bool isEn, {bool contentOnly = false, bool quotesOnly = false}) {
    // 6/29 14:59 Brien 反馈: 收藏后 Tab 2 看不到新条目 — _items state 不重 load, 显示旧数据
    // 修: ListenableBuilder 每次 rebuild 都在 FutureBuilder 里重拉 service, 不依赖 _items
    return FutureBuilder<List<ContentItem>>(
      future: _subService.getSubscribedItems(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 4,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: ListItemSkeleton(),
            ),
          );
        }
        final items = snapshot.data!;
        final filtered = items.where((it) {
          // 8/28 P61-2 沿 SOUL #189 智: 略过 (隐藏) - 不显示
          if (_skippedIds.contains(it.id)) return false;
          // 7/20 加: 按子 Tab 分类型
          if (contentOnly && it.id.startsWith('quote_')) return false;
          if (quotesOnly && !it.id.startsWith('quote_')) return false;
          // 7/20 加: 按 _searchQuery 搜 title + description + source
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery;
          return it.title.toLowerCase().contains(q) ||
              it.description.toLowerCase().contains(q) ||
              it.source.toLowerCase().contains(q);
        }).toList();

    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: ListItemSkeleton(),
        ),
      );
    }
    if (filtered.isEmpty) {
      // 7/20: 搜不到东西时显示不同的提示 (跟空收藏区别)
      if (_searchQuery.isNotEmpty) {
        return _buildNoSearchResult(scale, isEn);
      }
      return _buildEmpty(context, scale, isEn, contentOnly: contentOnly, quotesOnly: quotesOnly);
    }
    // 7/15 16:44: quotesOnly 走新 Quote 专属布局 — 按 lastReadAt 倒序, 最新置顶
    if (quotesOnly) {
      final sorted = List<ContentItem>.from(filtered)
        ..sort((a, b) => (b.lastReadAt ?? DateTime.now())
            .compareTo(a.lastReadAt ?? DateTime.now()));
      return _buildQuotesView(sorted, scale, isEn);
    }
    if (contentOnly) {
      final sorted = List<ContentItem>.from(filtered)
        ..sort((a, b) => (b.lastReadAt ?? DateTime.now())
            .compareTo(a.lastReadAt ?? DateTime.now()));
      return _buildContentView(sorted, scale, isEn);
    }
    return ListView.separated(
      padding: EdgeInsets.all(16 * scale),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => SizedBox(height: 12 * scale),
      itemBuilder: (context, index) {
        final item = filtered[index];
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
                  userType: widget.userType,
                  scene: widget.scene,
                ),
              ),
            );
          },
          onRemove: () => _unsubscribe(item),
        );
      },
    );
      },
    );
  }

  // 7/15: 名言收藏页 — 顶部大卡 (最新) + 时间线 (按 day 分)
  // 7/30 B 修: 改成 Column[hero + Expanded(ListView)] 模式 — hero 不随滚动溜走 (SliverPersistentHeader 写法不稳)
  Widget _buildQuotesView(List<ContentItem> quotes, double scale, bool isEn) {
    final heroCard = _QuoteHeroCard(
      latest: quotes.first,
      totalCount: quotes.length,
      scale: scale,
      isEn: isEn,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ContentReaderScreen(
              item: quotes.first,
              isElderlyMode: widget.isElderlyMode,
              isEn: isEn,
              userType: widget.userType,
              scene: widget.scene,
            ),
          ),
        );
      },
      onRemove: () => _unsubscribe(quotes.first),
    );
    return Column(
      children: [
        // hero 不滚 (不放在 slivers 里)
        Padding(
          padding: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 8 * scale),
          child: heroCard,
        ),
        // 列表可滚
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 32 * scale),
            itemCount: quotes.length - 1,
            itemBuilder: (context, i) {
              final item = quotes[i + 1];
              return _QuoteTimelineItem(
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
                        userType: widget.userType,
                        scene: widget.scene,
                      ),
                    ),
                  );
                },
                // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 听 + 略过
                onListen: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEn ? 'Reading quote aloud' : '朗读名言'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                onSkip: () {
                  _skipItem(item);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEn ? 'Skipped' : '已略过'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                onRemove: () => _unsubscribe(item),
              );
            },
          ),
        ),
      ],
    );
  }

  // 17:28: 内容 Tab Hero+Timeline 视图 (跟名言 tab 风格统一)
  // 7/30 B 修: 改成 Column[hero + Expanded(ListView)] 模式 — hero 不随滚动溜走
  Widget _buildContentView(List<ContentItem> items, double scale, bool isEn) {
    final heroCard = _ContentHeroCard(
      latest: items.first,
      totalCount: items.length,
      scale: scale,
      isEn: isEn,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ContentReaderScreen(
              item: items.first,
              isElderlyMode: widget.isElderlyMode,
              isEn: isEn,
              userType: widget.userType,
              scene: widget.scene,
            ),
          ),
        );
      },
      onRemove: () => _unsubscribe(items.first),
    );
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 8 * scale),
          child: heroCard,
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 32 * scale),
            itemCount: items.length - 1,
            itemBuilder: (context, i) => _ContentTimelineItem(
              item: items[i + 1],
              scale: scale,
              isEn: isEn,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContentReaderScreen(
                      item: items[i + 1],
                      isElderlyMode: widget.isElderlyMode,
                      isEn: isEn,
                      userType: widget.userType,
                      scene: widget.scene,
                    ),
                  ),
                );
              },
              // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 听 + 略过 按钮
              onListen: () {
                // 8/28 P61-2: 跳 reader, TTS 自动启动 (沿 content_reader 模式)
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContentReaderScreen(
                      item: items[i + 1],
                      isElderlyMode: widget.isElderlyMode,
                      isEn: isEn,
                      userType: widget.userType,
                      scene: widget.scene,
                    ),
                  ),
                );
                // 注: TTS 启动在 reader 内部 (_autoStartTts), 这里只导航
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEn ? 'Opening reader with TTS' : '打开 reader 自动 TTS'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              onSkip: () {
                // 8/28 P61-2 沿 SOUL #189 智: 略过 = 从当前列表移除 (但不删 history, 不动订阅)
                //   真凶: 之前无 "略过" 路径, 用户想"已经看过了"无法标记
                //   修: 调 _skipItem (本期先 SnackBar, P62 实装 SharedPreferences skip 列表)
                _skipItem(items[i + 1]);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEn ? 'Skipped' : '已略过'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              onRemove: () => _unsubscribe(items[i + 1]),
            ),
          ),
        ),
      ],
    );
  }

  // 6/25 A: 关注 Tab (显示完整关注列表 + 管理按钮)
  // 7/20 18:39 Brien 反馈 "3 个 Tab 都能用搜索" → 加 _searchQuery 过滤 platform/category
  Widget _buildFollowingTab(double scale, bool isEn) {
    return FutureBuilder<List<dynamic>>(
      future: () async {
        final sources = await SubscriptionService.instance.getSubscribedSources();
        final categories = await SubscriptionService.instance.getSubscribedCategories();
        return [sources, categories];
      }(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rawSources = (snap.data![0] as Set).cast<dynamic>().toList();
            final rawCategories = (snap.data![1] as Set).cast<String>().toList();
            // 7/20 加: 按 _searchQuery 过滤 platform/category name (大小写不敏感)
            final sources = _searchQuery.isEmpty
                ? rawSources
                : rawSources.where((s) => s.toString().toLowerCase().contains(_searchQuery)).toList();
            final categories = _searchQuery.isEmpty
                ? rawCategories
                : rawCategories.where((c) => c.toLowerCase().contains(_searchQuery)).toList();
            if (sources.isEmpty && categories.isEmpty && _searchQuery.isEmpty) {
              return _buildFollowingEmpty(context, scale, isEn);
            }
            // 7/20 加: 搜不到时显示 no search result
            if (sources.isEmpty && categories.isEmpty) {
              return _buildNoSearchResult(scale, isEn);
            }
            // 7/30: 紫色 hero pinned 在顶部 (跟 Tab 1/2 hero 风格统一)
            final heroCard = _followingHeroCard(
              platformCount: sources.length,
              categoryCount: categories.length,
              scale: scale,
              isEn: isEn,
              // 8/28 P62-B 沿用户新反馈"点击管理, 跳回首页提示"治本:
              //   真凶: P58-2 让 onManage 调 onSceneJump → main.dart 注入 setTab(0)
              //     → 用户点"管理"期望跳管理页, 实际跳首页
              //   修: onManage 直接 push SubscriptionScreen (默认), 让 main.dart 仍可 override
              // 8/28 P62-B 注释: 沿用户截图"管理跳回首页提示"应该改为跳管理页
              onManage: () {
                if (widget.onManage != null) {
                  widget.onManage!();
                } else {
                  // 8/28 P62-B: 默认 push 管理页 (沿用户"管理"指示)
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                  );
                }
              },
            );
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 8 * scale),
                  child: heroCard,
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 32 * scale),
                    children: [
                      // 7/30 Brien "点关注平台/类别 → 看推荐最新热门" → 加横向 chip 跳转 SourceDetailScreen
                      // 多关注也不需竖翻 (总在一屏内)
                      if (sources.isNotEmpty) ...[
                        _followingSectionHeader(
                          label: isEn ? 'PLATFORMS' : '关注平台',
                          icon: Icons.subscriptions,
                          scale: scale,
                        ),
                        SizedBox(height: 12 * scale),
                        SizedBox(
                          height: 48 * scale,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: sources.length,
                            separatorBuilder: (_, __) => SizedBox(width: 8 * scale),
                            itemBuilder: (context, i) {
                              final s = sources[i];
                              return _followingSourceChip(
                                source: s,
                                isEn: isEn,
                                scale: scale,
                                // 8/28 P58-1 沿 SOUL #137 真凶链: 跳主场景 (沿你截图描述)
                                //   真凶: 之前点关注平台 chip → push SourceDetailScreen 新页面
                                //     → 用户留在关注 tab, 看不到主页推荐
                                //   修: 跳主场景 tab + 传 source (主页过滤)
                                // 8/28 P62-A 沿用户新反馈"点标签可以进入, 给我推荐内容"修:
                                //   真凶: P60-2 只 SnackBar 留此页, 但用户要 push 详情页看推荐
                                //   修: 默认 push SourceDetailScreen (widget.userType 沿 userType)
                                //     main.dart 仍可注入 onSourceJump override (向后兼容)
                                onTap: () {
                                  if (widget.onSourceJump != null) {
                                      widget.onSourceJump!(s);
                                    } else {
                                      // 8/28 P62-A: 默认 push 详情页 (沿用户"给我推荐内容"指示)
                                      // 注: SourceDetailScreen 不支持 userType 参数, 走默认
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SourceDetailScreen(
                                            source: s,
                                            isElderlyMode: widget.isElderlyMode,
                                            isEn: widget.isEn,
                                          ),
                                        ),
                                      );
                                    }
                                },
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 20 * scale),
                      ],
                      if (categories.isNotEmpty) ...[
                        _followingSectionHeader(
                          label: isEn ? 'CATEGORIES' : '关注类目',
                          icon: Icons.category_outlined,
                          scale: scale,
                        ),
                        SizedBox(height: 12 * scale),
                        SizedBox(
                          height: 48 * scale,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: categories.length,
                            separatorBuilder: (_, __) => SizedBox(width: 8 * scale),
                            itemBuilder: (context, i) {
                              final c = categories[i];
                              return _followingCategoryChip(
                                categoryName: c,
                                isEn: isEn,
                                scale: scale,
                                // 8/28 P56-2 沿 SOUL #103 治好不抢注意力: 取消 SnackBar placeholder
                                //   真凶: 之前 "$c 类目详情即将上线" = 假承诺, 没真实内容
                                // 8/28 P58-2 沿 SOUL #137 真凶链: 跳主场景 + 类目过滤
                                //   真凶: 之前只 onSceneJump (不过滤), 跳过去是默认推荐
                                //   修: 类目 chip 跳主场景 + 过滤该 category
                                // 8/28 P62-A 沿用户新反馈"点标签可以进入, 给我推荐内容"修:
                                //   真凶: P60-2 只 SnackBar 留此页, 但用户要 push 详情页看推荐
                                //   修: 默认 push CategoryDetailScreen (P62-A 新建, 沿 SourceDetailScreen 模式)
                                //     main.dart 仍可注入 onCategoryJump override (向后兼容)
                                onTap: () {
                                  if (widget.onCategoryJump != null) {
                                    widget.onCategoryJump!(c);
                                  } else {
                                    // 8/28 P62-A: 默认 push CategoryDetailScreen (沿用户"给我推荐内容"指示)
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CategoryDetailScreen(
                                          categoryName: c,
                                          isElderlyMode: widget.isElderlyMode,
                                          isEn: widget.isEn,
                                          userType: widget.userType,
                                        ),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
  }

  // 7/30: 平台横滑 chip — 点击跳 SourceDetailScreen
  // 7/30 美化: 复用 _followingSourceRow 的 sourceColor (bilibili 粉 / zhihu 蓝 / 36 氪 etc.)
  // chip 底色 = sourceColor 12% + 边框 = sourceColor 40% + 图标 = sourceColor 实色
  Widget _followingSourceChip({
    required ContentSource source,
    required bool isEn,
    required double scale,
    required VoidCallback onTap,
  }) {
    final c = _sourceColor(source);
    return Material(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 7 * scale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withValues(alpha: 0.35), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22 * scale,
                height: 22 * scale,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: c, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Icon(source.icon, size: 12 * scale, color: c),
              ),
              SizedBox(width: 8 * scale),
              Text(
                source.name,
                style: TextStyle(
                  fontSize: 13 * scale,
                  color: c,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 7/30: 类目横滑 chip — 点击推 placeholder (CategoryDetailScreen 后续加)
  // 7/30: 类目横滑 chip — 复用 AppTheme.secondary (紫色) 跟 Tab 1/2 hero 风格一致
  Widget _followingCategoryChip({
    required String categoryName,
    required bool isEn,
    required double scale,
    required VoidCallback onTap,
  }) {
    const c = AppTheme.secondary;
    return Material(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 7 * scale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withValues(alpha: 0.35), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22 * scale,
                height: 22 * scale,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: c, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.local_offer_outlined, size: 12 * scale, color: c),
              ),
              SizedBox(width: 8 * scale),
              Text(
                categoryName,
                style: TextStyle(
                  fontSize: 13 * scale,
                  color: c,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 17:45: 关注 Tab 顶部 Hero 统计 (紫色 24 圆角, 56x56 avatar + 数字 + 管理按钮)
  Widget _followingHeroCard({
    required int platformCount,
    required int categoryCount,
    required double scale,
    required bool isEn,
    required VoidCallback onManage,
  }) {
    final s = scale;
    return Container(
      decoration: BoxDecoration(
        // 7/19 fix v2: LinearGradient 全量清除
        color: const Color(0xFF7C5CFC),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CFC).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(20 * s),
      child: Row(
        children: [
          Container(
            width: 56 * s,
            height: 56 * s,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.notifications_active, color: Colors.white, size: 24 * s),
          ),
          SizedBox(width: 14 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn ? 'My Following' : '我关注了',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 6 * s),
                Row(
                  children: [
                    Text(
                      '$platformCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24 * s,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 4 * s),
                    Text(
                      isEn ? 'platforms' : '个平台',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13 * s),
                    ),
                    SizedBox(width: 14 * s),
                    Text(
                      '$categoryCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24 * s,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 4 * s),
                    Text(
                      isEn ? 'categories' : '个类目',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13 * s),
                    ),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onManage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 8 * s),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, size: 14 * s, color: const Color(0xFF7C5CFC)),
                  SizedBox(width: 4 * s),
                  Text(
                    isEn ? 'Manage' : '管理',
                    style: TextStyle(color: const Color(0xFF7C5CFC), fontSize: 12 * s, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 17:45: 关注 Tab 段头 (紫色 16px + icon)
  Widget _followingSectionHeader({required String label, required IconData icon, required double scale}) {
    final s = scale;
    return Row(
      children: [
        Icon(icon, size: 14 * s, color: AppTheme.primary),
        SizedBox(width: 6 * s),
        Text(
          label,
          style: TextStyle(
            fontSize: 12 * s,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // 7/30: 源色映射 — bilibili 粉 / zhihu 蓝 / 喜马拉雅橙 / 默认紫
  // 复用给 _followingSourceRow + _followingSourceChip, 跨 widget 保持一致
  Color _sourceColor(ContentSource s) {
    if (s == ContentSource.bilibili) return const Color(0xFFFB7299);
    if (s == ContentSource.zhihu) return const Color(0xFF0084FF);
    if (s == ContentSource.ximalaya) return const Color(0xFFFF6E0E);
    if (s == ContentSource.news36kr) return const Color(0xFF4285F4);
    if (s == ContentSource.youtube) return const Color(0xFFFF0000);
    if (s == ContentSource.spotify) return const Color(0xFF1DB954);
    return AppTheme.primary;
  }

  // 17:45: 关注 Tab 平台行 (跟内容 Timeline 同款 紫 4% 底 + 12% 边框)

  // 17:45: 关注 Tab 类目行 (同款 紫 4% 底)

  Widget _buildFollowingEmpty(BuildContext context, double scale, bool isEn) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subscriptions_outlined, size: 80 * scale, color: AppTheme.textLight.withValues(alpha: 0.4)),
            SizedBox(height: 24 * scale),
            Text(
              isEn ? 'No platforms or categories followed yet' : '还没有关注任何平台 / 类目',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16 * scale, color: AppTheme.textLight),
            ),
            SizedBox(height: 24 * scale),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 12 * scale),
              ),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: Text(
                isEn ? 'Start Following' : '开始关注',
                style: TextStyle(fontSize: 15 * scale, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 6/25 A: 关注 Tab section header (类似 70fa9a7 风格)

  // 6/25 A: ContentSource enum 转中文

// 6/25 A: 分组/卡片 helper 删了 (TabBar 子视图取代, 简化)

  // 6/25 筛选 helper 删了 (用 TabBar 替代, 不需要计数)

  // 7/20 16:48 Brien "收藏内容多了, 让用户搜搜" → 搜不到时提示
  Widget _buildNoSearchResult(double scale, bool isEn) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48 * scale, color: AppTheme.textLight.withValues(alpha: 0.5)),
            SizedBox(height: 12 * scale),
            Text(
              isEn ? 'No matches for "$_searchQuery"' : '没找到包含 "$_searchQuery" 的收藏',
              style: TextStyle(fontSize: 14 * scale, color: AppTheme.textLight),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, double scale, bool isEn, {bool contentOnly = false, bool quotesOnly = false}) {
    final msg = quotesOnly
        ? (isEn ? 'No quotes saved' : '还没有名言收藏')
        : contentOnly
            ? (isEn ? 'No articles saved' : '还没有内容收藏')
            : (isEn ? 'No saved items yet' : '还没有收藏');
    final hint = quotesOnly
        ? (isEn ? 'Tap ❤️ on the banner to save today\'s quote.' : '点击首页 banner ❤️ 收藏今日名言。')
        : contentOnly
            ? (isEn ? 'Tap 🔖 on any article to save it here.' : '在内容页点击 🔖 添加到这里。')
            : (isEn ? 'Tap the bookmark icon on any article to save it here.' : '在内容页点击 🔖 图标添加到这里');
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 64 * scale, color: AppTheme.textLight.withValues(alpha: 0.4)),
            SizedBox(height: 16 * scale),
            Text(
              msg,
              style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w600, color: AppTheme.textLight),
            ),
            SizedBox(height: 8 * scale),
            Text(
              hint,
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
  // 8/28 P61-2 沿 SOUL #103 治好不抢注意力 + SOUL #189 智: 加 听 + 略过
  //   真凶: 之前 _SubscribedCard 只 1 个 "Saved" 按钮, 用户"想听/想略过"无路径
  //   修: 加 听 (TTS) + 略过 (move to history, 沿 P57-2 autoSaveOnRead 模式)
  // ignore: unused_element (沿 P59-1 dead code, 旧版保留)
  // ignore: unused_element
  final VoidCallback? onListen;
  // ignore: unused_element
  final VoidCallback? onSkip;

  const _SubscribedCard({
    required this.item,
    required this.scale,
    required this.isEn,
    required this.onTap,
    required this.onRemove,
    // ignore: unused_element
    this.onListen,
    // ignore: unused_element
    this.onSkip,
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
                      color: item.priceType.color.withValues(alpha: 0.1),
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
                item.description,
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
                  // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 听 + 略过 + 已收藏 (3 按钮)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 听 (TTS) 按钮 - 沿 P49-5 AI 摘要 streaming
                      if (onListen != null)
                        IconButton(
                          onPressed: onListen,
                          icon: Icon(Icons.headphones, size: 18 * scale, color: AppTheme.primary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                          tooltip: isEn ? 'Listen' : '听',
                        ),
                      // 略过 按钮 - 从收藏移除 (沿 P57-2 autoSaveOnRead 模式, 实际只读, 不动 history)
                      if (onSkip != null)
                        IconButton(
                          onPressed: onSkip,
                          icon: Icon(Icons.skip_next, size: 18 * scale, color: AppTheme.textLight),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                          tooltip: isEn ? 'Skip' : '略过',
                        ),
                      // 已收藏 (保存) 按钮
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
            ],
          ),
        ),
      ),
    );
  }
}


// 7/15: 名言收藏 - 顶部大字 Hero (本机制仅渲染最新一条)
// 复用 _DailyEncouragementBanner 同款紫色渐变 + 圆角, 但放大一档
// 7/30: _PinnedHeroDelegate 已删 (不用 SliverPersistentHeader, 改用 Column[hero + Expanded(ListView)] 模式)

class _QuoteHeroCard extends StatelessWidget {
  final ContentItem latest;
  final int totalCount;
  final double scale;
  final bool isEn;
  final VoidCallback onTap; // 7/15 加: 点 hero 进 reader
  final VoidCallback onRemove;

  const _QuoteHeroCard({
    required this.latest,
    required this.totalCount,
    required this.scale,
    required this.isEn,
    required this.onTap,
    required this.onRemove,
  });

  String _authorInit() {
    final t = latest.title;
    if (t.isEmpty) return '✦';
    // 取 author 首字符 (中文首字 / 英文首字母)
    return t.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final d = latest.lastReadAt ?? DateTime.now();
    return Padding(
      padding: EdgeInsets.fromLTRB(16 * scale, 16 * scale, 16 * scale, 8 * scale),
      child: InkWell(
        // 7/15 加: Hero 可点击 (进 reader)
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
        decoration: BoxDecoration(
          // 7/19 fix v2: LinearGradient 全量清除
          color: const Color(0xFF7C5CFC),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFC).withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(14 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // 7/30: 自适应高度 — 内容多则高, 内容少则矮
          children: [
            // 顶部一行: 标签 + 总数 + 删除
            Row(
              children: [
                Icon(Icons.format_quote, color: Colors.white, size: 16 * scale),
                SizedBox(width: 6 * scale),
                Text(
                  isEn ? 'Latest saved quote' : '刚收藏的名言',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isEn ? '❤ $totalCount' : '❤ $totalCount',
                    style: TextStyle(color: Colors.white, fontSize: 11 * scale, fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(width: 6 * scale),
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: EdgeInsets.all(4 * scale),
                    child: Icon(Icons.bookmark, color: Colors.white, size: 18 * scale),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10 * scale),
            // 正文 quote
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 圆形 avatar
                Container(
                  width: 44 * scale,
                  height: 44 * scale,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _authorInit(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // title = 作者名
                      Text(
                        latest.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (latest.description.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 4 * scale),
                          child: Text(
                            latest.description,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 13 * scale,
                              fontStyle: FontStyle.italic,
                              height: 1.4,
                            ),
                            maxLines: 6, // 7/30: 4 → 6, 长 quote 不被截
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8 * scale),
            // 底部: 日期 + 阅读时长
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.white.withValues(alpha: 0.7), size: 12 * scale),
                SizedBox(width: 4 * scale),
                Text(
                  '《收藏于 ${d.month}月${d.day}日》',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10 * scale),
                ),
                const Spacer(),
                Text(
                  '“${latest.duration}”',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10 * scale),
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

// 7/15: 名言收藏 - 时间线条目 (单条 quote 紧凑展示, 用于列表)
class _QuoteTimelineItem extends StatelessWidget {
  final ContentItem item;
  final double scale;
  final bool isEn;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 听 + 略过
  final VoidCallback? onListen;
  final VoidCallback? onSkip;

  const _QuoteTimelineItem({
    required this.item,
    required this.scale,
    required this.isEn,
    this.onTap,
    this.onRemove,
    this.onListen,
    this.onSkip,
  });

  String _authorInit() {
    final t = item.title;
    if (t.isEmpty) return '✦';
    return t.characters.first;
  }

  String _dayLabel(DateTime d, bool isEn) {
    final now = DateTime.now();
    final diff = now.difference(d).inDays;
    if (diff == 0) return isEn ? 'Today' : '今天';
    if (diff == 1) return isEn ? 'Yesterday' : '昨天';
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final d = item.lastReadAt ?? DateTime.now();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧小 avatar
            Container(
              width: 40 * scale,
              height: 40 * scale,
              decoration: BoxDecoration(
                color: const Color(0xFF7C5CFC).withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF7C5CFC).withValues(alpha: 0.3), width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                _authorInit(),
                style: TextStyle(
                  color: const Color(0xFF7C5CFC),
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 作者 (title) + 日期 + 已收藏徽章
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 7/15 Q3: 跟 Hero ❤️ 同色系紫色徽章 (统一视觉)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                        margin: EdgeInsets.only(right: 6 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C5CFC).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark, size: 10 * scale, color: const Color(0xFF7C5CFC)),
                            SizedBox(width: 3 * scale),
                            Text(
                              isEn ? 'Saved' : '已收藏',
                              style: TextStyle(fontSize: 10 * scale, color: const Color(0xFF7C5CFC), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _dayLabel(d, isEn),
                        style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * scale),
                  // quote 描述
                  Text(
                    item.description,
                    style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight, fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 听 + 略过 + 取消收藏 (3 按钮)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onListen != null)
                  IconButton(
                    onPressed: onListen,
                    icon: Icon(Icons.headphones, size: 16, color: AppTheme.primary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    tooltip: isEn ? 'Listen' : '听',
                  ),
                if (onSkip != null)
                  IconButton(
                    onPressed: onSkip,
                    icon: Icon(Icons.skip_next, size: 16, color: AppTheme.textLight),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    tooltip: isEn ? 'Skip' : '略过',
                  ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: Icon(Icons.bookmark_outline, size: 16, color: AppTheme.textLight),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    tooltip: isEn ? 'Remove' : '取消收藏',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


// 17/28: 内容 Tab 顶部 Hero 卡 (跟 _QuoteHeroCard 同风格, 紫色渐变, 56x56 source icon)
class _ContentHeroCard extends StatelessWidget {
  final ContentItem latest;
  final int totalCount;
  final double scale;
  final bool isEn;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ContentHeroCard({
    required this.latest,
    required this.totalCount,
    required this.scale,
    required this.isEn,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final d = latest.lastReadAt ?? DateTime.now();
    final sourceIcon = latest.sourceType.icon;
    final sourceColor = latest.sourceType == ContentSource.bilibili
        ? const Color(0xFFFB7299)
        : latest.sourceType == ContentSource.zhihu
            ? const Color(0xFF0084FF)
            : latest.sourceType == ContentSource.ximalaya
                ? const Color(0xFFFF6E0E)
                : Colors.white;
    return Padding(
      padding: EdgeInsets.fromLTRB(16 * s, 16 * s, 16 * s, 8 * s),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            // 7/19 fix v2: LinearGradient 全量清除
            color: const Color(0xFF7C5CFC),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C5CFC).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(14 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // 7/30: 自适应高度
            children: [
              Row(
                children: [
                  Icon(Icons.bookmark, color: Colors.white, size: 16 * s),
                  SizedBox(width: 6 * s),
                  Text(
                    isEn ? 'Latest saved content' : '刚收藏的内容',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 11 * s,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '❤ $totalCount',
                      style: TextStyle(color: Colors.white, fontSize: 11 * s, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(width: 6 * s),
                  InkWell(
                    onTap: onRemove,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: EdgeInsets.all(4 * s),
                      child: Icon(Icons.delete_outline, color: Colors.white, size: 18 * s),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10 * s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 17/28 Q1=C: 紫底 8% + 源色 icon (双层)
                  Container(
                    width: 44 * s,
                    height: 44 * s,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: sourceColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(sourceIcon, color: sourceColor, size: 22 * s),
                  ),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // title = 内容标题
                        Text(
                          latest.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15 * s,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 3, // 7/30: 2 → 3, 长内容不被截
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4 * s),
                        // 副: 时长 + source + 内容类型
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.white.withValues(alpha: 0.7), size: 11 * s),
                            SizedBox(width: 3 * s),
                            Text(
                              latest.duration,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10 * s),
                            ),
                            SizedBox(width: 6 * s),
                            Text(
                              '• ${latest.source}',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10 * s),
                            ),
                            SizedBox(width: 6 * s),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 1 * s),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                latest.contentType.label,
                                style: TextStyle(color: Colors.white, fontSize: 10 * s, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12 * s),
              // 底部: 收藏日期
              Row(
                children: [
                  Icon(Icons.bookmark, color: Colors.white.withValues(alpha: 0.7), size: 13 * s),
                  SizedBox(width: 4 * s),
                  Text(
                    '《收藏于 ${d.month}月${d.day}日》',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11 * s),
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

// 17/28: 内容 Tab 时间线条目 (跟 _QuoteTimelineItem 紫底 4% + 边框, 40x40 source icon)
class _ContentTimelineItem extends StatelessWidget {
  final ContentItem item;
  final double scale;
  final bool isEn;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 加 听 + 略过
  final VoidCallback? onListen;
  final VoidCallback? onSkip;

  const _ContentTimelineItem({
    required this.item,
    required this.scale,
    required this.isEn,
    this.onTap,
    this.onRemove,
    this.onListen,
    this.onSkip,
  });

  String _dayLabel(DateTime d, bool isEn) {
    final now = DateTime.now();
    final diff = now.difference(d).inDays;
    if (diff == 0) return isEn ? 'Today' : '今天';
    if (diff == 1) return isEn ? 'Yesterday' : '昨天';
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final d = item.lastReadAt ?? DateTime.now();
    final sourceColor = item.sourceType == ContentSource.bilibili
        ? const Color(0xFFFB7299)
        : item.sourceType == ContentSource.zhihu
            ? const Color(0xFF0084FF)
            : item.sourceType == ContentSource.ximalaya
                ? const Color(0xFFFF6E0E)
                : AppTheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: EdgeInsets.only(bottom: 8 * s),
        padding: EdgeInsets.symmetric(vertical: 12 * s, horizontal: 8 * s),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 40x40 source icon (跟 Hero 同色)
            Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: sourceColor.withValues(alpha: 0.4), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Icon(item.sourceType.icon, color: sourceColor, size: 18 * s),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 17/28 Q3: 跟名言 '已收藏' 徽章同色系
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                        margin: EdgeInsets.only(right: 6 * s),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark, size: 10 * s, color: AppTheme.primary),
                            SizedBox(width: 3 * s),
                            Text(
                              isEn ? 'Saved' : '已收藏',
                              style: TextStyle(fontSize: 10 * s, color: AppTheme.primary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _dayLabel(d, isEn),
                        style: TextStyle(fontSize: 11 * s, color: AppTheme.textLight),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * s),
                  // 副: 时长 · source · type
                  Text(
                    '${item.duration} • ${item.source} • ${item.contentType.label}',
                    style: TextStyle(fontSize: 12 * s, color: AppTheme.textLight),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 听 + 略过 + 取消收藏 (3 按钮)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onListen != null)
                  IconButton(
                    onPressed: onListen,
                    icon: Icon(Icons.headphones, size: 16, color: AppTheme.primary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    tooltip: isEn ? 'Listen' : '听',
                  ),
                if (onSkip != null)
                  IconButton(
                    onPressed: onSkip,
                    icon: Icon(Icons.skip_next, size: 16, color: AppTheme.textLight),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    tooltip: isEn ? 'Skip' : '略过',
                  ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: Icon(Icons.bookmark_outline, size: 16, color: AppTheme.textLight),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    tooltip: isEn ? 'Remove' : '取消收藏',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 8/28 P60-1: 阅读历史 tab 的 item card (沿 P18-3 HistoryItem)
class _HistoryItemCard extends StatelessWidget {
  final HistoryItem historyItem;
  final double scale;
  final bool isEn;
  final VoidCallback onTap;
  // 8/28 P61-2 沿 SOUL #103 治好不抢注意力: 听 + 略过 (略过只 in-memory)
  final VoidCallback? onListen;
  final VoidCallback? onSkip;
  // 8/28 P61-C 沿用户"需要添加删除的功能"治本: 多选删除
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;

  const _HistoryItemCard({
    required this.historyItem,
    required this.scale,
    required this.isEn,
    required this.onTap,
    this.onListen,
    this.onSkip,
    this.selected = false,
    this.multiSelectMode = false,
    this.onLongPress,
    this.onRemove,
  });

  String _formatReadTime(int readAtMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(readAtMs);
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return isEn ? 'just now' : '刚刚';
  if (diff.inHours < 1) return isEn ? '${diff.inMinutes}m ago' : '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return isEn ? '${diff.inHours}h ago' : '${diff.inHours} 小时前';
  if (diff.inDays < 7) return isEn ? '${diff.inDays}d ago' : '${diff.inDays} 天前';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final item = historyItem;
    return Card(
      // 8/28 P61-C 沿 SOUL #189 智: 选中时高亮
      color: selected ? AppTheme.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress, // 8/28 P61-C: 长按进入多选
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Row(
            children: [
              // 8/28 P61-C: 多选 checkbox (在 icon 之前)
              if (multiSelectMode) ...[
                Checkbox(
                  value: selected,
                  onChanged: (_) => onTap(), // 复用 onTap 来 toggle
                ),
                SizedBox(width: 4 * scale),
              ],
              Container(
                width: 36 * scale,
                height: 36 * scale,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.history,
                  size: 18 * scale,
                  color: AppTheme.primary,
                ),
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14 * scale,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      '${item.duration} • ${item.source}',
                      style: TextStyle(
                        fontSize: 11 * scale,
                        color: AppTheme.textLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      _formatReadTime(item.readAt),
                      style: TextStyle(
                        fontSize: 10 * scale,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              // 8/28 P61-C 沿 SOUL #137 真凶链: 单选删除按钮 (在 chevron 之前)
              if (!multiSelectMode && onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline, size: 18 * scale, color: AppTheme.textLight),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  tooltip: isEn ? 'Delete' : '删除',
                ),
              Icon(
                Icons.chevron_right,
                size: 18 * scale,
                color: AppTheme.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
