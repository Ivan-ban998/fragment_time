// ignore_for_file: avoid_print
// 8/28 P37-11 沿 SOUL #125 #189: LLM cache 单元测试
//   验证 LlmService.clearLlmCache + llmCacheHits/Misses 计数
// 跑法: flutter test test/llm_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/services/llm_service.dart';

void main() {
  test('clearLlmCache 重置 hit/miss 计数到 0', () {
    LlmService.clearLlmCache();
    expect(LlmService.llmCacheHits, 0);
    expect(LlmService.llmCacheMisses, 0);
  });

  test('cache hit rate getter (0 hits, 0 misses → 0%)', () {
    LlmService.clearLlmCache();
    // 0 hits, 0 misses → 0.0
    final rate = (LlmService.llmCacheHits + LlmService.llmCacheMisses) == 0
        ? 0.0
        : LlmService.llmCacheHits / (LlmService.llmCacheHits + LlmService.llmCacheMisses);
    expect(rate, 0.0);
  });
}