import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/quote.dart';

// 7/15 重构后 Quote struct: 用 fallback 池里 struct 化 Quote。
// 14 + 13 = 27 条 (中 20 条 + 英 7 条), 一周内看不重复。
class _QuotePool {
  static final List<Quote> zh = [
    // 6/26 原文 4 条保留, 补作者 + 出处
    Quote(text: '竹杖芒鞋轻胜马，谁怕？一蓑烟雨任平生。', author: '苏轼', source: '定风波·莫听穿林打叶声', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '长风破浪会有时，直挂云帆济沧海。', author: '李白', source: '行路难·其一', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '采菊东篱下，悠然见南山。', author: '陶渊明', source: '饮酒·其五', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '行到水穷处，坐看云起时。', author: '王维', source: '终南别业', createdAt: DateTime(2026, 1, 1)),
    // 6/26 原文另外 3 条
    Quote(text: '不畏浮云遮望眼，自缘身在最高层。', author: '王安石', source: '登飞来峰', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '会当凌绝顶，一览众山小。', author: '杜甫', source: '望岳', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '海纳百川，有容乃大；壁立千仞，无欲则刚。', author: '林则徐', source: '对联·后人辑录', createdAt: DateTime(2026, 1, 1)),
    // 7/15 补 13 条 (凑到 20, 一周看不重复)
    Quote(text: '莫愁前路无知己，天下谁人不识君。', author: '高适', source: '别董大', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '人生如逆旅，我亦是行人。', author: '苏轼', source: '临江仙·送钱穆父', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '此心安处是吾乡。', author: '苏轼', source: '定风波·南海归赠王定国侍人寓娘', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '沉舟侧畔千帆过，病树前头万木春。', author: '刘禹锡', source: '酬乐天扬州初逢席上见赠', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '旧时王谢堂前燕，飞入寻常百姓家。', author: '刘禹锡', source: '乌衣巷', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '何事吟余忽惆怅，村桥原树似吾乡。', author: '王安石', source: '暮春山居怀耿天衢', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '落红不是无情物，化作春泥更护花。', author: '龚自珍', source: '己亥杂诗·其五', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '我劝天公重抖擞，不拘一格降人才。', author: '龚自珍', source: '己亥杂诗·其一二五', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '纸上得来终觉浅，绝知此事要躬行。', author: '陆游', source: '冬夜读书示子聿', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '问渠那得清如许？为有源头活水来。', author: '朱熹', source: '观书有感·其一', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '少壮不努力，老大徒伤悲。', author: '佚名', source: '汉乐府·长歌行', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '黑发不知勤学早，白首方悔读书迟。', author: '颜真卿', source: '劝学诗', createdAt: DateTime(2026, 1, 1)),
    Quote(text: '少年辛苦终身事，莫向光阴惰寸功。', author: '杜荀鹤', source: '题弟侄书堂', createdAt: DateTime(2026, 1, 1)),
  ];

  static final List<Quote> en = [
    Quote(text: 'The impediment to action advances action. What stands in the way becomes the way.', author: 'Marcus Aurelius', authorEn: 'Marcus Aurelius', source: 'Meditations, Book 5', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'We suffer more in imagination than in reality.', author: 'Seneca', authorEn: 'Seneca', source: 'Letters from a Stoic', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'No man is free who is not master of himself.', author: 'Epictetus', authorEn: 'Epictetus', source: 'Discourses', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'What we do in life echoes in eternity.', author: 'Marcus Aurelius', authorEn: 'Marcus Aurelius', source: 'Meditations, Book 6', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'Waste no more time arguing what a good man should be. Be one.', author: 'Marcus Aurelius', authorEn: 'Marcus Aurelius', source: 'Meditations, Book 10', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'The only true wisdom is in knowing you know nothing.', author: 'Socrates', authorEn: 'Socrates', source: 'Apology (Plato)', createdAt: DateTime(2026, 1, 1)),
    Quote(text: 'It is not death that a man should fear, but he should fear never beginning to live.', author: 'Marcus Aurelius', authorEn: 'Marcus Aurelius', source: 'Meditations, Book 2', createdAt: DateTime(2026, 1, 1)),
  ];
}

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

  // 6/26 Brien 反馈: 删鼓励 (LLM 1.5b 推鼓励也输出完整新闻, 名言已够用, 各角色通用)
  // 只保留 getDailyQuote
  Future<Quote> getDailyEncouragement({
    required bool isEn,
    required Future<String> Function(String prompt) llmCall,
  }) async {
    // 6/26: fallback — 返回 quote 代替鼓励
    return getDailyQuote(isEn: isEn, llmCall: llmCall);
  }

  // 6/24 v3 亮点: 每日 1 句名言 (按小时选作者, 跟场景色配)
  // 跟鼓励不同: 鼓励基于今天读的内容, 名言是通用智慧
  // 失败兜底: 返回一句硬编码的名言
  Future<Quote> getDailyQuote({
    required bool isEn,
    required Future<String> Function(String prompt) llmCall,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dayKey = 'quote_v3_${now.year}-${now.month}-${now.day}'; // 7/15: v3 (Quote struct + JSON cache)
    final cachedJson = prefs.getString(dayKey);
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final q = Quote.fromJson(_decodeJson(cachedJson));
        if (q.text.isNotEmpty) return q;
      } catch (e) { debugPrint('[motivation_] err'); /* 下走重新生成 */ }
    }

    // 按时段选作者
    final hour = now.hour;
    final author = isEn
        ? (hour < 12 ? 'Marcus Aurelius' : hour < 18 ? 'Seneca' : 'Epictetus')
        : (hour < 12 ? '苏轼' : hour < 18 ? '李白' : '陶渊明');

    // 7/15: prompt 改 JSON
    final prompt = isEn
        ? 'Provide a short quote from $author.\n'
            'Return ONLY a JSON object with these exact fields:\n'
            '{"text": "<quote, max 25 words, no quotation marks>",'
            '"author": "$author",'
            '"source": "<where from, e.g. Meditations Book 5>",'
            '"textEn": null,'
            '"authorEn": "$author"}\n'
            'No explanation, no extra fields, no markdown.'
        : '提供 $author 一句诗或名言，不超过 25 字。\n'
            '仅返回 JSON 对象, 字段如下:\n'
            '{"text": "<名言原文, 不含引号>",'
            '"author": "$author",'
            '"source": "<出自哪首诗/书, 如 定风波>",'
            '"textEn": "<英译, 可选填 null>",'
            '"authorEn": "<作者英文名, 可选填 null>"}\n'
            '无解释, 无多余字段, 无 markdown。';

    Quote result;
    try {
      final raw = await llmCall(prompt);
      if (raw.isEmpty) throw 'empty';
      result = Quote.fromLlmJson(raw, now: now);
      // 兑底: text 空或太长
      if (result.text.isEmpty || result.text.length > 80) {
        throw 'parse_failed';
      }
      if (result.author.isEmpty) {
        result = Quote(
          text: result.text,
          author: author,
          source: result.source,
          textEn: result.textEn,
          authorEn: result.authorEn,
          createdAt: result.createdAt,
        );
      }
    } catch (e) {
      // 7/15: fallback 走 _QuotePool (27 条 pool 按天+小时索引)
      final pool = isEn ? _QuotePool.en : _QuotePool.zh;
      result = pool[(now.day + hour) % pool.length];
    }
    await prefs.setString(dayKey, _encodeJson(result.toJson()));
    return result;
  }

  // 6/29 10:59: 随机名言 — 8s LLM 慢, Brien 反馈 "一直转"
  // 修: 不调 LLM, 直接走 hardcoded 池 (7b 冷启动 12-20s, 完 5 名言池够用)
  // 未来 P2: 预热 LLM 后台写 cache, 按钮拿 cache
  // 7/15: 返回 Quote struct, 不用拼接字符串 (作者在 struct 字段里)
  Quote getRandomQuoteSync({
    required bool isEn,
  }) {
    final now = DateTime.now();
    final pool = isEn ? _QuotePool.en : _QuotePool.zh;
    return pool[now.second % pool.length];
  }

  // 7/15 保留 async 接口 (返回 Quote)
  Future<Quote> getRandomQuote({
    required bool isEn,
    Future<String> Function(String prompt)? llmCall,
  }) async {
    return getRandomQuoteSync(isEn: isEn);
  }

  // 7/15 helper: JSON 编解码 (避开 dart:convert 依赖)
  String _encodeJson(Map<String, dynamic> m) {
    final parts = m.entries
        .where((e) => e.value != null)
        .map((e) => '"${e.key}":${_encodeValue(e.value)}')
        .join(',');
    return '{$parts}';
  }
  String _encodeValue(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return '"${v.replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
    if (v is DateTime) return '"${v.toIso8601String()}"';
    return '"$v"';
  }
  Map<String, dynamic> _decodeJson(String s) {
    final m = RegExp(r'\{([\s\S]*)\}').firstMatch(s.trim());
    if (m == null) return {};
    final body = m.group(1)!;
    final result = <String, dynamic>{};
    final entryRe = RegExp(r'"([^"]+)"\s*:\s*("(?:[^"\\]|\\.)*"|null|\d+(?:\.\d+)?)');
    for (final em in entryRe.allMatches(body)) {
      final k = em.group(1)!;
      var v = em.group(2)!;
      if (v == 'null') {
        result[k] = null;
      } else if (v.startsWith('"') && v.endsWith('"')) {
        result[k] = v.substring(1, v.length - 1).replaceAll('\\"', '"').replaceAll('\\n', '\n');
      } else {
        result[k] = num.tryParse(v) ?? v;
      }
    }
    return result;
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
            'Trending among $source listeners this week. Summarized: the core idea challenge traditional views.',
            'Community pick: This has been bookmarked by thousands of $source users. Quick summary available.',
          ]
        : [
            '这段内容约5分钟可以消化，配合你的$source使用习惯。',
            '本周在$source圈子内很热，核心观点挑战传统认知。',
            '社区精选：已被数千$source用户收藏，这里有摘要。',
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