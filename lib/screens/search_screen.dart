import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/content_aggregator.dart';
import '../services/local_subscription_service.dart';
import '../services/analytics_service.dart';
import '../widgets/skeleton.dart';
import 'content_reader_screen.dart';

class SearchScreen extends StatefulWidget {
  final bool isElderlyMode;
  final String languageCode;
  final bool isInternational;

  const SearchScreen({
    super.key,
    this.isElderlyMode = false,
    this.languageCode = 'zh',
    this.isInternational = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ContentAggregator _aggregator = ContentAggregator();
  final TextEditingController _controller = TextEditingController();
  List<ContentItem> _results = [];
  bool _isLoading = false;
  // 6/11 加: 搜索历史
  List<String> _history = [];
  static const _historyKey = 'search_history_v1';
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _history = prefs.getStringList(_historyKey) ?? []);
    }
  }

  Future<void> _saveHistory(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    list.remove(query); // 去重
    list.insert(0, query); // 最新在前
    if (list.length > 10) list.removeRange(10, list.length);
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) setState(() => _history = []);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String query) async {
    _lastQuery = query;
    if (query.trim().isNotEmpty) {
      // 6/8 埋点
      AnalyticsService.instance.track(
        AnalyticsService.EVT_SEARCH,
        props: {'q': query},
      );
      await _saveHistory(query); // 6/11 加: 记历史
    }
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await _aggregator.searchContent(query, isInternational: widget.isInternational);
      if (mounted && _lastQuery == query) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
    final isEn = widget.languageCode == 'en';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEn ? 'Search' : '搜索',
                style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4 * scale),
              Text(
                isEn ? 'Find content across all sources' : '在所有内容源中搜索',
                style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
              ),
              SizedBox(height: 16 * scale),
              TextField(
                controller: _controller,
                onSubmitted: _doSearch,
                onChanged: (v) {
                  if (v.isEmpty) setState(() => _results = []);
                },
                style: TextStyle(fontSize: 15 * scale),
                decoration: InputDecoration(
                  hintText: isEn ? 'Type to search...' : '输入关键词搜索...',
                  prefixIcon: Icon(Icons.search, size: 20 * scale),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 20 * scale),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _results = []);
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12 * scale,
                    vertical: 12 * scale,
                  ),
                ),
              ),
              SizedBox(height: 8 * scale),
              if (_isLoading)
                // 6/23: 骨架屏替换 loading 圈
                ListView.builder(
                  padding: EdgeInsets.all(16 * scale),
                  itemCount: 4,
                  itemBuilder: (_, __) => Padding(
                    padding: EdgeInsets.only(bottom: 10 * scale),
                    child: const ListItemSkeleton(),
                  ),
                )
              else if (_lastQuery.isNotEmpty && _results.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24 * scale),
                  child: Column(
                    children: [
                      Center(
                        child: Text(
                          isEn
                              ? '🕵️ No results for "$_lastQuery"'
                              : '🕵️ 没找到 "$_lastQuery" 的结果',
                          style: TextStyle(fontSize: 14 * scale, color: AppTheme.textLight),
                        ),
                      ),
                      SizedBox(height: 16 * scale),
                      Text(isEn ? 'Try these instead:' : '试试这些：',
                          style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight)),
                      SizedBox(height: 8 * scale),
                      Wrap(
                        spacing: 6 * scale,
                        runSpacing: 6 * scale,
                        alignment: WrapAlignment.center,
                        children: (isEn
                                ? ['AI', 'productivity', 'health', 'business', 'study']
                                : ['AI', '效率', '健康', '商业', '学习'])
                            .map((s) => ActionChip(
                                  label: Text(s, style: TextStyle(fontSize: 12 * scale)),
                                  onPressed: () {
                                    _controller.text = s;
                                    _doSearch(s);
                                  },
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                )
              else if (_results.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4 * scale),
                  child: Text(
                    isEn
                        ? '${_results.length} result(s)'
                        : '共 ${_results.length} 条结果',
                    style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight),
                  ),
                ),
              Expanded(
                child: _results.isEmpty && _lastQuery.isEmpty
                    ? _buildSuggestions(isEn, scale)
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          return _buildResultCard(item, isEn, scale);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions(bool isEn, double scale) {
    final suggestions = isEn
        ? ['AI', 'Flutter', 'productivity', 'health', 'business']
        : ['AI', 'Flutter', '效率', '健康', '商业'];
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 48 * scale, color: AppTheme.textLight.withOpacity(0.3)),
          SizedBox(height: 12 * scale),
          // 6/11 加: 搜索历史 (不是 Center, 让顶部有间距)
          if (_history.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(isEn ? 'Recent searches:' : '最近搜索：',
                    style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight)),
                TextButton(
                  onPressed: _clearHistory,
                  child: Text(isEn ? 'Clear' : '清空', style: TextStyle(fontSize: 11 * scale)),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: Wrap(
                spacing: 6 * scale,
                runSpacing: 6 * scale,
                alignment: WrapAlignment.center,
                children: _history
                    .map((h) => InputChip(
                          avatar: Icon(Icons.history, size: 14 * scale, color: AppTheme.textLight),
                          label: Text(h, style: TextStyle(fontSize: 12 * scale)),
                          onPressed: () {
                            _controller.text = h;
                            _doSearch(h);
                          },
                        ))
                    .toList(),
              ),
            ),
            SizedBox(height: 16 * scale),
          ],
          Text(
            isEn ? 'Try searching for:' : '试试搜索：',
            style: TextStyle(fontSize: 14 * scale, color: AppTheme.textLight),
          ),
          SizedBox(height: 12 * scale),
          Wrap(
            spacing: 8 * scale,
            runSpacing: 8 * scale,
            alignment: WrapAlignment.center,
            children: suggestions
                .map((s) => ActionChip(
                      label: Text(s, style: TextStyle(fontSize: 13 * scale)),
                      onPressed: () {
                        _controller.text = s;
                        _doSearch(s);
                      },
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ContentItem item, bool isEn, double scale) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4 * scale),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
        child: Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: item.priceType.color.withOpacity(0.1),
                child: Icon(
                  item.contentType.icon,
                  size: 20 * scale,
                  color: AppTheme.primary,
                ),
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
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_outline, size: 20),
                tooltip: isEn ? 'Subscribe' : '订阅',
                onPressed: () async {
                  await LocalSubscriptionService.instance.subscribe(item);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isEn ? 'Added to Saved' : '已收藏')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
