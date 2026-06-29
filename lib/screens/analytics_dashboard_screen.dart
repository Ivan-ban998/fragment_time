// lib/screens/analytics_dashboard_screen.dart
// 6/8 自用看板
// 入口：设置页底部"📊 数据看板（自用）"按钮
// 展示：app 打开数 / 6 userType 偏好 / 4 scene 偏好 / 24 桶组合 top8 / TTS/视频点击 / 搜索词

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/analytics_service.dart';
import '../services/motivation_service.dart';
import '../services/llm_service.dart';
import '../services/weekly_recap_service.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _aiRecap; // 6/11 加: AI 私教回顾文本
  bool _aiRecapLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AnalyticsService.instance.summary();
    if (!mounted) return;
    setState(() {
      _summary = s;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空所有事件？'),
        content: const Text('重置本地统计（不影响主功能）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AnalyticsService.instance.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('📊 数据看板（自用）')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final s = _summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 数据看板（自用）'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _clear, tooltip: '清空'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stat('总事件数', '${s['totalEvents']}'),
          _stat('App 打开 (24h / 7d / 总)',
              '${s['appOpens1d']} / ${s['appOpens7d']} / ${s['appOpens']}'),
          _stat('TTS 播放', '${s['ttsPlays']}'),
          _stat('视频内嵌播放', '${s['videoPlays']}'),
          _stat('视频跳原站', '${s['videoExtClicks']}'),
          _stat('搜索次数', '${s['searches']}'),
          _stat('历史单条删除', '${s['historyDeletes']}'),
          // 6/10 加: 过去 56 天热力图 + 本周回顾
          const Divider(height: 32),
          _section('过去 56 天活跃热力图（GitHub 风格）'),
          _buildHeatmap(),
          const SizedBox(height: 16),
          _section('本周回顾'),
          _buildWeeklyRecap(),
          const SizedBox(height: 8),
          // 6/11 加: AI 私教回顾按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _generateAiRecap(context),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('生成 AI 私教回顾'),
            ),
          ),
          const SizedBox(height: 8),
          _buildAiRecap(),
          const Divider(height: 32),
          _section('6 userType 偏好（按出现次数）'),
          _bar(s['userTypePick']),
          _section('4 scene 偏好'),
          _bar(s['scenePick']),
          _section('24 桶组合 top 8（userType × scene）'),
          _bar(s['bucketPick']),
          _section('Top 10 详情点击条目 id'),
          _bar(s['itemOpens']),
          _section('搜索词 top 10'),
          _bar(s['searchTerms']),
          _section('按 contentType 收藏次数'),
          _bar(s['savesByType']),
          const SizedBox(height: 32),
          Text(
            '宪法 §1.1：数据只在设备本地，SharedPreferences，不上服务器。',
            style: TextStyle(fontSize: 11, color: AppTheme.hintColor(context)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 200, child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  /// bars = List<MapEntry<String, int>>
  Widget _bar(dynamic bars) {
    final list = (bars as List?)?.cast<MapEntry<String, int>>() ?? [];
    if (list.isEmpty) return Text('（暂无数据）', style: TextStyle(color: AppTheme.hintColor(context)));
    final max = list.first.value.clamp(1, 1 << 30);
    return Column(
      children: list.map((e) {
        final pct = e.value / max;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(width: 100, child: Text(e.key, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              Expanded(
                child: Stack(
                  children: [
                    Container(height: 14, decoration: BoxDecoration(color: AppTheme.textLight.withOpacity(0.15), borderRadius: BorderRadius.circular(3))),
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(height: 14, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(3))),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 40, child: Text('${e.value}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 6/10 加: 过去 56 天热力图（GitHub 风格）
  Widget _buildHeatmap() {
    return FutureBuilder<List<({DateTime day, int count})>>(
      future: StreakService().getDailyHeatmap(days: 56),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 1)));
        final data = snap.data!;
        if (data.isEmpty) return const Text('（暂无数据）');
        // 6/12 改: 全 0 时压缩为一行
        final totalCount = data.fold<int>(0, (s, e) => s + e.count);
        if (totalCount == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '近 8 周还没阅读记录',
              style: TextStyle(fontSize: 12, color: AppTheme.hintColor(ctx)),
            ),
          );
        }
        final maxCount = data.fold<int>(1, (m, e) => e.count > m ? e.count : m);
        // 7 列（周） x 8 行（56/7=8）
        final cols = <List<({DateTime day, int count})>>[];
        for (int i = 0; i < data.length; i += 7) {
          cols.add(data.sublist(i, i + 7 > data.length ? data.length : i + 7));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: cols.map((week) {
                return Column(
                  children: week.map((d) {
                    final ratio = d.count / maxCount;
                    final color = d.count == 0
                        ? AppTheme.textLight.withOpacity(0.1)
                        : AppTheme.primary.withOpacity(0.2 + ratio * 0.8);
                    return Container(
                      width: 12, height: 12, margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text('过去 8 周 · 峰值 $maxCount 次/天', style: TextStyle(fontSize: 10, color: AppTheme.hintColor(context))),
          ],
        );
      },
    );
  }

  // 6/10 加: 本周回顾 (看 / 听 / 收藏 / 活跃分钟)
  // 6/26 Brien 反馈: Sofa 启发, 加 "本周最常看类目" 1 行
  Widget _buildWeeklyRecap() {
    return FutureBuilder<({int watchedArticles, int listenedAudio, int savedCount, int minutesActive})>(
      future: StreakService().getWeeklyRecap(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final r = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stat('看文章', '${r.watchedArticles}'),
            _stat('听音频', '${r.listenedAudio}'),
            _stat('收藏', '${r.savedCount}'),
            _stat('活跃分钟', '${r.minutesActive}'),
            // 6/26: Sofa 启发 1 行 — 复用 WeeklyRecapService 拿本周最常看 source
            FutureBuilder<WeeklyRecap>(
              future: WeeklyRecapService.instance.generate(useLLM: false),
              builder: (ctx2, snap2) {
                if (!snap2.hasData || snap2.data!.perSource.isEmpty) return const SizedBox.shrink();
                final entries = snap2.data!.perSource.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final top = entries.first;
                return _stat('本周最常看', '${top.key} ×${top.value}');
              },
            ),
          ],
        );
      },
    );
  }

  // 6/11 加: 生成 AI 私教回顾
  Future<void> _generateAiRecap(BuildContext context) async {
    setState(() => _aiRecapLoading = true);
    final r = await StreakService().getWeeklyRecap();
    final prompt = '本周看 ${r.watchedArticles} 篇文章、听 ${r.listenedAudio} 次、收藏 ${r.savedCount} 个、活跃 ${r.minutesActive} 分钟。给 2 句温紫鼓励总结。';
    final recap = await LlmService.generateRaw(prompt, isEn: false);
    if (!mounted) return;
    setState(() {
      _aiRecap = recap;
      _aiRecapLoading = false;
    });
  }

  // 6/11 加: 显示 AI 回顾文本
  Widget _buildAiRecap() {
    if (_aiRecapLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('AI 思考中...', style: TextStyle(fontSize: 12, color: AppTheme.hintColor(context))),
          ],
        ),
      );
    }
    if (_aiRecap == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(_aiRecap!, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
