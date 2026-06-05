import 'package:flutter/material.dart';
import '../models/models.dart';

class ContentScreen extends StatefulWidget {
  final UserType userType;
  final Scene scene;
  final bool isInternational;
  final bool isElderlyMode;
  final String languageCode;
  const ContentScreen({
    super.key,
    required this.userType,
    required this.scene,
    this.isInternational = false,
    this.isElderlyMode = false,
    this.languageCode = 'zh',
  });
  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen> {
  @override
  Widget build(BuildContext context) {
    final scale = widget.isElderlyMode ? 1.3 : 1.0;
    final isEn = widget.languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.scene.icon} ${isEn ? widget.scene.name : widget.scene.title}',
          style: TextStyle(fontSize: 18 * scale),
        ),
      ),
      body: Center(
        child: Text(
          isEn ? 'Content screen' : '内容页建设中...',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
