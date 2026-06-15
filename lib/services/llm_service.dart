// lib/services/llm_service.dart
// 2026-06-07 重写：接 6/2 4 个 user type (student/officeWorker/parent/senior)
// 调 MiniMax Chat Completions 或本地 Ollama

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
// 6/11 条件 import: web 才用 dart:html, native 不 import 避免编译失败
import 'web_host_stub.dart'
    if (dart.library.html) 'web_host_web.dart' as webhost;
import '../models/models.dart';

class LlmService {
  static const String _apiKey = String.fromEnvironment('LLM_API_KEY', defaultValue: '');
  static const String _remoteEndpoint = String.fromEnvironment('LLM_ENDPOINT', defaultValue: '');
  // 6/10 修复: web 直接走 LAN IP (Ollama CORS 开着的, 不用 proxy)
  // native (APK) 直连 NAS LAN IP
  // 前提: 手机/电脑跟 NAS 同 WiFi
  // 6/11 修复: web 端动态取 window.location.hostname, 避免 CNA 拦截跨 host 私网调用
  // (tailscale IP 100.89.x.x → 192.168.1.20 跨 host 跨私网会被 Chrome CNA 预检拒绝)
  static String get _ollamaHost {
    if (kIsWeb) {
      return webhost.currentHostname();
    }
    return '192.168.1.20';
  }
  static String get _ollamaEndpoint {
    return 'http://$_ollamaHost:11434/api/chat';
  }
  static const String _model = 'qwen2.5:7b';

  static Stream<String> generateStream({
    required UserType userType,
    required Scene scene,
    required String languageCode,
    required bool isInternational,
    String? prefSummary, // 6/13 6: 用户偏好摘要, nil = 不用
  }) async* {
    final systemPrompt = _buildSystemPrompt(userType, languageCode, prefSummary: prefSummary);
    final userPrompt = _buildUserPrompt(userType, scene, languageCode, isInternational);

    final useRemote = _apiKey.isNotEmpty && _remoteEndpoint.isNotEmpty;
    final endpoint = useRemote ? _remoteEndpoint : _ollamaEndpoint;
    final model = useRemote ? 'MiniMax-M2.7' : _model;

    Map<String, dynamic> body;
    Map<String, String> headers = {'Content-Type': 'application/json'};

    if (useRemote) {
      headers['Authorization'] = 'Bearer $_apiKey';
      body = {
        'model': model,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.8,
        'max_tokens': 800,
      };
    } else {
      body = {
        'model': model,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'options': {
          'temperature': 0.8,
          'num_predict': 500,
        },
      };
    }

    final req = http.Request('POST', Uri.parse(endpoint))
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    // 6/11 修复：30s → 120s，Ollama 7B 冷启动 27s + 出 800 token 70s，30s 不够
    final response = await http.Client().send(req).timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        throw LlmException('timeout 120s: $endpoint');
      },
    );
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw LlmException('HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}');
    }

    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      if (useRemote) {
        while (true) {
          final idx = buffer.indexOf('\n\n');
          if (idx < 0) break;
          final event = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);
          for (final line in event.split('\n')) {
            if (line.startsWith('data:')) {
              final data = line.substring(5).trim();
              if (data == '[DONE]') return;
              if (data.isEmpty) continue;
              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                final choices = json['choices'] as List?;
                if (choices == null || choices.isEmpty) continue;
                final delta = choices[0]['delta'] as Map?;
                final content = delta?['content'] as String?;
                if (content != null && content.isNotEmpty) yield content;
              } catch (_) {}
            }
          }
        }
      } else {
        while (true) {
          final nl = buffer.indexOf('\n');
          if (nl < 0) break;
          final line = buffer.substring(0, nl);
          buffer = buffer.substring(nl + 1);
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final message = json['message'] as Map?;
            final content = message?['content'] as String?;
            final thinking = message?['thinking'] as String?;
            if (content != null && content.isNotEmpty) yield content;
            else if (thinking != null && thinking.isNotEmpty) yield thinking;
            if (json['done'] == true) return;
          } catch (_) {}
        }
      }
    }
  }

  // 6/11 加: 原始 prompt 接口 - 给私教/回顾这种需要自定义 prompt 的场景
  static Future<String> generateRaw(String prompt, {bool isEn = true}) async {
    final useRemote = _apiKey.isNotEmpty && _remoteEndpoint.isNotEmpty;
    final endpoint = useRemote ? _remoteEndpoint : _ollamaEndpoint;
    final model = useRemote ? 'MiniMax-M2.7' : _model;

    final headers = {'Content-Type': 'application/json'};
    final body = useRemote
        ? {
            'model': model,
            'stream': false,
            'messages': [
              {'role': 'system', 'content': isEn ? 'You are a warm, concise coach.' : '你是温紫、简洁的 AI 教练。'},
              {'role': 'user', 'content': prompt},
            ],
            'temperature': 0.7,
            'max_tokens': 200,
          }
        : {
            'model': model,
            'stream': false,
            'messages': [
              {'role': 'system', 'content': isEn ? 'You are a warm, concise coach.' : '你是温紫、简洁的 AI 教练。'},
              {'role': 'user', 'content': prompt},
            ],
            'options': {'temperature': 0.7, 'num_predict': 200},
          };

    if (useRemote) headers['Authorization'] = 'Bearer $_apiKey';

    try {
      final response = await http
          .post(Uri.parse(endpoint), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        return isEn ? '(LLM unavailable)' : '（LLM 不可用）';
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final msg = json['message'] as Map<String, dynamic>?;
      return (msg?['content'] as String?) ?? (isEn ? '(no response)' : '（无回复）');
    } catch (e) {
      return isEn ? '(LLM error: $e)' : '（LLM 错误）';
    }
  }

  static String _buildSystemPrompt(UserType userType, String languageCode, {String? prefSummary}) {
    final isEn = languageCode == 'en';
    // 6/13 偏好拼进 system prompt
    final prefLine = (prefSummary != null && prefSummary.isNotEmpty)
        ? (isEn
            ? '\nUSER PREFERENCES (from past interactions): $prefSummary\nUse these to align tone and topic angle when relevant. Do NOT echo these back. Treat as soft signal only.'
            : '\n用户偏好（来自历史交互）：$prefSummary\n在适当时用这些对齐语气和角度。不要原样回传。作为软信号处理。')
        : '';
    // 6/7 宪法 §4 红线：儿童内容硬安全约束
    final childGuard = userType == UserType.child
        ? (isEn
            ? ' CHILD SAFETY (HARD RULE): audience is 6-12 year olds. '
                'Use simple words, short sentences, warm tone, fun examples. '
                'STRICTLY NO: violence, scary content, romantic/sexual content, '
                'alcohol/tobacco/drugs, dangerous challenges, hate speech, '
                'complex medical/financial advice, political persuasion, or anything a parent would find inappropriate. '
                'If the topic seems risky, redirect to a safe educational angle. '
            : ' 【儿童安全硬约束】读者是 6-12 岁儿童。'
                '用简单词汇、短句、温和语气、有趣例子。'
                '严格禁止：暴力、恐怖、恋爱/性内容、烟酒/药品/毒品、危险挑战、仇恨言论、'
                '复杂医疗/金融建议、政治煽动、或任何家长会觉得不合适的内容。'
                '如话题本身有风险，请转向安全的教育角度。'
          )
        : '';
    if (isEn) {
      return 'You are a friendly, concise content writer for the FragmentTime app. '
          'Write in clear, accessible English. Keep responses around 250 words. '
          'Audience: ${userType.name}. No emojis.$childGuard '
          'CRITICAL FORMAT: Start with a ONE-LINE summary (under 30 words) wrapped in 【】 brackets. '
          'Then a blank line. Then the full ~250-word body. The summary lets users decide if they want to read.$prefLine';
    }
    return '你是一位擅长用简洁语言为碎片时间写作的内容创作者。'
        '用清晰自然的中文，控制在 250 字左右。'
        '读者：${_userTypeZh(userType)}。不用 emoji 装饰。$childGuard'
        '**重要格式**：先写一行【30字以内的精要总结】（包裹在【】里），空一行后写 ~250 字正文。'
        '精要放在最前，让用户快速判断是否要读。$prefLine';
  }

  static String _buildUserPrompt(UserType userType, Scene scene, String languageCode, bool isInternational) {
    final isEn = languageCode == 'en';
    if (isEn) return _enPrompt(userType, scene);
    return _zhPrompt(userType, scene, isInternational);
  }

  static String _zhPrompt(UserType u, Scene s, bool intl) {
    final sceneName = _sceneZh(s);
    final userDesc = _userTypeDescZh(u);
    final region = intl ? '国际视角' : '国内视角';
    final key = '${u.name}_${s.name}';
    // 6/7 宪法 §4：儿童提示语开头加"适龄 6-12 岁"
    final childHint = u == UserType.child ? '【适龄 6-12 岁】' : '';
    switch (key) {
      // 学生
      case 'student_learn':
        return '面向学生的趣味知识点。$region。一个能 5 分钟读完的硬核小知识，250 字。$userDesc。';
      case 'student_listen':
        return '面向学生的科普音频。$region。3 个今日奇闻/前沿，250 字。$userDesc。';
      case 'student_relax':
        return '面向学生的"5 分钟放空"练习。$region。一段引导放松的描述，250 字。$userDesc。';
      case 'student_workout':
        return '面向学生的课间 5 分钟。$region。5 个 1 分钟动作，250 字。$userDesc。';
      // 上班族
      case 'officeWorker_learn':
        return '面向上班族的"摸鱼时间"学点东西。$region。一个 5 分钟能读完的行业/方法论小点，250 字。$userDesc。';
      case 'officeWorker_listen':
        return '面向上班族的通勤要闻。$region。3 条 5 分钟能听完的短新闻，250 字。$userDesc。';
      case 'officeWorker_relax':
        return '面向上班族的午休心理陪伴。$region。一段 5 分钟正念 + 一句暖话，250 字。$userDesc。';
      case 'officeWorker_workout':
        return '面向上班族的工位微运动。$region。5 个 1 分钟动作，250 字。$userDesc。';
      // 创业者
      case 'entrepreneur_learn':
        return '面向创业者的商业洞察。$region。一个 5 分钟能读完的商业趋势/管理决策/案例分析，250 字。$userDesc。';
      case 'entrepreneur_listen':
        return '面向创业者的今日要闻。$region。3 条 5 分钟商业/科技简讯，250 字。$userDesc。';
      case 'entrepreneur_relax':
        return '面向创业者的高压放松。$region。一段 5 分钟正念 + 决策疲劳恢复，250 字。$userDesc。';
      case 'entrepreneur_workout':
        return '面向创业者的碎片化运动。$region。5 个 1 分钟动作（出差/会议间隙可做），250 字。$userDesc。';
      // 宝爸宝妈
      case 'parent_learn':
        return '面向宝爸宝妈的亲子教育/时间管理小贴士。$region。1 个 5 分钟可读完的方法论，250 字。$userDesc。';
      case 'parent_listen':
        return '面向宝爸宝妈的轻松一刻。$region。3 条短资讯或暖心片段，250 字。$userDesc。';
      case 'parent_relax':
        return '面向宝爸宝妈的"喘口气"心理陪伴。$region。一段温柔的自我对话 + 呼吸练习，250 字。$userDesc。';
      case 'parent_workout':
        return '面向宝爸宝妈的"边带娃边动"运动。$region。5 个 1 分钟小动作，250 字。$userDesc。';
      // 退休人群
      case 'senior_learn':
        return '面向退休人群的健康知识小课堂。$region。讲一个 5 分钟能读完的养生/医疗常识点，250 字左右。$userDesc。';
      case 'senior_listen':
        return '面向退休人群的今日要闻播报。$region。挑 3 条简讯，温和语气，250 字左右。$userDesc。';
      case 'senior_relax':
        return '面向退休人群的正念呼吸引导。$region。5 分钟能做完的练习，250 字。$userDesc。';
      case 'senior_workout':
        return '面向退休人群的温和拉伸。$region。5 个动作，每个 1 句话，250 字。$userDesc。';
      // 6/7 儿童（6-12 岁宪法 §4 必做）
      case 'child_learn':
        return '$childHint 面向 6-12 岁儿童的趣味小知识。$region。一个 5 分钟能读完的小知识，250 字。$userDesc。避免任何家长觉得不合适的话题。';
      case 'child_listen':
        return '$childHint 面向 6-12 岁儿童的睡前小故事或奇闻。$region。一个 5 分钟的温馨小故事，250 字。$userDesc。内容必须适合儿童，温馨安全。';
      case 'child_relax':
        return '$childHint 面向 6-12 岁儿童的"放空"引导。$region。一段温和的呼吸 + 想象练习，250 字。$userDesc。语气温柔、像讲故事。';
      case 'child_workout':
        return '$childHint 面向 6-12 岁儿童的课间小游戏。$region。5 个 1 分钟安全动作，250 字。$userDesc。动作要安全有趣、不能有危险动作。';
      default:
        return '$childHint 面向${_userTypeZh(u)}的${sceneName}内容。$region。5 分钟可读完，250 字。$userDesc。';
    }
  }

  static String _enPrompt(UserType u, Scene s) {
    final childHint = u == UserType.child ? '【Age 6-12, safe content only】' : '';
    return '$childHint Write a 5-minute ${_sceneEn(s)} piece for ${u.name} users. '
        'Around 250 words. Clear, friendly English. No emojis. International perspective.';
  }

  static String _userTypeDescZh(UserType u) {
    switch (u) {
      case UserType.student: return '读者是学生，关注学业、考试、知识';
      case UserType.officeWorker: return '读者是上班族，关注职场技能、通勤效率、深度内容';
      case UserType.entrepreneur: return '读者是创业者或企业主，关注商业趋势、管理决策、行业动态';
      case UserType.parent: return '读者是宝爸宝妈，时间碎片化，关注亲子教育、家庭成长';
      case UserType.senior: return '读者是退休人群，关注养生健康、兴趣爱好、慢节奏生活';
      case UserType.child: return '读者是儿童，6-12岁，需要有趣的故事和科普，语言简单生动';
    }
  }

  static String _userTypeZh(UserType u) {
    switch (u) {
      case UserType.student: return '学生';
      case UserType.officeWorker: return '上班族';
      case UserType.entrepreneur: return '创业者';
      case UserType.parent: return '宝爸宝妈';
      case UserType.senior: return '退休人群';
      case UserType.child: return '儿童';
    }
  }

  static String _sceneZh(Scene s) {
    switch (s) {
      case Scene.learn: return '学习';
      case Scene.listen: return '听';
      case Scene.relax: return '放松';
      case Scene.workout: return '运动';
    }
  }

  static String _sceneEn(Scene s) {
    switch (s) {
      case Scene.learn: return 'learn';
      case Scene.listen: return 'listen';
      case Scene.workout: return 'workout';
      case Scene.relax: return 'relax';
    }
  }

  // 6/11 B2: AI 出题 (非流式, 一次性 JSON 返回)
  // 测一测面板点开时调一次, 失败让 UI 重试
  static const _quizSystemPrompt = '''
你是一个小学老师。根据用户给的内容, 出 3 道理解题测一测。

【严格要求】
- 中文 4 个选项 A B C D, 选 1
- 答案随机位置, 不能总是 A
- 每题附一行「答案: X」+ 一行「解析: ...」
- 输出必须是合法 JSON, 不要任何额外文字

【格式】
{
  "questions": [
    {"question": "...", "choices": ["A...", "B...", "C...", "D..."], "correctIndex": 0-3, "explanation": "..."},
    ...(共 3 题)
  ]
}
''';

  static Future<List<QuizQuestion>> generateQuiz({
    required String title,
    required String description,
    String languageCode = 'zh',
  }) async {
    final useRemote = _apiKey.isNotEmpty && _remoteEndpoint.isNotEmpty;
    final endpoint = useRemote ? _remoteEndpoint : _ollamaEndpoint;
    final model = useRemote ? 'MiniMax-M2.7' : _model;

    final userMsg = languageCode == 'en'
        ? 'Title: $title\n\nContent: $description\n\nMake 3 multiple choice questions in English.'
        : '标题: $title\n\n内容: $description\n\n出 3 道中文选择题。';

    final body = useRemote
        ? {
            'model': model,
            'stream': false,
            'messages': [
              {'role': 'system', 'content': _quizSystemPrompt},
              {'role': 'user', 'content': userMsg},
            ],
            'temperature': 0.6,
            'max_tokens': 800,
          }
        : {
            'model': model,
            'stream': false,
            'messages': [
              {'role': 'system', 'content': _quizSystemPrompt},
              {'role': 'user', 'content': userMsg},
            ],
            'options': {'temperature': 0.6, 'num_predict': 500},
          };

    final headers = useRemote
        ? {'Content-Type': 'application/json', 'Authorization': 'Bearer $_apiKey'}
        : {'Content-Type': 'application/json'};

    final response = await http.post(
      Uri.parse(endpoint),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 120), onTimeout: () {
      throw LlmException('timeout 120s: $endpoint');
    });

    if (response.statusCode != 200) {
      throw LlmException('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    // Ollama 格式: { "message": { "content": "..." } }
    // OpenAI 格式: { "choices": [ { "message": { "content": "..." } } ] }
    String content;
    if (data['message'] != null) {
      content = (data['message'] as Map)['content'] as String;
    } else if ((data['choices'] as List?)?.isNotEmpty == true) {
      content = ((data['choices'] as List).first as Map)['message']['content'] as String;
    } else {
      throw LlmException('no content in response');
    }

    // 6/11: LLM 有时会包 ```json ... ```, 剥掉
    final cleaned = content
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*$', multiLine: true), '')
        .trim();

    final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    final list = (parsed['questions'] as List?) ?? [];
    return list
        .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class LlmException implements Exception {
  final String message;
  LlmException(this.message);
  @override
  String toString() => 'LlmException: $message';
}

// 6/11 B2: AI 出题
// 根据内容生成 3 道选择题, JSON 返回
// 调用方: content_reader_screen 测一测面板
// 失败回退: 抛 LlmException, UI 显示「出题中...」 重试

/// 6/7 Brien: 从 LLM 流式输出里解出【精要】和【正文】。
/// 格式：AI 被 prompt 写为「【精要】\n\n正文」或「先精要后正文」。
/// 解析规则：找到第一个【...】作为精要，其余为正文。
class LlmSummary {
  final String summary;
  final String body;
  const LlmSummary({required this.summary, required this.body});

  static LlmSummary parse(String full) {
    final m = RegExp(r'【(.+?)】').firstMatch(full);
    if (m == null) {
      return LlmSummary(summary: '', body: full);
    }
    final summary = m.group(1)!.trim();
    final body = full.replaceFirst(m.group(0)!, '').trim();
    return LlmSummary(summary: summary, body: body);
  }

  static LlmSummary empty() => const LlmSummary(summary: '', body: '');
}
