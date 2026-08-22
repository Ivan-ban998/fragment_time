// 8/28 P65: Web 平台 in-app webview iframe 嵌入 (沿 SOUL #137 治本)
//   真凶: 之前 webview_flutter 在 Web 不工作 (没装 webview_flutter_web)
//   修: 用 dart:html iframe + HtmlElementView 直接嵌入, 沿 iframe_video_view_web.dart 模式
// 8/28 P65 沿 SOUL #169 不撒谎: 大部分网站 X-Frame 拒绝, 会失败
//   → 主屏幕检测 onError + 显示 fallback + 外部浏览器按钮
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';

/// 8/28 P65: Web 平台 - iframe 嵌入视图
///   如果 X-Frame-Options 拒绝, iframe 显示空白
///   用户可用 AppBar 的"用浏览器打开"按钮跳外部
Widget buildIframeView(String url) {
  // 8/28 P65: 用 platformViewRegistry 注册 iframe view factory (沿 iframe_video_view_web.dart)
  final viewType = 'in-app-webview-${url.hashCode}';
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.minHeight = '400px'
        ..allow = 'autoplay; encrypted-media; fullscreen'
        ..allowFullscreen = true
        // 8/28 P65: 不设 sandbox 让更多网站能加载
        ..referrerPolicy = 'no-referrer';
      return iframe;
    },
  );
  return HtmlElementView(viewType: viewType);
}