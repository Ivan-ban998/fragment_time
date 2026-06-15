import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/models.dart';

class AudioPlayService {
  static final AudioPlayService _instance = AudioPlayService._();
  factory AudioPlayService() => _instance;
  AudioPlayService._();

  final AudioPlayer _player = AudioPlayer();
  ContentItem? _currentItem;

  Future<void> play(ContentItem item) async {
    if (item.audioUrl == null || item.audioUrl!.isEmpty) return;
    _currentItem = item;
    await _player.setUrl(item.audioUrl!);
    await _player.play();
  }

  Future<void> pause() async => _player.pause();
  Future<void> resume() async => _player.play();
  Future<void> stop() async {
    await _player.stop();
    _currentItem = null;
  }
  Future<void> seek(Duration pos) async => _player.seek(pos);

  ContentItem? get currentItem => _currentItem;
  bool get isPlaying => _player.playing;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
}
