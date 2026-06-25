// 6/25 Brien 21:33 '首次进入搞个欢迎界面取昵称或跳过'
// 流程: 欢迎语 → 输入昵称 (可跳过) → 选角色 (UserTypeScreen)
// 检测: SharedPreferences 'first_run_done_v1' == false → 显示

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/handle_service.dart';
import '../theme/app_theme.dart';
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
  const WelcomeScreen({super.key, this.isEn = false});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late TextEditingController _ctrl;
  String _currentHandle = HandleService.defaultHandle;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _currentHandle);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _complete({bool save = true}) async {
    if (save && _ctrl.text.trim().isNotEmpty) {
      await HandleService().set(_ctrl.text.trim());
    }
    // 标记首次完成 + 设 first_run_done_v1 = true
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_run_done_v1', true);
    if (!mounted) return;
    // 6/25: 欢迎屏不是单独路由, 是 main Stack 覆盖层
    // 通过 Navigator 拿到上层 MainHomeScreenState 调 _showWelcome = false
    // 这里用 Navigator.popUntil(rootNavigator) 不可行 (不在 Route 栈)
    // 最简: 直接通过 rootNavigator 返回, 但其实覆盖层没用 MaterialPageRoute, 需要其他方式
    // 改用全局 ValueNotifier 通知 MainHomeScreenState 关掉
    WelcomeCompleteSignal.notifyComplete();
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
              const SizedBox(height: 12),
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
                  prefixIcon: Icon(Icons.alternate_email, color: AppTheme.primary),
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