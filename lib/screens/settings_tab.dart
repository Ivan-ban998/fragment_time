import 'package:flutter/material.dart';
import '../models/models.dart';

class SettingsTab extends StatelessWidget {
  final AppConfig config;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final VoidCallback onToggleInternational;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleElderlyMode;

  const SettingsTab({
    super.key,
    required this.config,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
    required this.onToggleInternational,
    required this.onToggleLanguage,
    required this.onToggleElderlyMode,
  });

  bool get isEn => languageCode == 'en';

  @override
  Widget build(BuildContext context) {
    final scale = isElderlyMode ? 1.3 : 1.0;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEn ? 'Settings' : '设置',
          style: TextStyle(fontSize: 18 * scale),
        ),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(isEn ? 'International Version' : '国际版'),
            subtitle: Text(
              isEn ? 'Switch to global content' : '切换到国际内容源',
            ),
            value: isInternational,
            onChanged: (_) => onToggleInternational(),
          ),
          SwitchListTile(
            title: Text(isEn ? 'English' : '中文'),
            subtitle: Text(isEn ? 'Switch language' : '切换语言'),
            value: isEn,
            onChanged: (_) => onToggleLanguage(),
          ),
          SwitchListTile(
            title: Text(isEn ? 'Elderly Mode' : '老年模式'),
            subtitle: Text(
              isEn ? 'Larger fonts & buttons' : '放大字体和按钮',
            ),
            value: isElderlyMode,
            onChanged: (_) => onToggleElderlyMode(),
          ),
          const Divider(),
          ListTile(
            title: Text(isEn ? 'About' : '关于'),
            subtitle: Text(config.copyright),
          ),
        ],
      ),
    );
  }
}
