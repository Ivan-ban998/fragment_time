import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/analytics_service.dart';
import '../services/local_subscription_service.dart';
import '../services/time_aware_recommender.dart';
import 'scene_screen.dart';
import 'content_screen.dart';

class UserTypeScreen extends StatelessWidget {
  final dynamic config;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  final String streakMessage;
  final UserType? selectedUserType;
  final VoidCallback onToggleInternational;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleElderlyMode;
  final ValueChanged<UserType> onUserTypeSelected;

  const UserTypeScreen({
    super.key,
    required this.config,
    required this.isInternational,
    required this.isElderlyMode,
    required this.languageCode,
    required this.streakMessage,
    this.selectedUserType,
    required this.onToggleInternational,
    required this.onToggleLanguage,
    required this.onToggleElderlyMode,
    required this.onUserTypeSelected,
  });

  bool get isEn => languageCode == 'en';
  double get scale => isElderlyMode ? 1.3 : 1.0;

  @override
  Widget build(BuildContext context) {
    final userTypes = isInternational
        ? [
            UserTypeIntl(UserType.student, 'Student', 'Exam prep & studies'),
            UserTypeIntl(UserType.officeWorker, 'Office Worker', 'Career & commute'),
            UserTypeIntl(UserType.entrepreneur, 'Entrepreneur', 'Business & decisions'),
            UserTypeIntl(UserType.parent, 'Parent', 'Parenting & family'),
            UserTypeIntl(UserType.senior, 'Senior', 'Health & hobbies'),
            UserTypeIntl(UserType.child, 'Child', 'Stories & science'),
          ]
        : [
            UserTypeIntl(UserType.student, '学生', '考试考证/学业提升'),
            UserTypeIntl(UserType.officeWorker, '上班族', '职场技能/通勤学习'),
            UserTypeIntl(UserType.entrepreneur, '创业者', '商业趋势/管理决策'),
            UserTypeIntl(UserType.parent, '宝爸宝妈', '亲子教育/家庭时光'),
            UserTypeIntl(UserType.senior, '退休人群', '养生健康/兴趣爱好'),
            UserTypeIntl(UserType.child, '儿童', '启蒙故事/科普'),
          ];

    final titleText = isInternational
        ? '碎片时间'
        : '碎片时间';

    final subtitleText = isEn
        ? 'Select your identity to find content for you'
        : '选择你的身份，找到适合你的碎片时间内容';

    final copyrightFooter = config.copyrightFooter as String;

    // 6/14 v5.4: 选角色页背景加白叠 (跟 content 一致, 不闷)
    return Container(
      decoration: BoxDecoration(
        gradient: GlassStyle.sceneBackgroundOverlay(),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      titleText,
                      style: TextStyle(
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  // Language toggle
                  GestureDetector(
                    onTap: onToggleLanguage,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.translate, size: 16 * scale, color: AppTheme.primary),
                          SizedBox(width: 4),
                          Text(
                            isEn ? '中' : 'EN',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14 * scale,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  // International toggle
                  GestureDetector(
                    onTap: onToggleInternational,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                      decoration: BoxDecoration(
                        color: isInternational ? AppTheme.primary : Colors.grey[300],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.public,
                            size: 16 * scale,
                            color: isInternational ? Colors.white : Colors.grey[600],
                          ),
                          SizedBox(width: 4),
                          Text(
                            isInternational ? 'INTL' : 'CN',
                            style: TextStyle(
                              fontSize: 12 * scale,
                              fontWeight: FontWeight.w600,
                              color: isInternational ? Colors.white : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  // Elderly mode toggle
                  GestureDetector(
                    onTap: onToggleElderlyMode,
                    child: Container(
                      padding: EdgeInsets.all(6 * scale),
                      decoration: BoxDecoration(
                        color: isElderlyMode ? Colors.orange : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.elderly,
                        size: 16 * scale,
                        color: isElderlyMode ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8 * scale),
              Text(
                subtitleText,
                style: TextStyle(fontSize: 14 * scale, color: AppTheme.textLight),
              ),
              SizedBox(height: 12 * scale),
              // 6/23: 按时段推荐 banner — 从精简版学来
              Builder(builder: (_) {
                final rec = TimeAwareRecommender.current;
                return Container(
                  margin: EdgeInsets.only(bottom: 12 * scale),
                  padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.auto_awesome, size: 14 * scale, color: AppTheme.primary),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isEn
                            ? 'Right now, we recommend: ${rec.label}'
                            : '根据现在的时间,推荐你: ${rec.label}',
                        style: TextStyle(
                          fontSize: 12 * scale,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        AnalyticsService.instance.track(
                          AnalyticsService.EVT_USER_TYPE_SELECT,
                          props: {'userType': rec.userType.name, 'source': 'time_recommend_banner'},
                        );
                        onUserTypeSelected(rec.userType);
                        // 6/23 fix: 跟 _TodayPickCard 一致，跳到 SceneScreen — 之前没跳所以点不开
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SceneScreen(
                              userType: rec.userType,
                              isInternational: isInternational,
                              isElderlyMode: isElderlyMode,
                              languageCode: languageCode,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isEn ? 'Go' : '去逛逛',
                          style: TextStyle(color: Colors.white, fontSize: 11 * scale, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
              SizedBox(height: 12 * scale),
              // 6/9 A：今日推荐 hero 按钮 — 0 步选角色，直接给 1 条内容
              _TodayPickCard(
                scale: scale,
                isEn: isEn,
                onTap: () {
                  final type = selectedUserType ?? UserType.student;
                  AnalyticsService.instance.track(AnalyticsService.EVT_USER_TYPE_SELECT,
                      props: {'userType': type.name, 'source': 'today_pick'});
                  onUserTypeSelected(type);
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
              ),
              SizedBox(height: 12 * scale),
              // 6/9 Sofa 启发：上次看到一半 — 进度未完
              _InProgressRow(scale: scale, isEn: isEn),
              SizedBox(height: 12 * scale),
              // Streak message + greeting
              if (streakMessage.isNotEmpty) ...[
                Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DailyMessage.getGreeting(isEn),
                          style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
                        ),
                        SizedBox(width: 8 * scale),
                        Text(
                          streakMessage,
                          style: TextStyle(fontSize: 13 * scale, color: AppTheme.primary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8 * scale),
              ],
              // 6/15 改: 屏宽 ≥480 用 3 列 (扁卡) 否则 2 列 (方卡), 一页显示全
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final cols = w >= 480 ? 3 : 2;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 16 * scale,
                        crossAxisSpacing: 16 * scale,
                        childAspectRatio: cols == 3 ? 1.4 : 1.0,
                      ),
                      itemCount: userTypes.length,
                      itemBuilder: (context, index) {
                        final ut = userTypes[index];
                        final isSelected = selectedUserType == ut.type;
                        return _UserTypeCard(
                          userType: ut,
                          scale: scale,
                          isSelected: isSelected,
                          onTap: () {
                            AnalyticsService.instance.track(AnalyticsService.EVT_USER_TYPE_SELECT,
                                props: {'userType': ut.type.name});
                            onUserTypeSelected(ut.type);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SceneScreen(
                                  userType: ut.type,
                                  isInternational: isInternational,
                                  isElderlyMode: isElderlyMode,
                                  languageCode: languageCode,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),


              Center(
                child: Text(
                  copyrightFooter,
                  style: TextStyle(fontSize: 10 * scale, color: AppTheme.textLight),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class UserTypeIntl {
  final UserType type;
  final String title;
  final String subtitle;
  const UserTypeIntl(this.type, this.title, this.subtitle);
}

class _UserTypeCard extends StatelessWidget {
  final UserTypeIntl userType;
  final double scale;
  final bool isSelected;
  final VoidCallback onTap;
  const _UserTypeCard({
    required this.userType,
    required this.scale,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: isSelected ? 8 : 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isSelected
              ? BorderSide(color: AppTheme.primary, width: 2.5)
              : BorderSide.none,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: isSelected
                  ? [
                      AppTheme.primary.withOpacity(0.25),
                      AppTheme.secondary.withOpacity(0.15),
                    ]
                  : [
                      AppTheme.primary.withOpacity(0.1),
                      AppTheme.secondary.withOpacity(0.05),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(userType.type.icon, size: 48 * scale, color: AppTheme.primary),
              SizedBox(height: 12 * scale),
              Text(
                userType.title,
                style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4 * scale),
              Text(
                userType.subtitle,
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

// 6/15 重写: 6/9 A 路线 hero 按钮 — 0 步选角色, 走默认 student + learn
class _TodayPickCard extends StatelessWidget {
  final double scale;
  final bool isEn;
  final VoidCallback onTap;

  const _TodayPickCard({
    required this.scale,
    required this.isEn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C5CFC), Color(0xFFA48BFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFC).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.white, size: 28 * scale),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn ? '"What should I read now?"' : '"现在看什么？"',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11 * scale,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    isEn ? 'Tap to start — 5 min story' : '点一下，5 分钟开始读',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8 * scale),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20 * scale),
              ),
              child: Text(
                isEn ? 'Start' : '开始',
                style: TextStyle(
                  color: const Color(0xFF7C5CFC),
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 6/15 重写: 6/9 Sofa 启发 — 续读小卡 (上次看到一半)
class _InProgressRow extends StatefulWidget {
  final double scale;
  final bool isEn;

  const _InProgressRow({required this.scale, required this.isEn});

  @override
  State<_InProgressRow> createState() => _InProgressRowState();
}

class _InProgressRowState extends State<_InProgressRow> {
  List<ContentItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await LocalSubscriptionService.instance.getInProgress(limit: 3);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64 * widget.scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        separatorBuilder: (_, __) => SizedBox(width: 10 * widget.scale),
        itemBuilder: (context, i) {
          final item = _items[i];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContentScreen(
                    userType: UserType.student,
                    scene: Scene.learn,
                    isInternational: false,
                    isElderlyMode: false,
                    languageCode: 'zh',
                  ),
                ),
              );
            },
            child: Container(
              width: 200 * widget.scale,
              padding: EdgeInsets.all(10 * widget.scale),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // 进度环
                  SizedBox(
                    width: 36 * widget.scale,
                    height: 36 * widget.scale,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: item.progress / 100,
                          strokeWidth: 3,
                          backgroundColor: AppTheme.primary.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                        ),
                        Text(
                          '${item.progress}%',
                          style: TextStyle(
                            fontSize: 10 * widget.scale,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8 * widget.scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.isEn ? 'Continue' : '继续读',
                          style: TextStyle(
                            fontSize: 10 * widget.scale,
                            color: AppTheme.textLight,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12 * widget.scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
