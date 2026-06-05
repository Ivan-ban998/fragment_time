import 'package:just_audio/just_audio.dart';

class AudioPlayService {
  final AudioPlayer _player = AudioPlayer();
  String? _currentUrl;
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;
  String? get currentUrl => _currentUrl;

  Future<void> play(String url) async {
    _currentUrl = url;
    try {
      await _player.setUrl(url);
      await _player.play();
      _isPlaying = true;
    } catch (e) {
      _isPlaying = false;
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    _currentUrl = null;
  }

  void dispose() {
    _player.dispose();
  }
}
