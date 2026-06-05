import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  final bool isElderlyMode;
  final String languageCode;
  const SearchScreen({
    super.key,
    this.isElderlyMode = false,
    this.languageCode = 'zh',
  });
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
    final isEn = widget.languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEn ? 'Search' : '搜索',
          style: TextStyle(fontSize: 18 * scale),
        ),
      ),
      body: Center(
        child: Text(isEn ? 'Search coming soon...' : '搜索功能即将上线...'),
      ),
    );
  }
}
