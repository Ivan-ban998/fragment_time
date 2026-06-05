// lib/models/models.dart
// FragmentTime data models - consolidated rewrite (2026-06-04)
//
// Test file to verify: is /volume1/... the real NAS path that Brien sees via SSH?
// If this file shows up in Brien's SSH ls, then the write tool CAN write to the real path.

class AudioItem {
  final String id;
  final String title;
  final String author;
  final String coverUrl;
  final String audioUrl;
  final int durationSec;
  final String source;

  AudioItem({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.audioUrl,
    required this.durationSec,
    this.source = 'local',
  });

  factory AudioItem.fromJson(Map<String, dynamic> json) => AudioItem(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Untitled',
        author: json['author']?.toString() ?? 'Unknown',
        coverUrl: json['coverUrl']?.toString() ?? '',
        audioUrl: json['audioUrl']?.toString() ?? '',
        durationSec: (json['durationSec'] is int)
            ? json['durationSec']
            : int.tryParse(json['durationSec']?.toString() ?? '0') ?? 0,
        source: json['source']?.toString() ?? 'local',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'coverUrl': coverUrl,
        'audioUrl': audioUrl,
        'durationSec': durationSec,
        'source': source,
      };
}
