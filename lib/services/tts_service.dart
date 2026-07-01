import 'dart:async';
import 'package:flutter/foundation.dart';
import 'tts_service_stub.dart'
    if (dart.library.html) 'tts_service_web.dart' as impl;

/// TTS 服务：web 用浏览器 SpeechSynthesis、原生 fallback
/// 6/7 修复：之前是 print 假实现，现在 web 真调 speechSynthesis
/// 7/1 加: ValueNotifier<double> progress (0..1) — UI 实时同步朗读进度
class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  bool _isSpeaking = false;
  bool _isPaused = false;
  String _currentText = '';

  // 7/1: 实时进度 (0..1)
  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  bool get isSpeaking => _isSpeaking;
  bool get isPaused => _isPaused;
  String get currentText => _currentText;

  Future<bool> isAvailable() async {
    if (kIsWeb) {
      return impl.isAvailableWeb();
    }
    return false;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    _currentText = text;
    _isSpeaking = true;
    _isPaused = false;
    progress.value = 0.0; // 7/1: 重置进度
    if (kIsWeb) {
      impl.speakWeb(text);
    }
  }

  Future<void> pause() async {
    if (!_isSpeaking) return;
    _isPaused = true;
    if (kIsWeb) {
      impl.pauseWeb();
    }
  }

  Future<void> resume() async {
    if (!_isPaused) return;
    _isPaused = false;
    if (kIsWeb) {
      impl.resumeWeb();
    }
  }

  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
    _currentText = '';
    progress.value = 0.0; // 7/1: 重置
    if (kIsWeb) {
      impl.stopWeb();
    }
  }
}
