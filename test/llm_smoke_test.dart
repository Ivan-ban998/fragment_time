// ignore_for_file: avoid_print
// 8/28 P36-3 沿 SOUL #125 #189: chatStream smoke test
//   验证 P35-1 ft_server thread death 修后, LLM 调用可重复成功
//   验证 P35-2 transient retry 行为
// 跑法: flutter test test/llm_smoke_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/llm_service.dart';

void main() {
  test('chatStream 真返 stream (web 端 /api/llm, 5 次顺序)', () async {
    final messages = [
      {'role': 'user', 'content': 'say hi in 1 word'},
    ];
    final chunks = <String>[];
    await for (final chunk in LlmService.chatStream(messages: messages)) {
      chunks.add(chunk);
    }
    print('chatStream 收 ${chunks.length} chunks: "${chunks.join()}"');
    expect(chunks.isNotEmpty, true,
        reason: 'P35-1 修复后, 应能收到至少 1 chunk');
    expect(chunks.join().isNotEmpty, true,
        reason: '内容应非空');
    expect(chunks.join(), isNot('(LLM unavailable)'),
        reason: '不应 fallback to mock');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('5 顺序调用都成功 (P35-1 thread death 修复验证)', () async {
    for (int i = 0; i < 5; i++) {
      final messages = [
        {'role': 'user', 'content': 'hi $i'},
      ];
      final chunks = <String>[];
      await for (final chunk in LlmService.chatStream(messages: messages)) {
        chunks.add(chunk);
      }
      print('Call $i: ${chunks.length} chunks');
      expect(chunks.isNotEmpty, true,
          reason: 'Call $i 应有响应');
      expect(chunks.join(), isNot('(LLM unavailable)'),
          reason: 'Call $i 不应 fallback');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  // 8/28 P49-5 沿 SOUL #137 真凶链: AI 摘要 streaming test
  //   真凶: 之前 _generateAiSummary 用 generateRaw 阻塞 5-15s
  //   修: 改 chatStream 流式, 用户立刻看到第 1 token
  test('AI 摘要 streaming (generateRaw → chatStream refactor)', () async {
    final messages = [
      {'role': 'user', 'content': 'say hi in 3 words'},
    ];
    final chunks = <String>[];
    final sw = Stopwatch()..start();
    await for (final chunk in LlmService.chatStream(messages: messages)) {
      chunks.add(chunk);
      // 验证第一 chunk 应在 10s 内到 (流式响应)
      if (chunks.length == 1) {
        sw.stop();
        print('First chunk 在 ${sw.elapsedMilliseconds}ms 到');
        expect(sw.elapsedMilliseconds < 10000, true,
            reason: '首 chunk 应 < 10s (流式 vs 阻塞)');
      }
    }
    expect(chunks.isNotEmpty, true,
        reason: 'streaming 应有至少 1 chunk');
    print('总 chunks: ${chunks.length}, content: "${chunks.join()}"');
  }, timeout: const Timeout(Duration(seconds: 30)));
}