// 6/25 Brien 21:33 '首次进入搞个欢迎界面取昵称或跳过'
// 流程: 欢迎语 → 输入昵称 (可跳过) → 选角色 (UserTypeScreen)
// 检测: SharedPreferences 'first_run_done_v1' == false → 显示

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/handle_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' as app;
import 'user_type_screen.dart';

// 6/25 WelcomeScreen → MainHomeScreen 通信信号 (ValueNotifier)
class WelcomeCompleteSignal {
  static final ValueNotifier<bool> _notifier = ValueNotifier<bool>(false);
  static ValueNotifier<bool> get instance => _notifier;
  static void notifyComplete() => _notifier.value = true;
  static void reset() => _notifier.value = false;
}

class WelcomeScreen extends StatefulWidget {
  final bool isEn;
  final VoidCallback? onComplete; // 6/28 19:54: 让 MainHomeScreen 传 callback, 不靠 globalKey
  const WelcomeScreen({super.key, this.isEn = false, this.onComplete});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late TextEditingController _ctrl;
  String _currentHandle = HandleService.defaultHandle;

  @override
  void initState() {
    super.initState();
    // 6/26 Brien 反馈: 默认值 '@你' 让人以为要保留 @, 改成空 (让用户直接输入)
    _ctrl = TextEditingController(text: _currentHandle == '@你' ? '' : _currentHandle);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // 6/28 Brien 反馈: WelcomeScreen 按钮无反应
  // 真凶: async 链中 `await HandleService().set()` 可能因为 web SharedPreferences 跨 isolate 卡住,
  //   后续 prefs.setBool + notifyComplete 都没跑。改成 fire-and-forget + 同步 prefs + 立即 notify
  void _complete({bool save = true}) {
    final text = _ctrl.text.trim();
    if (save && text.isNotEmpty) {
      // 不 await, fire-and-forget
      HandleService().set(text).catchError((_) {});
    }
    // prefs 也 fire-and-forget, 不阻塞 UI
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('first_run_done_v1', true);
    }).catchError((_) {});
    // 6/28: WelcomeCompleteSignal ValueNotifier + GlobalKey 双保险, onComplete 优先
    if (!mounted) return;
    WelcomeCompleteSignal.notifyComplete();
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      try {
        app.hideWelcomeScreenFromOutside();
      } catch (e) {
        debugPrint('[welcome] hideWelcomeScreenFromOutside 失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = widget.isEn;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Icon(Icons.waving_hand_outlined, size: 80, color: AppTheme.primary),
              const SizedBox(height: 24),
              Text(
                isEn ? 'Welcome!' : '欢迎！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                isEn
                    ? "Let's set up your fragment time."
                    : '来设置你的碎片时间。',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 40),
              Text(
                isEn ? 'Pick a handle' : '取个昵称',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                isEn
                    ? 'You can change it anytime in Settings.'
                    : '随时可以在设置中修改。',
                style: const TextStyle(fontSize: 13, color: Colors.black45),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: isEn ? 'Your name' : '你的昵称',
                  // 6/26 Brien 反馈: 输入框 @ 前缀图标让人误会要保留 @, 删了
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
                autofocus: true,
                onSubmitted: (_) => _complete(save: true),
              ),
              const Spacer(),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _complete(save: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isEn ? 'Continue' : '继续',
                    style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _complete(save: false),
                child: Text(
                  isEn ? 'Skip for now' : '暂时跳过',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}