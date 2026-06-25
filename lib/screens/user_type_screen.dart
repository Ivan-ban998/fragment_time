import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass_decoration.dart';
import '../services/analytics_service.dart';
import '../services/local_subscription_service.dart';
import '../services/time_aware_recommender.dart';
import 'scene_screen.dart';
import 'content_screen.dart';
import 'topic_onboarding_screen.dart';

class UserTypeScreen extends StatefulWidget {
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

  @override
  State<UserTypeScreen> createState() => _UserTypeScreenState();
}

class _UserTypeScreenState extends State<UserTypeScreen> {
  // 6/24 B 方案：完整模式 — 5 桶默认 + 老人默认折叠其余桶
  late bool _showAllTypes;

  @override
  void initState() {
    super.initState();
    // 6/24 B 方案：老人默认折叠，非老人默认展开
    _showAllTypes = !widget.isElderlyMode;
  }

  @override
  void didUpdateWidget(UserTypeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换老人模式时同步默认行为
    if (oldWidget.isElderlyMode != widget.isElderlyMode) {
      setState(() {
        _showAllTypes = !widget.isElderlyMode;
      });
    }
  }

  bool get isEn => widget.languageCode == 'en';
  double get scale => widget.isElderlyMode ? 1.3 : 1.0;

  @override
  Widget build(BuildContext context) {
    final userTypes = widget.isInternational
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

    // 6/24 v11: 6 个角色平等 (老人回 6 桶)，卡片缩小一屏显全
    final allUserTypes = userTypes; // student/office/entrepreneur/parent/senior/child

    final titleText = widget.isInternational
        ? '碎片时间'
        : '碎片时间';

    final subtitleText = isEn
        ? (widget.isElderlyMode
            ? 'Tap your identity to start'
            : 'Select your identity to find content for you')
        : (widget.isElderlyMode
            ? '点一下你的身份开始'
            : '选择你的身份，找到适合你的碎片时间内容');

    final copyrightFooter = widget.config.copyrightFooter as String;

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
                    onTap: widget.onToggleLanguage,
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
                    onTap: widget.onToggleInternational,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                      decoration: BoxDecoration(
                        color: widget.isInternational ? AppTheme.primary : Colors.grey[300],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.public,
                            size: 16 * scale,
                            color: widget.isInternational ? Colors.white : Colors.grey[600],
                          ),
                          SizedBox(width: 4),
                          Text(
                            widget.isInternational ? 'INTL' : 'CN',
                            style: TextStyle(
                              fontSize: 12 * scale,
                              fontWeight: FontWeight.w600,
                              color: widget.isInternational ? Colors.white : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  // Elderly mode toggle
                  GestureDetector(
                    onTap: widget.onToggleElderlyMode,
                    child: Container(
                      padding: EdgeInsets.all(6 * scale),
                      decoration: BoxDecoration(
                        color: widget.isElderlyMode ? Colors.orange : Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.elderly,
                        size: 16 * scale,
                        color: widget.isElderlyMode ? Colors.white : Colors.grey[600],
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
                        widget.onUserTypeSelected(rec.userType);
                        // 6/23 fix: 跟 _TodayPickCard 一致，跳到 SceneScreen — 之前没跳所以点不开
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SceneScreen(
                              userType: rec.userType,
                              isInternational: widget.isInternational,
                              isElderlyMode: widget.isElderlyMode,
                              languageCode: widget.languageCode,
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
                  final type = widget.selectedUserType ?? UserType.student;
                  AnalyticsService.instance.track(AnalyticsService.EVT_USER_TYPE_SELECT,
                      props: {'userType': type.name, 'source': 'today_pick'});
                  widget.onUserTypeSelected(type);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SceneScreen(
                        userType: type,
                        isInternational: widget.isInternational,
                        isElderlyMode: widget.isElderlyMode,
                        languageCode: widget.languageCode,
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
              if (widget.streakMessage.isNotEmpty) ...[
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
                          widget.streakMessage,
                          style: TextStyle(fontSize: 13 * scale, color: AppTheme.primary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8 * scale),
              ],
              // 6/24 B 方案：5 桶主区 + 1 桶折叠（老人模式默认折叠，老人以外默认展开）
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 5 桶主区
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          // 6/25 Brien 反馈: 3 列太小 → 回到 2 列 (老默认)
                          final cols = widget.isElderlyMode ? 1 : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              mainAxisSpacing: 12 * scale,
                              crossAxisSpacing: 12 * scale,
                              childAspectRatio: cols == 1 ? 2.0 : 1.1,
                            ),
                            itemCount: allUserTypes.length,
                            itemBuilder: (context, index) {
                              final ut = allUserTypes[index];
                              final isSelected = widget.selectedUserType == ut.type;
                              return _UserTypeCard(
                                userType: ut,
                                scale: scale,
                                isSelected: isSelected,
                                onTap: () {
                                  AnalyticsService.instance.track(AnalyticsService.EVT_USER_TYPE_SELECT,
                                      props: {'userType': ut.type.name});
                                  widget.onUserTypeSelected(ut.type);
                                  // 6/24 v15: 角色选完 → 话题 onboarding (可跳过) → SceneScreen
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TopicOnboardingScreen(
                                        isEn: isEn,
                                        isElderlyMode: widget.isElderlyMode,
                                        onComplete: () {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => SceneScreen(
                                                userType: ut.type,
                                                isInternational: widget.isInternational,
                                                isElderlyMode: widget.isElderlyMode,
                                                languageCode: widget.languageCode,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
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
