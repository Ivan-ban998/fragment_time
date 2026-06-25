import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// Web: 直接嵌 <iframe src=externalUrl>
/// 6/25 A: 站内直接读全文 (点击展开, sandbox 限制脚本, 失败兜底走外链)
Widget buildInlineReadWidget(String url) {
  final viewType = 'inlineread-${url.hashCode}';
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'autoplay; encrypted-media'
        ..setAttribute('sandbox', 'allow-same-origin allow-scripts')
        ..setAttribute('referrerpolicy', 'no-referrer');
      return iframe;
    },
  );
  return HtmlElementView(viewType: viewType);
}