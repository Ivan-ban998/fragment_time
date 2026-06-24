// lib/screens/topic_onboarding_screen.dart
// 6/24 v15: 话题 onboarding — 角色选完后, 弹此页选喜欢的话题, 可跳过
// 关联: 选完的话题存到 SubscriptionService.subscribeCategory, 跟关注管理共享
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/subscription_service.dart';

class TopicOnboardingScreen extends StatefulWidget {
  final bool isEn;
  final bool isElderlyMode;
  final VoidCallback onComplete; // 选完或跳过回调

  const TopicOnboardingScreen({
    super.key,
    required this.isEn,
    this.isElderlyMode = false,
    required this.onComplete,
  });

  @override
  State<TopicOnboardingScreen> createState() => _TopicOnboardingScreenState();
}

class _TopicOnboardingScreenState extends State<TopicOnboardingScreen> {
  final Set<String> _selected = {};

  bool get isEn => widget.isEn;
  double get scale => widget.isElderlyMode ? 1.3 : 1.0;

  Future<void> _onConfirm() async {
    // 存到订阅管理
    for (final cat in _selected) {
      try {
        await SubscriptionService.instance.subscribeCategory(cat);
      } catch (_) {}
    }
    widget.onComplete();
  }

  void _onSkip() {
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final categories = SubscriptionService.getAllCategories(isEn: isEn);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.85),
        foregroundColor: AppTheme.primary,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          onPressed: _onSkip, // 顶部 X = 跳过
          tooltip: isEn ? 'Skip' : '跳过',
        ),
        title: Text(
          isEn ? 'Pick your topics' : '选择你喜欢的话题',
          style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部说明
              Text(
                isEn
                    ? 'Choose what you want to see. Skip if you just want to browse.'
                    : '挑几个你想看的, 不挑也行, 后面随时能改。',
                style: TextStyle(fontSize: 14 * scale, color: AppTheme.textLight),
              ),
              SizedBox(height: 20 * scale),
              // 12 类目 Wrap 多选
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10 * scale,
                    runSpacing: 10 * scale,
                    children: categories.map((cat) {
                      final isSelected = _selected.contains(cat);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(cat);
                            } else {
                              _selected.add(cat);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(
                            horizontal: 14 * scale,
                            vertical: 10 * scale,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primary
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary
                                  : Colors.grey[300]!,
                              width: 1.5,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primary.withOpacity(0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                size: 16 * scale,
                                color: isSelected ? Colors.white : AppTheme.primary,
                              ),
                              SizedBox(width: 6 * scale),
                              Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 14 * scale,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // 底部按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _onSkip,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14 * scale),
                        side: BorderSide(color: Colors.grey[400]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isEn ? 'Skip' : '跳过',
                        style: TextStyle(
                          fontSize: 15 * scale,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: EdgeInsets.symmetric(vertical: 14 * scale),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isEn
                            ? 'Done (${_selected.length})'
                            : '完成${_selected.length > 0 ? " (${_selected.length})" : ""}',
                        style: TextStyle(
                          fontSize: 15 * scale,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
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