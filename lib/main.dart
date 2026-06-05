import 'package:flutter/material.dart';
import 'models/models.dart';
import 'theme/app_theme.dart';
import 'services/local_subscription_service.dart';
import 'services/locale_service.dart';
import 'services/motivation_service.dart';
import 'services/audio_play_service.dart';
import 'screens/user_type_screen.dart';
import 'screens/scene_screen.dart';
import 'screens/content_screen.dart';
import 'screens/content_reader_screen.dart';
import 'screens/search_screen.dart';
import 'screens/my_subscriptions_screen.dart';
import 'screens/settings_tab.dart';

void main() {
  runApp(const FragmentTimeApp());
}

class FragmentTimeApp extends StatelessWidget {
  const FragmentTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '碎片时间',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final LocalSubscriptionService _subService = LocalSubscriptionService();
  final LocaleService _localeService = LocaleService();
  final StreakService _streakService = StreakService();
  final AudioPlayService _audioService = AudioPlayService();

  bool _isInternational = false;
  bool _isElderlyMode = false;
  String _languageCode = 'zh';
  List<ContentItem> _subscribedItems = [];
  int _subscriptionCount = 0;
  int _selectedIndex = 0;
  String _streakMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  bool get isEn => _languageCode == 'en';
  double get _scale => _isElderlyMode ? 1.3 : 1.0;

  Future<void> _loadSettings() async {
    final isInt = await _localeService.getIsInternational();
    final isElderly = await _localeService.getIsElderlyMode();
    final lang = await _localeService.getLanguageCode();
    final items = await _subService.getSubscribedItems();
    final msg = await _streakService.getStreakMessage(isEn);
    setState(() {
      _isInternational = isInt;
      _isElderlyMode = isElderly;
      _languageCode = lang;
      _subscribedItems = items;
      _subscriptionCount = items.length;
      _streakMessage = msg;
    });
  }

  Future<void> _toggleInternational() async {
    setState(() => _isInternational = !_isInternational);
    await _localeService.setIsInternational(_isInternational);
  }

  Future<void> _toggleLanguage() async {
    setState(() => _languageCode = _languageCode == 'zh' ? 'en' : 'zh');
    await _localeService.setLanguageCode(_languageCode);
  }

  Future<void> _toggleElderlyMode() async {
    setState(() => _isElderlyMode = !_isElderlyMode);
    await _localeService.setIsElderlyMode(_isElderlyMode);
  }

  @override
  Widget build(BuildContext context) {
    final config = _isInternational ? AppConfig.global : AppConfig.domestic;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          UserTypeScreen(
            config: config,
            isInternational: _isInternational,
            isElderlyMode: _isElderlyMode,
            languageCode: _languageCode,
            streakMessage: _streakMessage,
            onToggleInternational: _toggleInternational,
            onToggleLanguage: _toggleLanguage,
            onToggleElderlyMode: _toggleElderlyMode,
          ),
          SearchScreen(
            isElderlyMode: _isElderlyMode,
            languageCode: _languageCode,
          ),
          MySubscriptionsScreen(
            subscribedItems: _subscribedItems,
            onUnsubscribe: _handleUnsubscribe,
            isElderlyMode: _isElderlyMode,
          ),
          SettingsTab(
            config: config,
            isInternational: _isInternational,
            isElderlyMode: _isElderlyMode,
            languageCode: _languageCode,
            onToggleInternational: _toggleInternational,
            onToggleLanguage: _toggleLanguage,
            onToggleElderlyMode: _toggleElderlyMode,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, size: _scale > 1 ? 28 : 24),
            selectedIcon: Icon(Icons.home, size: _scale > 1 ? 28 : 24),
            label: isEn ? 'Home' : '首页',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _subscriptionCount > 0,
              label: Text('$_subscriptionCount'),
              child: Icon(Icons.bookmark_outline, size: _scale > 1 ? 28 : 24),
            ),
            selectedIcon: Badge(
              isLabelVisible: _subscriptionCount > 0,
              label: Text('$_subscriptionCount'),
              child: Icon(Icons.bookmark, size: _scale > 1 ? 28 : 24),
            ),
            label: isEn ? 'Subscriptions' : '订阅',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, size: _scale > 1 ? 28 : 24),
            selectedIcon: Icon(Icons.settings, size: _scale > 1 ? 28 : 24),
            label: isEn ? 'Settings' : '设置',
          ),
        ],
      ),
    );
  }

  void _handleUnsubscribe(ContentItem item) async {
    await _subService.unsubscribe(item);
    await _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEn ? 'Unsubscribed' : '已取消订阅'),
          action: SnackBarAction(
            label: isEn ? 'Undo' : '撤销',
            onPressed: () async {
              await _subService.subscribe(item);
              await _loadSettings();
            },
          ),
        ),
      );
    }
  }
}
