import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // 7/15 17:19: 透传给 ContentReaderScreen (含 quote Hero 卡, 关联阅读用)
  final UserType? userType;
  final Scene? scene;

  const MySubscriptionsScreen({
    super.key,
    this.isElderlyMode = false,
    this.isEn = false,
    this.userType,
    this.scene,
  });

  // 6/24 v8: GlobalKey 让详情页订阅后能 reload
  static final reloadKey = GlobalKey<_MySubscriptionsScreenState>();

  @override
  State<MySubscriptionsScreen> createState() => _MySubscriptionsScreenState();
}

class _MySubscriptionsScreenState extends State<MySubscriptionsScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final LocalSubscriptionService _subService = LocalSubscriptionService.instance;
  List<ContentItem> _items = [];
  bool _loading = true;
  int _followingPlatforms = 0;
  int _followingCategories = 0;
  String _handle = '@你'; // 6/25 昵称扩展: 顶部显示
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
    _tabController = TabController(length: 3, vsync: this);
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
      } catch (_) {}
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textLight,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelStyle: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600),
          tabs: [
            Tab(icon: Icon(Icons.article_outlined, size: 18 * scale), text: isEn ? 'Articles' : '内容'),
            Tab(icon: Icon(Icons.format_quote, size: 18 * scale), text: isEn ? 'Quotes' : '名言'),
            Tab(icon: Icon(Icons.subscriptions, size: 18 * scale), text: isEn ? 'Following' : '关注'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 7/20 16:48 Brien 反馈 "收藏内容多了, 让用户搜搜" → 加搜索框 (跨 3 个子 Tab 共享)
          _buildSearchBar(scale, isEn),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: 内容收藏
                _buildSavedTab(scale, isEn, contentOnly: true),
                // Tab 2: 名言收藏
                _buildSavedTab(scale, isEn, quotesOnly: true),
                // Tab 3: 关注管理 (跳转)
                _buildFollowingTab(scale, isEn),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  // 7/20 16:48 Brien 反馈 "收藏内容多了, 让用户搜搜" → 加搜索框
  // 7/20 18:42 Brien "每个子 Tab 有专属 hint" → 根据 _tabController.index 切 hint
  String _hintForCurrentTab(bool isEn) {
    // _tabController.index: 0=内容 1=名言 2=关注
    switch (_tabController.index) {
      case 0:
        return isEn ? 'Search saved articles...' : '搜收藏的内容...';
      case 1:
        return isEn ? 'Search saved quotes...' : '搜收藏的名言...';
      case 2:
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
        color: Colors.white.withOpacity(0.85),
        border: Border(bottom: BorderSide(color: AppTheme.textLight.withOpacity(0.15), width: 0.5)),
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
          fillColor: AppTheme.textLight.withOpacity(0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // 6/25 A: 收藏 Tab (内容 / 名言)
  // 7/15: quotesOnly 走 _buildQuotesView (顶部大字 quote + time-grouped 列表)
  // 7/20 16:48: _searchQuery 跨 3 个子 Tab 共享, 内容/名言子 Tab 过滤
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
  Widget _buildQuotesView(List<ContentItem> quotes, double scale, bool isEn) {
    return CustomScrollView(
      slivers: [
        // 顶部大卡 (块 1: 最新一条 quote hero 展示)
        SliverToBoxAdapter(
          child: _QuoteHeroCard(
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
          ),
        ),
        if (quotes.length > 1) SliverToBoxAdapter(child: SizedBox(height: 24 * scale)),
        // 块 2: 按天分组的时间线 (lastReadAt 同一天合并)
        if (quotes.length > 1)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 16 * scale),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
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
                    onRemove: () => _unsubscribe(item),
                  );
                },
                childCount: quotes.length - 1,
              ),
            ),
          ),
      ],
    );
  }

  // 17:28: 内容 Tab Hero+Timeline 视图 (跟名言 tab 风格统一)
  Widget _buildContentView(List<ContentItem> items, double scale, bool isEn) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _ContentHeroCard(
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
          ),
        ),
        if (items.length > 1) SliverToBoxAdapter(child: SizedBox(height: 24 * scale)),
        if (items.length > 1)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 16 * scale),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ContentTimelineItem(
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
                  onRemove: () => _unsubscribe(items[i + 1]),
                ),
                childCount: items.length - 1,
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
            return ListView(
              padding: EdgeInsets.fromLTRB(16 * scale, 16 * scale, 16 * scale, 32 * scale),
              children: [
                // 17:45 方案 A: Hero 统计
                _FollowingHeroCard(
                  platformCount: sources.length,
                  categoryCount: categories.length,
                  scale: scale,
                  isEn: isEn,
                  onManage: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                    );
                  },
                ),
                SizedBox(height: 16 * scale),
                if (sources.isNotEmpty) ...[
                  _FollowingSectionHeader(
                    label: isEn
                        ? 'PLATFORMS (\${sources.length})'
                        : '关注平台 (\${sources.length})',
                    icon: Icons.subscriptions,
                    scale: scale,
                  ),
                  SizedBox(height: 12 * scale),
                  ...sources.map<Widget>((s) => _FollowingSourceRow(
                        source: s,
                        isEn: isEn,
                        scale: scale,
                        onRemove: () async {
                          // ignore: use_build_context_synchronously
                          await SubscriptionService.instance.unsubscribeSource(s);
                          // 强制刷新: pop+push 重建 tab
                          (context as Element).markNeedsBuild();
                        },
                      )),
                  SizedBox(height: 20 * scale),
                ],
                if (categories.isNotEmpty) ...[
                  _FollowingSectionHeader(
                    label: isEn
                        ? 'CATEGORIES (\${categories.length})'
                        : '关注类目 (\${categories.length})',
                    icon: Icons.category_outlined,
                    scale: scale,
                  ),
                  SizedBox(height: 12 * scale),
                  ...categories.map<Widget>((c) => _FollowingCategoryRow(
                        categoryName: c,
                        isEn: isEn,
                        scale: scale,
                        onRemove: () async {
                          // ignore: use_build_context_synchronously
                          await SubscriptionService.instance.unsubscribeCategory(c);
                          (context as Element).markNeedsBuild();
                        },
                      )),
                ],
              ],
            );
          },
        );
  }

  // 17:45: 关注 Tab 顶部 Hero 统计 (紫色 24 圆角, 56x56 avatar + 数字 + 管理按钮)
  Widget _FollowingHeroCard({
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
            color: const Color(0xFF7C5CFC).withOpacity(0.25),
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
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
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
                    color: Colors.white.withOpacity(0.92),
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
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13 * s),
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
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13 * s),
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
  Widget _FollowingSectionHeader({required String label, required IconData icon, required double scale}) {
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

  // 17:45: 关注 Tab 平台行 (跟内容 Timeline 同款 紫 4% 底 + 12% 边框)
  Widget _FollowingSourceRow({
    required dynamic source,
    required bool isEn,
    required double scale,
    required VoidCallback onRemove,
  }) {
    final s = scale;
    final sourceObj = source as ContentSource;
    final name = isEn ? sourceObj.name : _sourceNameZh(sourceObj);
    final sourceColor = sourceObj == ContentSource.bilibili
        ? const Color(0xFFFB7299)
        : sourceObj == ContentSource.zhihu
            ? const Color(0xFF0084FF)
            : sourceObj == ContentSource.ximalaya
                ? const Color(0xFFFF6E0E)
                : AppTheme.primary;

    return Container(
      margin: EdgeInsets.only(bottom: 8 * s),
      padding: EdgeInsets.symmetric(vertical: 12 * s, horizontal: 8 * s),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40 * s,
            height: 40 * s,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: sourceColor.withOpacity(0.4), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(sourceObj.icon, color: sourceColor, size: 18 * s),
          ),
          SizedBox(width: 12 * s),
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close, size: 18, color: AppTheme.textLight),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            tooltip: isEn ? 'Unsubscribe' : '取消关注',
          ),
        ],
      ),
    );
  }

  // 17:45: 关注 Tab 类目行 (同款 紫 4% 底)
  Widget _FollowingCategoryRow({
    required String categoryName,
    required bool isEn,
    required double scale,
    required VoidCallback onRemove,
  }) {
    final s = scale;
    return Container(
      margin: EdgeInsets.only(bottom: 8 * s),
      padding: EdgeInsets.symmetric(vertical: 12 * s, horizontal: 8 * s),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40 * s,
            height: 40 * s,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.local_offer, color: AppTheme.primary, size: 18 * s),
          ),
          SizedBox(width: 12 * s),
          Expanded(
            child: Text(
              categoryName,
              style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close, size: 18, color: AppTheme.textLight),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            tooltip: isEn ? 'Unsubscribe' : '取消关注',
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingEmpty(BuildContext context, double scale, bool isEn) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subscriptions_outlined, size: 80 * scale, color: AppTheme.textLight.withOpacity(0.4)),
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
  Widget _buildFollowingSectionHeader(String label, IconData icon, double scale) {
    return Row(
      children: [
        Icon(icon, size: 14 * scale, color: AppTheme.primary),
        SizedBox(width: 6 * scale),
        Text(
          label,
          style: TextStyle(
            fontSize: 12 * scale,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // 6/25 A: ContentSource enum 转中文
  String _sourceNameZh(ContentSource s) {
    switch (s) {
      case ContentSource.ximalaya: return '喜马拉雅';
      case ContentSource.news36kr: return '36氪';
      case ContentSource.bilibili: return 'B站';
      case ContentSource.youtube: return 'YouTube';
      case ContentSource.rss: return 'RSS';
      case ContentSource.applePodcasts: return 'Apple Podcasts';
      case ContentSource.lizhiFM: return '荔枝FM';
      case ContentSource.zhihu: return '知乎';
      case ContentSource.spotify: return 'Spotify';
    }
  }

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
            Icon(Icons.search_off, size: 48 * scale, color: AppTheme.textLight.withOpacity(0.5)),
            SizedBox(height: 12 * scale),
            Text(
              isEn ? 'No matches for "${_searchQuery}"' : '没找到包含 "${_searchQuery}" 的收藏',
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
            Icon(Icons.bookmark_border, size: 64 * scale, color: AppTheme.textLight.withOpacity(0.4)),
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


// 7/15: 名言收藏 - 顶部大字 Hero (本机制仅渲染最新一条)
// 复用 _DailyEncouragementBanner 同款紫色渐变 + 圆角, 但放大一档
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
              color: const Color(0xFF7C5CFC).withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(20 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部一行: 标签 + 总数 + 删除
            Row(
              children: [
                Icon(Icons.format_quote, color: Colors.white, size: 18 * scale),
                SizedBox(width: 6 * scale),
                Text(
                  isEn ? 'Latest saved quote' : '刚收藏的名言',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
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
            SizedBox(height: 16 * scale),
            // 正文 quote
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 圆形 avatar
                Container(
                  width: 56 * scale,
                  height: 56 * scale,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _authorInit(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22 * scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: 14 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // title = 作者名
                      Text(
                        latest.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (latest.description != null && latest.description!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 6 * scale),
                          child: Text(
                            latest.description!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 14 * scale,
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12 * scale),
            // 底部: 日期 + 阅读时长
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.white.withOpacity(0.7), size: 13 * scale),
                SizedBox(width: 4 * scale),
                Text(
                  '《收藏于 ${d.month}月${d.day}日》',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11 * scale),
                ),
                const Spacer(),
                Text(
                  '“${latest.duration}”',
                  style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11 * scale),
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

  const _QuoteTimelineItem({
    required this.item,
    required this.scale,
    required this.isEn,
    this.onTap,
    this.onRemove,
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
                color: const Color(0xFF7C5CFC).withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF7C5CFC).withOpacity(0.3), width: 1),
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
                          color: const Color(0xFF7C5CFC).withOpacity(0.12),
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
                    item.description ?? '',
                    style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight, fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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
                color: const Color(0xFF7C5CFC).withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(20 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bookmark, color: Colors.white, size: 18 * s),
                  SizedBox(width: 6 * s),
                  Text(
                    isEn ? 'Latest saved content' : '刚收藏的内容',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
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
              SizedBox(height: 16 * s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 17/28 Q1=C: 紫底 8% + 源色 icon (双层)
                  Container(
                    width: 56 * s,
                    height: 56 * s,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: sourceColor.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(sourceIcon, color: sourceColor, size: 26 * s),
                  ),
                  SizedBox(width: 14 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // title = 内容标题
                        Text(
                          latest.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16 * s,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 6 * s),
                        // 副: 时长 + source + 内容类型
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.white.withOpacity(0.7), size: 12 * s),
                            SizedBox(width: 3 * s),
                            Text(
                              latest.duration,
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11 * s),
                            ),
                            SizedBox(width: 8 * s),
                            Text(
                              '• ${latest.source}',
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11 * s),
                            ),
                            SizedBox(width: 8 * s),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 1 * s),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
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
                  Icon(Icons.bookmark, color: Colors.white.withOpacity(0.7), size: 13 * s),
                  SizedBox(width: 4 * s),
                  Text(
                    '《收藏于 ${d.month}月${d.day}日》',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11 * s),
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

  const _ContentTimelineItem({
    required this.item,
    required this.scale,
    required this.isEn,
    this.onTap,
    this.onRemove,
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
          color: AppTheme.primary.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withOpacity(0.12)),
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
                border: Border.all(color: sourceColor.withOpacity(0.4), width: 1.5),
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
                          color: AppTheme.primary.withOpacity(0.12),
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
      ),
    );
  }
}
