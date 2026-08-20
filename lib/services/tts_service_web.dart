// Web: 真调 window.speechSynthesis
// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'analytics_service.dart';
import 'tts_service.dart';

bool isAvailableWeb() {
  return html.window.speechSynthesis != null;
}

Timer? _progressTimer;

void _resetProgress() {
  _progressTimer?.cancel();
  TtsService.progress.value = 0.0;
}

void _startProgress(String text) {
  // 7/1: 估读完秒数 (1.0 rate, 100ms / 字), 计算 interval step
  if (text.isEmpty) return;
  final estSeconds = (text.length * 0.18).clamp(3, 300);
  _progressTimer?.cancel();
  final step = 0.2 / estSeconds; // 200ms 推进 1 / estSeconds
  var cur = TtsService.progress.value;
  _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
    cur += step;
    if (cur >= 1.0) { cur = 1.0; t.cancel(); }
    TtsService.progress.value = cur;
  });
}

void _finishProgress() {
  _progressTimer?.cancel();
  TtsService.progress.value = 1.0;
}

void speakWeb(String text) {
  if (html.window.speechSynthesis == null) return;
  // 取消之前任何朗读
  html.window.speechSynthesis!.cancel();
  // 创建 utterance
  final utter = html.SpeechSynthesisUtterance(text);
  utter.lang = 'zh-CN';
  utter.rate = 1.0;
  utter.pitch = 1.0;
  utter.volume = 1.0;

  // 7/1: 用 addEventListener 接 start/end/error (dart:html 拿不到 onStart 的 Stream API, fallback listener)
  // 8/16 修 (沿 SOUL #103 真改没改对 第 N+21 次): onend 后清状态
  //   真凶: 之前 onend 只 _finishProgress (重置 progress), 没清 _isSpeaking / _isPaused
  //     → 用户听完后调 _isSpeaking 还是 true, pause() / stop() 等返回 false
  //     → 重新点播放按钮没反应
  //   修: onend + onerror 都清 _isSpeaking + _isPaused
  utter.addEventListener('start', (html.Event _) {
    _startProgress(text);
  });
  utter.addEventListener('end', (html.Event _) {
    _finishProgress();
    TtsService.instance.markFinished();
  });
  utter.addEventListener('error', (html.Event _) {
    _resetProgress();
    TtsService.instance.markFinished();
  });
  // 8/16 治本 (沿 SOUL #103): utterance 是 1 次性, GC 自动回收 listener

  // 6/8 埋点
  AnalyticsService.instance.track(
    AnalyticsService.evtTtsPlay,
    props: {'len': '${text.length}'},
  );
  html.window.speechSynthesis!.speak(utter);
}

void pauseWeb() {
  _progressTimer?.cancel();
  if (html.window.speechSynthesis == null) return;
  html.window.speechSynthesis!.pause();
}

void resumeWeb() {
  if (html.window.speechSynthesis == null) return;
  html.window.speechSynthesis!.resume();
}

void stopWeb() {
  _resetProgress();
  if (html.window.speechSynthesis == null) return;
  html.window.speechSynthesis!.cancel();
}
