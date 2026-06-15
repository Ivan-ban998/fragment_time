// 6/15 紧急最小版 - 之前 1736 行 (LLM/进度/dark mode 等) 全段被误删
// TODO: 重新实现核心功能 (LLM 流式/收藏/进度/glass background/dark mode/Tinder 跳/续读)

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/llm_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/eye_protection_scope.dart';
import '../services/local_subscription_service.dart';
import '../services/user_preference_service.dart';
import '../services/content_aggregator.dart';
import '../services/subscription_service.dart';
import '../services/analytics_service.dart';
import '../main.dart';
import '../services/tts_service.dart';
import 'content_reader_screen.dart';

class ContentScreen extends StatefulWidget {
  final UserType userType;
  final Scene scene;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final ContentItem? prefillItem;
  const ContentScreen({
    super.key,
    required this.userType,
    required this.scene,
    this.isInternational = false,
    this.isElderlyMode = false,
    this.languageCode = 'zh',
    this.prefillItem,
  });
  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen> {
  String _buf = '';
  bool _loading = true;
  bool _llmGotFirstChunk = false;
  Timer? _llmFallbackTimer;
  StreamSubscription? _sub;
  ContentItem? _aiContentItem;
  LlmSummary? _summary;
  int _streak = 0;
  List<ContentItem> _recItems = [];

  double get _scale => widget.isElderlyMode ? 1.3 : 1.0;
  bool get isEn => widget.languageCode == 'en';

  // 6/15 dark mode: dark 走老单色亮底
  Color? _sceneBgColor() {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (isDark) return _sceneBackground();
    return null;
  }

  LinearGradient get _sceneBgGradient {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isWarm = EyeProtectionScope.of(context);
    return GlassStyle.sceneBackground(widget.scene.name, dark: isDark, warm: isWarm);
  }

  Color _sceneBackground() {
    switch (widget.scene) {
      case Scene.learn: return const Color(0xFFFAF7FF);
      case Scene.listen: return const Color(0xFFF1F3F8);
      case Scene.relax: return const Color(0xFFFFF5F0);
      case Scene.workout: return const Color(0xFFF0F8F4);
    }
  }

  String _sceneName() {
    if (isEn) {
      switch (widget.scene) {
        case Scene.learn: return 'Learn';
        case Scene.listen: return 'Listen';
        case Scene.relax: return 'Relax';
        case Scene.workout: return 'Workout';
      }
    }
    switch (widget.scene) {
      case Scene.learn: return '学';
      case Scene.listen: return '听';
      case Scene.relax: return '放松';
      case Scene.workout: return '运动';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
    _sub?.cancel();
    _llmGotFirstChunk = false;
    _llmFallbackTimer?.cancel();
    _llmFallbackTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (!_llmGotFirstChunk && _loading) {
        _showStub();
      }
    });
    _startLlmStream();
  }

  Future<void> _loadRecommendations() async {
    try {
      final rec = await ContentAggregator().fetchRecommendContent(
        userType: widget.userType,
        scene: widget.scene,
        isInternational: widget.isInternational,
      );
      if (mounted) setState(() => _recItems = rec);
    } catch (_) {}
  }

  void _showStub() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _buf = isEn
          ? 'AI is responding slowly. Showing pre-cached content.'
          : 'AI 响应较慢。下方为你预准备的内容。';
    });
  }

  Future<void> _startLlmStream() async {
    try {
      String prefSummary = '';
      try {
        prefSummary = await UserPreferenceService.instance.getPreferenceSummary(
          userType: widget.userType,
          scene: widget.scene,
        );
      } catch (_) {}
      _sub = LlmService.generateStream(
        userType: widget.userType,
        scene: widget.scene,
        languageCode: widget.languageCode,
        isInternational: widget.isInternational,
        prefSummary: prefSummary.isEmpty ? null : prefSummary,
      ).listen((chunk) {
        if (!mounted) return;
        if (!_llmGotFirstChunk) {
          _llmGotFirstChunk = true;
          _llmFallbackTimer?.cancel();
          setState(() {
            _loading = false;
            _buf = chunk;
          });
        } else {
          setState(() => _buf += chunk);
        }
      }, onError: (e) {
        if (!mounted) return;
        if (!_llmGotFirstChunk) {
          _showStub();
        }
      }, onDone: () {
        if (!mounted) return;
        if (_buf.isEmpty) _showStub();
        _summary = LlmSummary.parse(_buf);
      });
    } catch (e) {
      _showStub();
    }
  }

  @override
  void dispose() {
    _llmFallbackTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // 6/15 加: 借鉴"不做手机控"番茄钟 — 老人友好正反馈
  Widget _buildCompleteFab(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _markComplete,
      backgroundColor: AppTheme.primary,
      icon: const Icon(Icons.celebration, color: Colors.white),
      label: Text(
        isEn ? 'I read it' : '读完啦',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _markComplete() async {
    if (_aiContentItem != null) {
      try {
        await LocalSubscriptionService.instance.updateProgress(_aiContentItem!, 100);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {});
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 8),
              Text(isEn ? 'Well done!' : '读完啦！',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 6),
              Text(isEn ? '+5 XP · keep the streak going' : '+5 经验',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9))),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(isEn ? 'OK' : '好', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = isEn ? widget.userType.name : widget.userType.title;
    final title = '$userName · ${_sceneName()}';

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: _sceneBgColor() == null ? _sceneBgGradient : null,
          color: _sceneBgColor(),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16 * _scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 18 * _scale, fontWeight: FontWeight.w600)),
                SizedBox(height: 12 * _scale),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      _buf.isEmpty ? (isEn ? 'Loading...' : '加载中...') : _buf,
                      style: TextStyle(fontSize: 14 * _scale, height: 1.5),
                    ),
                  ),
                ),
                if (_recItems.isNotEmpty) ...[
                  SizedBox(height: 12 * _scale),
                  Text(isEn ? 'You may also like' : '你可能还喜欢',
                      style: TextStyle(fontSize: 12 * _scale, color: AppTheme.textLight)),
                  SizedBox(height: 8 * _scale),
                  SizedBox(
                    height: 80 * _scale,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _recItems.length,
                      separatorBuilder: (_, __) => SizedBox(width: 8 * _scale),
                      itemBuilder: (_, i) {
                        final it = _recItems[i];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ContentScreen(
                                userType: widget.userType, scene: widget.scene,
                                isInternational: widget.isInternational,
                                isElderlyMode: widget.isElderlyMode,
                                languageCode: widget.languageCode, prefillItem: it,
                              ),
                            ));
                          },
                          child: Container(
                            width: 160 * _scale,
                            padding: EdgeInsets.all(8 * _scale),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(it.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11 * _scale)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _buildCompleteFab(context),
    );
  }
}
