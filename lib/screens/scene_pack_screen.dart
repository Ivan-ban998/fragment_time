// 6/9 场景包 screen — 用户选 5 篇 → 命名 → 一键进
import 'package:flutter/material.dart';
import '../theme/glass_decoration.dart';
import '../models/models.dart';
import '../services/local_subscription_service.dart';
import '../services/news_service.dart';
import '../theme/app_theme.dart';
import 'content_reader_screen.dart';

class ScenePackScreen extends StatefulWidget {
  final UserType userType;
  final Scene scene;
  final bool isEn;
  const ScenePackScreen({super.key, required this.userType, required this.scene, required this.isEn});

  @override
  State<ScenePackScreen> createState() => _ScenePackScreenState();
}

class _ScenePackScreenState extends State<ScenePackScreen> {
  final Set<String> _selected = {};
  final TextEditingController _nameCtrl = TextEditingController();
  final LocalSubscriptionService _svc = LocalSubscriptionService.instance;

  late Future<List<ContentItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _load();
  }

  Future<List<ContentItem>> _load() async {
    // 调 news_service 按 userType+scene 拉 6 条
    final news = NewsService();
    return await news.getRecommendations(widget.userType, widget.scene);
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    String defaultName;
    if (hour < 9) defaultName = widget.isEn ? 'Morning pack' : '早安包';
    else if (hour < 14) defaultName = widget.isEn ? 'Lunch pack' : '午休包';
    else if (hour < 18) defaultName = widget.isEn ? 'Afternoon pack' : '下午包';
    else if (hour < 22) defaultName = widget.isEn ? 'Evening pack' : '晚上包';
    else defaultName = widget.isEn ? 'Night pack' : '睡前包';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(widget.isEn ? 'Scene Pack' : '场景包'),
      ),
      body: FutureBuilder<List<ContentItem>>(
        future: _itemsFuture,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _nameCtrl..text = defaultName,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: widget.isEn ? 'Pack name' : '包名',
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return CheckboxListTile(
                      value: _selected.contains(it.id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(it.id);
                          } else {
                            _selected.remove(it.id);
                          }
                        });
                      },
                      title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${it.source} · ${it.duration}'),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () async {
                          final picked = items.where((i) => _selected.contains(i.id)).toList();
                          await _svc.setPack(_nameCtrl.text, picked);
                          if (mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.save),
                  label: Text('${widget.isEn ? "Save" : "保存"} (${_selected.length})'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
