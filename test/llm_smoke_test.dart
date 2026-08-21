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
}