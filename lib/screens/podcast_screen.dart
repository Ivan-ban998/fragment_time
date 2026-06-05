import 'package:flutter/material.dart';

class PodcastScreen extends StatelessWidget {
  final bool isElderlyMode;
  final String languageCode;

  const PodcastScreen({
    super.key,
    this.isElderlyMode = false,
    this.languageCode = 'zh',
  });

  @override
  Widget build(BuildContext context) {
    final isEn = languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Podcasts' : '播客'),
      ),
      body: Center(
        child: Text(
          isEn ? 'Podcast search coming soon...' : '播客搜索功能即将上线...',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
