import 'package:flutter/material.dart';

enum BuildMode {
  domestic,
  global,
}

class AppConfig {
  final BuildMode mode;
  final String appName;
  final String packageSuffix;
  final List<ContentSource> availableSources;
  final String copyrightFooter;
  final bool showInternationalSources;

  const AppConfig({
    required this.mode,
    required this.appName,
    required this.packageSuffix,
    required this.availableSources,
    required this.copyrightFooter,
    required this.showInternationalSources,
  });

  static AppConfig get domestic => const AppConfig(
        mode: BuildMode.domestic,
        appName: '碎片时间',
        packageSuffix: '.domestic',
        availableSources: [
          ContentSource.ximalaya,
          ContentSource.lizhiFM,
          ContentSource.news36kr,
          ContentSource.zhihu,
        ],
        copyrightFooter: '©2024 碎片时间 | 内容版权归属原作者',
        showInternationalSources: false,
      );

  static AppConfig get global => const AppConfig(
        mode: BuildMode.global,
        appName: 'FragmentTime',
        packageSuffix: '.global',
        availableSources: [
          ContentSource.ximalaya,
          ContentSource.lizhiFM,
          ContentSource.news36kr,
          ContentSource.zhihu,
          ContentSource.applePodcasts,
          ContentSource.spotify,
          ContentSource.youtube,
          ContentSource.rss,
        ],
        copyrightFooter: '©2024 FragmentTime | Content copyright belongs to original creators',
        showInternationalSources: true,
      );
}

enum ContentSource {
  ximalaya('喜马拉雅', Icons.headphones, true),
  lizhiFM('荔枝FM', Icons.mic, true),
  news36kr('36氪', Icons.business_center, true),
  zhihu('知乎', Icons.forum, false),
  bilibili('B站', Icons.play_circle_filled, true),
  applePodcasts('Apple Podcasts', Icons.podcasts, false),
  spotify('Spotify', Icons.music_note, false),
  youtube('YouTube', Icons.play_circle_outline, false),
  rss('RSS订阅', Icons.rss_feed, true);

  final String name;
  final IconData icon;
  final bool isDomestic;

  const ContentSource(this.name, this.icon, this.isDomestic);
}

enum ContentPriceType {
  free('免费', Colors.green),
  membership('会员', Colors.orange),
  paid('付费', Colors.red);

  final String label;
  final Color color;
  const ContentPriceType(this.label, this.color);
}

/// 6/7 Brien 多种形式诉求：内容载体不只文章。
/// 宪法 §1.1 零服务器：video 类型用 embed iframe（不缓存）、audio 走跳原站
enum ContentType {
  article(Icons.article_outlined, '文章'),
  audio(Icons.headphones, '音频'),
  video(Icons.play_circle_outline, '视频'),
  short(Icons.flash_on, '短贴'),
  card(Icons.style, '资讯卡'),
  quiz(Icons.quiz, '测验');

  final IconData icon;
  final String label;
  const ContentType(this.icon, this.label);
}

/// 6/7 Brien 小窗看视频需求：仅用于 video 类型 + embed iframe
enum VideoPlatform {
  bilibili('B站', 'https://player.bilibili.com/player.html?bvid={id}&autoplay=0'),
  youtube('YouTube', 'https://www.youtube.com/embed/{id}'),
  vimeo('Vimeo', 'https://player.vimeo.com/video/{id}');

  final String name;
  final String _embedUrlTemplate;
  const VideoPlatform(this.name, this._embedUrlTemplate);

  String buildEmbedUrl(String videoId) =>
      _embedUrlTemplate.replaceAll('{id}', videoId);
}

class ContentItem {
  final String id;
  final String title;
  final String description;
  final String duration;
  final String source;
  final String? imageUrl;
  final String? audioUrl;
  final String? externalUrl;
  final ContentSource sourceType;
  final ContentPriceType priceType;
  final String? priceNote;
  final ContentType contentType;
  final String? videoId;
  final VideoPlatform? videoPlatform;
  // 6/9 Sofa 启发：进度追踪
  final int progress; // 0-100
  final DateTime? lastReadAt;

  const ContentItem({
    this.id = '',
    required this.title,
    required this.description,
    required this.duration,
    required this.source,
    this.imageUrl,
    this.audioUrl,
    this.externalUrl,
    required this.sourceType,
    this.contentType = ContentType.article,
    this.videoId,
    this.videoPlatform,
    this.progress = 0,
    this.lastReadAt,
    this.priceType = ContentPriceType.free,
    this.priceNote,
  });

  // 6/9 4：离线收藏包
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'duration': duration,
    'source': source,
    'imageUrl': imageUrl,
    'audioUrl': audioUrl,
    'externalUrl': externalUrl,
    'sourceType': sourceType.name,
    'priceType': priceType.name,
    'priceNote': priceNote,
    'contentType': contentType.name,
    'videoId': videoId,
    'videoPlatform': videoPlatform?.name,
    'progress': progress,
    'lastReadAt': lastReadAt?.toIso8601String(),
  };

  factory ContentItem.fromJson(Map<String, dynamic> m) => ContentItem(
    id: m['id'] ?? '',
    title: m['title'] ?? '',
    description: m['description'] ?? '',
    duration: m['duration'] ?? '',
    source: m['source'] ?? '',
    imageUrl: m['imageUrl'],
    audioUrl: m['audioUrl'],
    externalUrl: m['externalUrl'],
    sourceType: ContentSource.values.firstWhere(
      (e) => e.name == m['sourceType'],
      orElse: () => ContentSource.news36kr,
    ),
    priceType: ContentPriceType.values.firstWhere(
      (e) => e.name == m['priceType'],
      orElse: () => ContentPriceType.free,
    ),
    priceNote: m['priceNote'],
    contentType: ContentType.values.firstWhere(
      (e) => e.name == m['contentType'],
      orElse: () => ContentType.article,
    ),
    videoId: m['videoId'],
    videoPlatform: m['videoPlatform'] != null
        ? VideoPlatform.values.firstWhere(
            (e) => e.name == m['videoPlatform'],
            orElse: () => VideoPlatform.bilibili,
          )
        : null,
    progress: (m['progress'] ?? 0) as int,
    lastReadAt: m['lastReadAt'] != null
        ? DateTime.tryParse(m['lastReadAt'] as String)
        : null,
  );
}

enum UserType {
  student(Icons.school, '学生', '考试考证/学业提升', 'Student'),
  officeWorker(Icons.work, '上班族', '职场技能/通勤学习', 'Office Worker'),
  entrepreneur(Icons.rocket_launch, '创业者', '商业趋势/管理决策', 'Entrepreneur'),
  parent(Icons.family_restroom, '宝爸宝妈', '亲子教育/家庭时光', 'Parent'),
  senior(Icons.elderly, '退休人群', '养生健康/兴趣爱好', 'Senior'),
  child(Icons.child_care, '儿童', '启蒙故事/科普', 'Child');

  final IconData icon;
  final String title;
  final String subtitle;
  final String name;

  const UserType(this.icon, this.title, this.subtitle, this.name);
}

enum Scene {
  learn(Icons.school_outlined, '学点东西', '每天进步一点点', 'Learn'),
  listen(Icons.headphones, '听一听', '通勤路上听天下事', 'Listen'),
  relax(Icons.self_improvement, '放松一下', '深呼吸，放空自己', 'Relax'),
  workout(Icons.fitness_center, '动一动', '告别久坐，活动筋骨', 'Workout');

  final IconData icon;
  final String title;
  final String subtitle;
  final String name;

  const Scene(this.icon, this.title, this.subtitle, this.name);
}

// 6/9 修复：把 userType.name/scene.name（带空格/驼峰的"显示名"）映射到 _allContent 用的
// 真实分桶 key（"student" / "officeWorker" / "learn" 等）
// 用 extension 而不是改 model，避免影响其他用 .name 的地方
extension UserTypeBucket on UserType {
  String get bucketKey {
    switch (this) {
      case UserType.student: return 'student';
      case UserType.officeWorker: return 'officeWorker';
      case UserType.entrepreneur: return 'entrepreneur';
      case UserType.parent: return 'parent';
      case UserType.senior: return 'senior';
      case UserType.child: return 'child';
    }
  }
}

extension SceneBucket on Scene {
  String get bucketKey {
    switch (this) {
      case Scene.learn: return 'learn';
      case Scene.listen: return 'listen';
      case Scene.relax: return 'relax';
      case Scene.workout: return 'workout';
    }
  }
}
// 6/11 B2：AI 出题
// 宪法 §3：老人小孩用，AI 帮理解
// 每篇内容附 3 道选择题，点开看答案
class QuizQuestion {
  final String question;
  final List<String> choices; // 4 选 1
  final int correctIndex;     // 0-3
  final String? explanation;  // 答案解析（可空）

  const QuizQuestion({
    required this.question,
    required this.choices,
    required this.correctIndex,
    this.explanation,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> m) {
    return QuizQuestion(
      question: (m['question'] ?? '') as String,
      choices: ((m['choices'] as List?) ?? []).map((e) => e.toString()).toList(),
      correctIndex: (m['correctIndex'] ?? 0) as int,
      explanation: m['explanation'] as String?,
    );
  }
}
