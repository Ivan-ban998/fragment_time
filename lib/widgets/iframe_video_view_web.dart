import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// Web: register iframe via platformViewRegistry, return HtmlElementView
Widget buildIframeWidget(String embedUrl) {
  final viewType = 'iframe-${embedUrl.hashCode}';
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = embedUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
      return iframe;
    },
  );
  return HtmlElementView(viewType: viewType);
}
