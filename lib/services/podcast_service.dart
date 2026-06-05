import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RssFeed {
  final String title;
  final List<RssItem> items;
  RssFeed({required this.title, required this.items});
}

class RssItem {
  final String title;
  final String description;
  final String? audioUrl;
  final String? link;
  final DateTime? pubDate;
  RssItem({
    required this.title,
    required this.description,
    this.audioUrl,
    this.link,
    this.pubDate,
  });
}

class PodcastService {
  final http.Client _client = http.Client();

  Future<RssFeed?> fetchFeed(String rssUrl) async {
    try {
      final response = await _client.get(Uri.parse(rssUrl));
      if (response.statusCode != 200) return null;
      return RssFeed(title: 'Unknown', items: []);
    } catch (e) {
      return null;
    }
  }

  Future<List<Podcast>> searchPodcasts(String query) async {
    return [];
  }

  void dispose() {
    _client.close();
  }
}

class Podcast {
  final String id;
  final String title;
  final String? imageUrl;
  final String? rssUrl;
  Podcast({
    required this.id,
    required this.title,
    this.imageUrl,
    this.rssUrl,
  });
}
