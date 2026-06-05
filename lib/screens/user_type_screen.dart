import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'scene_screen.dart';

class UserTypeScreen extends StatelessWidget {
  final AppConfig config;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final String streakMessage;
  final VoidCallback onToggleInternational;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleElderlyMode;

  const UserTypeScreen({
    super.key,
    required this.config,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
    required this.streakMessage,
    required this.onToggleInternational,
    required this.onToggleLanguage,
    required this.onToggleElderlyMode,
  });

  bool get isEn => languageCode == 'en';
  double get _scale => isElderlyMode ? 1.3 : 1.0;

  @override
  Widget build(BuildContext context) {
    final userTypes = UserType.values;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'FragmentTime' : '碎片时间'),
        actions: [
          IconButton(
            icon: Icon(isElderlyMode ? Icons.accessibility : Icons.accessibility_new, size: _scale > 1 ? 28 : 24),
            tooltip: isEn ? 'Elderly mode' : '老年模式',
            onPressed: onToggleElderlyMode,
          ),
          IconButton(
            icon: Text(isEn ? '中' : 'EN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _scale > 1 ? 18 : 14)),
            tooltip: isEn ? 'Switch to Chinese' : '切换英文',
            onPressed: onToggleLanguage,
          ),
          IconButton(
            icon: Icon(isInternational ? Icons.public : Icons.flag, size: _scale > 1 ? 28 : 24),
            tooltip: isInternational ? 'Switch to Domestic' : '切换国际版',
            onPressed: onToggleInternational,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20 * _scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DailyMessage.getGreeting(isEn)} 👋',
                style: TextStyle(fontSize: 22 * _scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8 * _scale),
              if (streakMessage.isNotEmpty)
                Text(
                  streakMessage,
                  style: TextStyle(fontSize: 14 * _scale, color: AppTheme.textLight),
                ),
              SizedBox(height: 8 * _scale),
              Text(
                isEn ? 'Who are you?' : '你是？',
                style: TextStyle(fontSize: 18 * _scale, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16 * _scale),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16 * _scale,
                    crossAxisSpacing: 16 * _scale,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: userTypes.length,
                  itemBuilder: (context, index) {
                    final type = userTypes[index];
                    return _UserTypeCard(
                      type: type,
                      isEn: isEn,
                      isInternational: isInternational,
                      scale: _scale,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SceneScreen(
                              userType: type,
                              isInternational: isInternational,
                              isElderlyMode: isElderlyMode,
                              languageCode: languageCode,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTypeCard extends StatelessWidget {
  final UserType type;
  final bool isEn;
  final bool isInternational;
  final double scale;
  final VoidCallback onTap;

  const _UserTypeCard({
    required this.type,
    required this.isEn,
    required this.isInternational,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.primary.withOpacity(0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(type.icon, style: TextStyle(fontSize: 48 * scale)),
              SizedBox(height: 8 * scale),
              Text(
                isInternational ? type.name : type.title,
                style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
