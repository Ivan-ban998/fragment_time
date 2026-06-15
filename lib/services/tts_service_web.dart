// Web: 真调 window.speechSynthesis
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'analytics_service.dart';

bool isAvailableWeb() {
  return html.window.speechSynthesis != null;
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
  // 6/8 埋点
  AnalyticsService.instance.track(
    AnalyticsService.EVT_TTS_PLAY,
    props: {'len': '${text.length}'},
  );
  html.window.speechSynthesis!.speak(utter);
}

void pauseWeb() {
  if (html.window.speechSynthesis == null) return;
  html.window.speechSynthesis!.pause();
}

void resumeWeb() {
  if (html.window.speechSynthesis == null) return;
  html.window.speechSynthesis!.resume();
}

void stopWeb() {
  if (html.window.speechSynthesis == null) return;
  html.window.speechSynthesis!.cancel();
}
