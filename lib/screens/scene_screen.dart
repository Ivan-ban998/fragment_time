import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/analytics_service.dart';
import 'content_screen.dart';

class SceneScreen extends StatelessWidget {
  final UserType userType;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;

  const SceneScreen({
    super.key,
    required this.userType,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
  });

  double get _scale => isElderlyMode ? 1.3 : 1.0;
  bool get isEn => languageCode == 'en';

  @override
  Widget build(BuildContext context) {
    final scenes = isInternational
        ? [
            SceneIntl(Scene.learn, 'Learn Something', 'Progress every day', Colors.blue),
            SceneIntl(Scene.listen, 'Listen', 'Learn while commuting', Colors.purple),
            SceneIntl(Scene.relax, 'Relax', 'Deep breath & unwind', Colors.green),
            SceneIntl(Scene.workout, 'Workout', 'Stretch & move', Colors.orange),
          ]
        : [
            SceneIntl(Scene.learn, '学点东西', '每天进步一点点', Colors.blue),
            SceneIntl(Scene.listen, '听一听', '通勤路上听天下事', Colors.purple),
            SceneIntl(Scene.relax, '放松一下', '深呼吸，放空自己', Colors.green),
            SceneIntl(Scene.workout, '动一动', '告别久坐，活动筋骨', Colors.orange),
          ];

    final userTypeName = isInternational
        ? _getUserTypeName(userType)
        : _getUserTypeName(userType);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlassStyle.glassAppBarBg,
        foregroundColor: GlassStyle.glassAppBarFg,
        elevation: GlassStyle.glassAppBarElevation,
        title: Text(
          // 6/19 修: 删 userType.icon (IconData 不能跟 String 直接拼接, 6/19 00:16 Brien 反馈 'IconData(U+0E6F2)' bug)
          userTypeName,
          style: TextStyle(fontSize: 18 * _scale),
        ),
        leading: Material(
          color: Colors.white.withOpacity(0.6),
          shape: const CircleBorder(),
          child: IconButton(
            icon: Icon(Icons.arrow_back, size: 24 * _scale, color: AppTheme.primary),
            padding: EdgeInsets.all(12 * _scale),
            constraints: BoxConstraints.tightFor(width: 48 * _scale, height: 48 * _scale),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      // 6/14 v5.4: 选场景页背景加白叠
      body: Container(
        decoration: BoxDecoration(
          gradient: GlassStyle.sceneBackgroundOverlay(),
        ),
        child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20 * _scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DailyMessage.getGreeting(isEn)} ${userTypeName}',
                style: TextStyle(fontSize: 18 * _scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4 * _scale),
              Text(
                isEn ? 'What would you like to do?' : '选择你现在想干嘛',
                style: TextStyle(fontSize: 14 * _scale, color: AppTheme.textLight),
              ),
              SizedBox(height: 24 * _scale),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16 * _scale,
                    crossAxisSpacing: 16 * _scale,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: scenes.length,
                  itemBuilder: (context, index) {
                    final scene = scenes[index];
                    return _SceneCard(
                      scene: scene,
                      scale: _scale,
                      onTap: () {
                        AnalyticsService.instance.track(AnalyticsService.EVT_SCENE_SELECT, props: {
                          'userType': userType.name,
                          'scene': scene.type.name,
                        });
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContentScreen(
                              userType: userType,
                              scene: scene.type,
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
      ),
    );
  }

  String _getUserTypeName(UserType type) {
    switch (type) {
      case UserType.student:
        return isInternational ? 'Student' : '学生';
      case UserType.officeWorker:
        return isInternational ? 'Office Worker' : '上班族';
      case UserType.entrepreneur:
        return isInternational ? 'Entrepreneur' : '创业者';
      case UserType.parent:
        return isInternational ? 'Parent' : '宝爸宝妈';
      case UserType.senior:
        return isInternational ? 'Senior' : '退休人群';
      case UserType.child:
        return isInternational ? 'Child' : '儿童';
    }
  }
}

class SceneIntl {
  final Scene type;
  final String title;
  final String subtitle;
  final Color color;
  const SceneIntl(this.type, this.title, this.subtitle, this.color);
}

class _SceneCard extends StatelessWidget {
  final SceneIntl scene;
  final double scale;
  final VoidCallback onTap;
  const _SceneCard({required this.scene, required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: scene.color.withOpacity(0.1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(12 * scale),
                decoration: BoxDecoration(
                  color: scene.color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(scene.type.icon, size: 32 * scale),
              ),
              SizedBox(height: 12 * scale),
              Text(scene.title, style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w600)),
              SizedBox(height: 4 * scale),
              Text(
                scene.subtitle,
                style: TextStyle(fontSize: 11 * scale, color: AppTheme.textLight),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
  );
  }
}

class DailyMessage {
  static String getGreeting(bool isEn) {
    final hour = DateTime.now().hour;
    if (hour < 6) {
      return isEn ? 'Good night' : '夜深了，注意休息';
    } else if (hour < 9) {
      return isEn ? 'Good morning' : '早上好';
    } else if (hour < 12) {
      return isEn ? 'Good morning' : '上午好';
    } else if (hour < 14) {
      return isEn ? 'Good afternoon' : '中午好';
    } else if (hour < 18) {
      return isEn ? 'Good afternoon' : '下午好';
    } else if (hour < 22) {
      return isEn ? 'Good evening' : '傍晚好';
    } else {
      return isEn ? 'Good night' : '晚安';
    }
  }
}
