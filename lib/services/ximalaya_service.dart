import 'package:just_audio/just_audio.dart';

class XimalayaService {
  final AudioPlayer _player = AudioPlayer();

  Future<List<dynamic>> getRecommendations() async {
    return [];
  }

  Future<List<dynamic>> search(String query) async {
    return [];
  }

  void dispose() {
    _player.dispose();
  }
}
