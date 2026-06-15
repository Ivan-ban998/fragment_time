// lib/services/podcast_service.dart
// 去外部依赖，本地 stub

import '../models/models.dart';

class PodcastService {
  Future<List<ContentItem>> fetchEpisodes(UserType userType) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return [];
  }
}
