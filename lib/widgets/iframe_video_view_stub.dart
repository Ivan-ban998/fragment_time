import 'package:flutter/material.dart';

/// Non-web fallback
Widget buildIframeWidget(String embedUrl) {
  return Container(
    color: Colors.black,
    child: const Center(
      child: Icon(Icons.play_circle_outline, color: Colors.white, size: 48),
    ),
  );
}
