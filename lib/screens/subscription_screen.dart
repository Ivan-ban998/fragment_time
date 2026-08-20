import 'package:flutter/material.dart';
import '../theme/glass_decoration.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/subscription_service.dart';
import '../widgets/skeleton.dart';
import 'content_reader_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  final bool isEn;
  const SubscriptionScreen({super.key, this.isEn = false});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final SubscriptionService _service = SubscriptionService.instance;

  Set<ContentSource> _selectedSources = {};
  Set<String> _selectedCategories = {};
  List<ContentItem> _previewItems = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources = await _service.getSubscribedSources();
    final categories = await _service.getSubscribedCategories();
    final preview = await _service.fetchSubscribedContent();
    if (!mounted) return;
    setState(() {
      _selectedSources = sources;
      _selectedCategories = categories;
      _previewItems = preview;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // 已通过 _service.subscribe/unsubscribe 实时持久化，这里只触发 UI 反馈
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _saving = false);
    _showFloatingSnack(context, widget.isEn ? 'Saved' : '已保存');
  }

  Future<void> _toggleSource(ContentSource source) async {
    if (_selectedSources.contains(source)) {
      await _service.unsubscribeSource(source);
    } else {
      await _service.subscribeSource(source);
    }
    if (!mounted) return;
    setState(() {
      if (_selectedSources.contains(source)) {
        _selectedSources.remove(source);
      } else {
        _selectedSources.add(source);
      }
    });
  }

  Future<void> _toggleCategory(String category) async {
    if (_selectedCategories.contains(category)) {
      await _service.unsubscribeCategory(category);
    } else {
      await _service.subscribeCategory(category);
    }
    if (!mounted) return;
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEn = widget.isEn;
    final allCategories = SubscriptionService.getAllCategories(isEn: isEn);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(isEn ? 'Manage Following' : '关注管理'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '...' : (isEn ? 'Save' : '保存')),
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
          // 7/30: 拆 Column[钉住(管理区) + Expanded(预览列表)]
          // — Platforms / Categories / Stats 不滚, 预览标题 + 列表可独立滚
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isEn
                                    ? 'Follow platforms and topics you care about — your feed will be tailored.'
                                    : '订阅你感兴趣的内容，每次打开只看你想看的',
                                style: const TextStyle(color: AppTheme.primary, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isEn ? 'Platforms' : '内容来源',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEn ? 'Tap to toggle subscriptions' : '点击切换订阅',
                        style: TextStyle(color: AppTheme.textLight, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: SubscriptionService.allSources
                            .map((source) => _buildSourceChip(source, _selectedSources.contains(source), isEn))
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      // 7/30: + 自定义 RSS 入口 (沿用 #103 #117 不接真 RSS, 仅存 URL+名字, 后续拉取接入)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _showAddCustomRssDialog(context, isEn),
                          icon: const Icon(Icons.add_link, size: 18),
                          label: Text(isEn ? 'Add custom RSS feed' : '+ 自定义 RSS 地址'),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isEn ? 'Categories' : '内容类目',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEn ? 'Narrow down by topics' : '精准订阅你感兴趣的细分领域',
                        style: TextStyle(color: AppTheme.textLight, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allCategories
                            .map((cat) => _buildCategoryChip(cat, _selectedCategories.contains(cat)))
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      // 7/30: + 新建类目 入口 (仅需 subscribeCategory 存一下)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _showAddCustomCategoryDialog(context, isEn),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(isEn ? 'Add custom category' : '+ 新建类目'),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStat(
                                isEn ? 'Platforms' : '已订来源',
                                '${_selectedSources.length}',
                              ),
                              Container(width: 1, height: 40, color: Colors.grey[300]),
                              _buildStat(
                                isEn ? 'Categories' : '已订类目',
                                '${_selectedCategories.length}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 7/30: “订阅内容预览” 标题钉住 (单独 row, 不滚)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.preview_outlined, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        isEn ? 'Preview of your feed' : '订阅内容预览',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                // 预览列表独立滚 (7/30 修: 不再嵌 _buildSubscribedContent — 避免双 Expanded 拿 0 空间)
                if (_previewItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isEn
                            ? 'No content yet. Select at least one platform above.'
                            : '还没有内容。请至少选择一个平台。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textLight, fontSize: 12),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            isEn
                                ? 'Showing first 5 items from your selected platforms'
                                : '从你选择的平台展示前 5 条',
                            style: TextStyle(color: AppTheme.textLight, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            itemCount: _previewItems.length > 5 ? 5 : _previewItems.length,
                            itemBuilder: (context, i) => _buildPreviewCard(_previewItems[i], isEn),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Center(
                    child: Text(
                      isEn
                          ? 'Your follows are saved. The "Saved" tab shows your bookmarks, separate from this.'
                          : '你的关注已自动保存。"收藏" 标签是你的书签（独立的）。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textLight, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPreviewCard(ContentItem item, bool isEn) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        // 6/10 修：预览卡片加 onTap - 6/9 遗漏, 点不开
        onTap: () {
          if (item.contentType == ContentType.video && item.externalUrl != null && !kIsWeb) {
            // mobile 视频跳原站
            launchUrl(Uri.parse(item.externalUrl!), mode: LaunchMode.externalApplication);
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContentReaderScreen(item: item, isEn: isEn),
            ),
          );
        },
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(item.contentType.icon, size: 22, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.source} · ${item.duration}',
                    style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: item.priceType.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.priceType.label,
                style: TextStyle(fontSize: 10, color: item.priceType.color),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSourceChip(ContentSource source, bool isSelected, bool isEn) {
    return GestureDetector(
      onTap: () => _toggleSource(source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              source.icon,
              size: 14,
              color: isSelected ? Colors.white : AppTheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              source.name,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textDark,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleCategory(category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : Colors.grey[300]!),
        ),
        child: Text(
          category,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textDark,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary)),
        Text(label, style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
      ],
    );
  }

  // 7/30: + 自定义 RSS 对话框 — 名字 + URL (存 prefs, 后续拉取接入)
  void _showAddCustomRssDialog(BuildContext context, bool isEn) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Add RSS feed' : '添加 RSS 订阅'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: isEn ? 'Name (e.g. Tech News)' : '名称 (例: 科技早知道)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                labelText: isEn ? 'RSS URL (https://...)' : 'RSS URL (https://...)',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'Cancel' : '取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              final messenger = ScaffoldMessenger.of(ctx);
              if (name.isEmpty || url.isEmpty) {
                messenger.showSnackBar(SnackBar(content: Text(isEn ? 'Both required' : '名称和 URL 都需要填')));
                return;
              }
              if (!url.startsWith('http')) {
                messenger.showSnackBar(SnackBar(content: Text(isEn ? 'URL must start with http(s)' : 'URL 必须以 http 开头')));
                return;
              }
              await SubscriptionService.instance.addCustomRss(name, url);
              if (ctx.mounted) Navigator.pop(ctx);
              messenger.showSnackBar(SnackBar(content: Text(isEn ? 'RSS added' : 'RSS 已添加')));
            },
            child: Text(isEn ? 'Add' : '添加'),
          ),
        ],
      ),
    );
  }

  // 7/30: + 新建类目 对话框 — 名字 (直接 subscribeCategory)
  void _showAddCustomCategoryDialog(BuildContext context, bool isEn) {
    final catCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'New category' : '新建类目'),
        content: TextField(
          controller: catCtrl,
          decoration: InputDecoration(
            labelText: isEn ? 'Category name' : '类目名 (例: 摄影技巧)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'Cancel' : '取消'),
          ),
          FilledButton(
            onPressed: () async {
              final cat = catCtrl.text.trim();
              final messenger = ScaffoldMessenger.of(ctx);
              if (cat.isEmpty) {
                messenger.showSnackBar(SnackBar(content: Text(isEn ? 'Name required' : '名称不能为空')));
                return;
              }
              await SubscriptionService.instance.subscribeCategory(cat);
              if (ctx.mounted) Navigator.pop(ctx);
              messenger.showSnackBar(SnackBar(content: Text(isEn ? 'Category added' : '类目已添加')));
            },
            child: Text(isEn ? 'Add' : '添加'),
          ),
        ],
      ),
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
      duration: const Duration(seconds: 2),
    ),
  );
}
