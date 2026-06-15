class PodcastEpisode {
  final String title;
  final String description;
  final String audioUrl;
  final String duration;
  final DateTime? publishDate;

  const PodcastEpisode({
    required this.title,
    required this.description,
    required this.audioUrl,
    required this.duration,
    this.publishDate,
  });
}

class PodcastChannel {
  final String name;
  final String artist;
  final String artworkUrl;
  final String feedUrl;
  final List<PodcastEpisode> episodes;

  const PodcastChannel({
    required this.name,
    required this.artist,
    required this.artworkUrl,
    required this.feedUrl,
    required this.episodes,
  });
}