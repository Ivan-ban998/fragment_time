import 'package:shared_preferences/shared_preferences.dart';
import 'history_service.dart';

class StreakService {
  static const String _lastOpenDateKey = 'last_open_date';
  static const String _streakCountKey = 'streak_count';
  static const String _totalOpenCountKey = 'total_open_count';
  static const String _firstOpenDateKey = 'first_open_date';

  Future<int> getStreakCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakCountKey) ?? 0;
  }

  Future<int> getTotalOpenCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_totalOpenCountKey) ?? 0;
  }

  Future<void> recordOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    final lastOpenDate = prefs.getString(_lastOpenDateKey);

    int streak = prefs.getInt(_streakCountKey) ?? 0;
    int total = prefs.getInt(_totalOpenCountKey) ?? 0;

    if (lastOpenDate == null) {
      streak = 1;
      await prefs.setString(_firstOpenDateKey, today);
    } else if (lastOpenDate != today) {
      final parts = lastOpenDate.split('-');
      final last = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      if (last.year == yesterday.year && last.month == yesterday.month && last.day == yesterday.day) {
        streak += 1;
      } else {
        streak = 1;
      }
    }

    total += 1;
    await prefs.setString(_lastOpenDateKey, today);
    await prefs.setInt(_streakCountKey, streak);
    await prefs.setInt(_totalOpenCountKey, total);
  }

  Future<String> getStreakMessage(bool isEn) async {
    final streak = await getStreakCount();
    if (streak == 0) return '';
    if (streak == 1) return isEn ? 'First step taken!' : '开始了就是好开始！';
    if (streak <= 3) return isEn ? '$streak days streak!' : '已坚持$streak天！';
    if (streak <= 7) return isEn ? '$streak days strong!' : '$streak天越来越强！';
    return isEn ? '$streak days! Amazing!' : '$streak天！太厉害了！';
  }

  // 6/9 B：milestone 解锁 — 7 天 / 30 天
  // 7 天：解锁 "今日精选" tab (AI 出，不是预制)
  // 30 天：解锁 "私人电台" (按口味自动推)
  Future<List<String>> getUnlockedMilestones(bool isEn) async {
    final streak = await getStreakCount();
    final unlocked = <String>[];
    if (streak >= 7) {
      unlocked.add(isEn ? 'unlock_7' : '解锁7天');
    }
    if (streak >= 30) {
      unlocked.add(isEn ? 'unlock_30' : '解锁30天');
    }
    if (streak >= 100) {
      unlocked.add(isEn ? 'unlock_100' : '解锁100天');
    }
    return unlocked;
  }

  // 6/9 F：本周回顾 — 看 / 听 / 收藏 各多少
  Future<({int watchedArticles, int listenedAudio, int savedCount, int minutesActive})> getWeeklyRecap() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekKey = '${weekStart.year}-${weekStart.month}-${weekStart.day}';
    return (
      watchedArticles: prefs.getInt('week_${weekKey}_articles') ?? 0,
      listenedAudio: prefs.getInt('week_${weekKey}_audio') ?? 0,
      savedCount: prefs.getInt('week_${weekKey}_saved') ?? 0,
      minutesActive: prefs.getInt('week_${weekKey}_minutes') ?? 0,
    );
  }

  Future<void> recordEvent(String type) async {
    // type: 'article' / 'audio' / 'saved'
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekKey = '${weekStart.year}-${weekStart.month}-${weekStart.day}';
    final key = 'week_${weekKey}_${type == 'article' ? 'articles' : type == 'audio' ? 'audio' : 'saved'}';
    final cur = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, cur + 1);
    // 6/9 Sofa 启发 #2：每日热力图
    final dayKey = 'day_${now.year}-${now.month}-${now.day}';
    final dayCount = prefs.getInt(dayKey) ?? 0;
    await prefs.setInt(dayKey, dayCount + 1);
  }

  // 6/9 Sofa 启发 #2：返回过去 N 天的每日计数
  Future<List<({DateTime day, int count})>> getDailyHeatmap({int days = 56}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final result = <({DateTime day, int count})>[];
    for (int i = days - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final k = 'day_${d.year}-${d.month}-${d.day}';
      result.add((day: d, count: prefs.getInt(k) ?? 0));
    }
    return result;
  }

  // 6/9 AI 私教回顾：周日晚触发一次
  Future<String?> maybeGenerateWeeklyRecap({required bool isEn, required Future<String> Function(String prompt) llmCall}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    if (now.weekday != DateTime.sunday || now.hour < 20) return null;
    final weekKey = 'recap_${now.year}-${now.month}-${now.day}';
    if (prefs.getString(weekKey) != null) return null;
    final r = await getWeeklyRecap();
    final prompt = isEn
        ? 'This week I read ${r.watchedArticles} articles, listened ${r.listenedAudio} times, saved ${r.savedCount} items, active ${r.minutesActive} min. Give a 2-sentence encouraging summary.'
        : '本周看了 ${r.watchedArticles} 篇文章、听了 ${r.listenedAudio} 次、收藏了 ${r.savedCount} 个、活跃 ${r.minutesActive} 分钟。给 2 句鼓励总结。';
    final out = await llmCall(prompt);
    await prefs.setString(weekKey, out);
    return out;
  }

  // 6/24 AI 私教: 启动时生成 1 句鼓励 (今天读的内容 + 时段)
  // 跟周回顾不同: 不限周日, 每天首次启动都有; 防重 key = today_yyyy-m-d
  // 失败兜底: 返回一句硬编码的鼓励 (不调 LLM, 不影响性能)
  Future<String> getDailyEncouragement({
    required bool isEn,
    required Future<String> Function(String prompt) llmCall,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dayKey = 'encourage_${now.year}-${now.month}-${now.day}';
    // 防重: 今天的已经生成过, 直接用
    final cached = prefs.getString(dayKey);
    if (cached != null && cached.isNotEmpty) return cached;

    // 没生成过: 读今天的历史, 调 LLM
    final all = await HistoryService.instance.getAll();
    final today = all.where((h) {
      final t = DateTime.fromMillisecondsSinceEpoch(h.readAt);
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).toList();

    String prompt;
    if (today.isEmpty) {
      // 今天没读: 给开篇鼓励
      final hour = now.hour;
      final timeLabel = hour < 12 ? (isEn ? 'morning' : '上午') : hour < 18 ? (isEn ? 'afternoon' : '下午') : (isEn ? 'evening' : '晚上');
      prompt = isEn
          ? 'It is $timeLabel. The user just opened the app, no reading today yet. Give ONE short encouraging sentence (max 25 words) in warm tone. Do not say hello, do not use emoji, just the encouragement.'
          : '现在是$timeLabel，用户刚打开 app，今天还没读。给一句 25 字以内的温暖鼓励，不要问好，不要用 emoji。';
    } else {
      // 今天读了: 基于读的标题给鼓励
      final titles = today.take(3).map((h) => h.title).join(' / ');
      prompt = isEn
          ? 'User read these today: $titles. Give ONE short sentence (max 25 words) connecting what they read to action or insight. Warm tone, no emoji.'
          : '用户今天读了: $titles。给一句 25 字以内的鼓励, 把读的跟行动或洞察连起来, 温暖, 不用 emoji。';
    }

    String out;
    try {
      out = await llmCall(prompt);
      if (out.isEmpty) throw 'empty';
    } catch (_) {
      // 兜底: 硬编码鼓励
      out = isEn
          ? (today.isEmpty
              ? 'A new day, a fresh start. Five minutes is all it takes.'
              : 'You are building a habit, one small step at a time.')
          : (today.isEmpty
              ? '新的一天, 新的开始。5 分钟就够。'
              : '你正在一点点养成习惯, 已经很棒了。');
    }
    await prefs.setString(dayKey, out);
    return out;
  }

  // 6/24 v3 亮点: 每日 1 句名言 (按小时选作者, 跟场景色配)
  // 跟鼓励不同: 鼓励基于今天读的内容, 名言是通用智慧
  // 失败兜底: 返回一句硬编码的名言
  Future<String> getDailyQuote({
    required bool isEn,
    required Future<String> Function(String prompt) llmCall,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dayKey = 'quote_${now.year}-${now.month}-${now.day}';
    final cached = prefs.getString(dayKey);
    if (cached != null && cached.isNotEmpty) return cached;

    // 按时段选作者
    final hour = now.hour;
    final author = isEn
        ? (hour < 12 ? 'Marcus Aurelius' : hour < 18 ? 'Seneca' : 'Epictetus')
        : (hour < 12 ? '苏轼' : hour < 18 ? '李白' : '陶渊明');

    final prompt = isEn
        ? 'Quote from $author in original English. Maximum 25 words. Return ONLY the quote, no author name, no explanation, no quotation marks.'
        : '$author 一句诗或名言, 25 字以内。只返回名言本身, 不带作者名, 不带解释, 不带引号。';

    String out;
    try {
      out = await llmCall(prompt);
      if (out.isEmpty) throw 'empty';
    } catch (_) {
      // 兑底: 硬编码名訁 (按时段 + 语种)
      final quotes = isEn
          ? ['The impediment to action advances action.', 'We suffer more in imagination than in reality.', 'No man is free who is not master of himself.']
          : ['竹杖芒鞋轻胜马, 谁怕? 一蓑烟雨任平生。', '长风破浪会有时, 直挂云帆济沧海。', '采菊东篱下, 悠然见南山。'];
      final idx = (now.day + hour) % quotes.length;
      out = quotes[idx];
    }
    await prefs.setString(dayKey, out);
    return out;
  }

  // 给 streak +1 后的 milestone popup
  Future<({int streak, String? justUnlocked})> checkJustUnlocked(bool isEn, int prevStreak) async {
    final cur = await getStreakCount();
    String? just;
    if (prevStreak < 7 && cur >= 7) just = isEn ? '🔓 7 days — AI Pick unlocked' : '🔓 坚持 7 天 — 今日精选解锁';
    if (prevStreak < 30 && cur >= 30) just = isEn ? '🔓 30 days — Personal Radio unlocked' : '🔓 坚持 30 天 — 私人电台解锁';
    if (prevStreak < 100 && cur >= 100) just = isEn ? '💎 100 days — Legend status' : '💎 坚持 100 天 — 传奇级别';
    return (streak: cur, justUnlocked: just);
  }
}

class DailyMessage {
  static final List<String> _zhMessages = [
    '每天进步一点点，积少成多',
    '碎片时间，也能有大收获',
    '别小看这15分钟',
    '学习是一种习惯',
    '听点有用的，比刷视频强',
    '给自己一个变强的机会',
    '时间会奖励坚持的人',
    '小小的坚持，大大的改变',
  ];

  static final List<String> _enMessages = [
    'Progress one step at a time',
    'Small moments, big gains',
    '15 minutes makes a difference',
    'Learning is a habit',
    'Learn something useful instead of scrolling',
    'Give yourself a chance to grow',
    'Time rewards the persistent',
    'Small consistent actions, big results',
  ];

  static String get(bool isEn) {
    final msgs = isEn ? _enMessages : _zhMessages;
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return msgs[dayOfYear % msgs.length];
  }

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

// AI Summary Generation
class AISummary {
  static String generateSummary(String title, String description, String source, bool isEn) {
    // Simulated AI summary based on content
    final summaries = isEn
        ? [
            'This content covers key insights that can be absorbed in about 5 minutes. Perfect for your $source routine.',
            'Trending among ${source} listeners this week. Summarized: the core idea challenge traditional views.',
            'Community pick: This has been bookmarked by thousands of ${source} users. Quick summary available.',
          ]
        : [
            '这段内容约5分钟可以消化，配合你的$source使用习惯。',
            '本周在${source}圈子内很热，核心观点挑战传统认知。',
            '社区精选：已被数千${source}用户收藏，这里有摘要。',
          ];
    final hash = title.hashCode.abs();
    return summaries[hash % summaries.length];
  }

  static String getAIRecommendationReason(String userType, String scene, bool isEn) {
    final Map<String, Map<String, List<String>>> reasons = {
      'student': {
        'learn': [
          '基于你的学习目标，这是本周同温层最热的',
          '结合你的考试/考证需求，AI推荐这篇',
          '根据你的学业阶段，这篇点击量最高'
        ],
        'listen': [
          '适合通勤/碎片时间，被学生群体高频收听',
          '结合学习场景，这个在学生中很热',
          'AI匹配：你的身份+场景，这是热门推荐'
        ],
        'relax': [
          '学习累了？AI推荐你先休息一下',
          '研究表明适当的休息提升学习效率',
          '这是学生中最受欢迎的放松内容'
        ],
        'workout': [
          '学习之余也要活动身体',
          '结合你的学习节奏，推荐这个运动',
          '学生圈子里这个运动最热'
        ],
      },
      'officeWorker': {
        'learn': [
          '结合你的职场发展需求，这是热门',
          '被上班族高频点击的职场技能',
          '基于你的职场人设，这是精选'
        ],
        'listen': [
          '通勤场景首选，被上班族高频收听',
          '结合你的通勤时间，这是黄金选择',
          'AI推荐：这是本月职场类热门'
        ],
        'relax': [
          '工作累了？AI推荐这个放松一下',
          '这是上班族最喜欢的放松内容',
          '职场人必备的放松技巧'
        ],
        'workout': [
          '办公室健康必看，被上班族验证过',
          '结合你的工作节奏，这个最合适',
          '这是上班族中口碑最好的运动'
        ],
      },
      'parent': {
        'learn': [
          '结合你的育儿需求，这是精选',
          '被宝爸宝妈高频点击的内容',
          'AI推荐：家庭场景热门第一'
        ],
        'listen': [
          '育儿场景首选，被宝爸宝妈收藏',
          '结合亲子时间，这个最推荐',
          '这是父母圈子里很热的'
        ],
        'relax': [
          '带孩子辛苦了，AI推荐你放松',
          '这是父母群体最喜欢的放松',
          '育儿路上也要给自己喘息'
        ],
        'workout': [
          '亲子运动被验证过，效果好',
          '结合带孩子的节奏，这个最合适',
          '父母圈子里最热门的运动'
        ],
      },
      'senior': {
        'learn': [
          '根据你的兴趣，这是精选',
          '被同龄人高频点击的内容',
          'AI推荐：退休圈子里热门'
        ],
        'listen': [
          '养生日课首选，被老年人收藏',
          '结合你的休闲时间，这是热门',
          '这是同龄人中口碑最好的'
        ],
        'relax': [
          '修身养性，这是精选',
          '被退休群体验证过的放松',
          'AI推荐：养生圈子热门'
        ],
        'workout': [
          '结合你的身体状态，这个最合适',
          '被老年人高频练习的内容',
          '这是养生运动圈口碑第一'
        ],
      },
    };

    final userReasons = reasons[userType]?[scene] ?? reasons['officeWorker']![scene]!;
    final hash = (userType.hashCode + scene.hashCode).abs();
    return userReasons[hash % userReasons.length];
  }
}