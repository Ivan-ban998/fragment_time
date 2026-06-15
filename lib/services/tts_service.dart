import 'dart:async';
import 'package:flutter/foundation.dart';
import 'tts_service_stub.dart'
    if (dart.library.html) 'tts_service_web.dart' as impl;

/// TTS 服务：web 用浏览器 SpeechSynthesis、原生 fallback
/// 6/7 修复：之前是 print 假实现，现在 web 真调 speechSynthesis
class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  bool _isSpeaking = false;
  bool _isPaused = false;
  String _currentText = '';

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
    if (kIsWeb) {
      impl.stopWeb();
    }
  }
}
