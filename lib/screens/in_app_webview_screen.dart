// 8/28 P65 沿 SOUL #137 真凶链 + 用户"给推荐但还在 7080 页面内"治本:
//   真凶: 之前 InAppWebViewScreen 用 webview_flutter, Web 平台 webview_flutter
//     不工作 (没装 webview_flutter_web), 即使装了大部分网站 X-Frame 拒绝
//     → 用户看到空白或失败, 体感"还在 7080 页面"
//   修: 平台分支
//   - Web (kIsWeb): 走 dart:html iframe 直接嵌入 (沿 iframe_video_view_web.dart 模式)
//     失败 → 显示 fallback + "外部浏览器打开"按钮
//   - Mobile (iOS/Android): 用 webview_flutter (原方案)
// 8/28 P65 沿 SOUL #169 不撒谎: iframe 也可能被 X-Frame-Options 拒
//   → 显示错误 UI + "外部浏览器打开"按钮, 不假装成功
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';
// 8/28 P65: 沿项目 iframe_video_view 模式, conditional import
import 'in_app_webview_screen_stub.dart'
    if (dart.library.html) 'in_app_webview_screen_web.dart' as impl;

class InAppWebViewScreen extends StatefulWidget {
  final String url;
  final String? title;
  const InAppWebViewScreen({super.key, required this.url, this.title});

  @override
  State<InAppWebViewScreen> createState() => _InAppWebViewScreenState();
}

class _InAppWebViewScreenState extends State<InAppWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 8/28 P65: Web 平台不创建 WebViewController (用 iframe)
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = null;
                });
              }
            },
            onWebResourceError: (err) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = err.description;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    } else {
      // 8/28 P65: Web 创建 dummy controller (用 iframe 时不走 WebView)
      _controller = WebViewController();
    }
  }

  /// 8/28 P65: 沿 SOUL #169 不撒谎 + SOUL #15: 用户主动选"新窗口" 跳转外部浏览器
  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '在原站阅读'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 8/28 P65: Web 平台走 iframe, Mobile 走 WebView
          if (kIsWeb)
            impl.buildIframeView(widget.url)
          else
            WebViewWidget(controller: _controller),
          if (_loading)
            const Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          // 8/28 P65 沿 SOUL #169: 失败时显示诊断 + 外部浏览器按钮 (沿 #103 不强行假装)
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      '页面嵌入失败',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error ?? '未知错误',
                      style: TextStyle(fontSize: 12, color: AppTheme.hintColor(context)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // 8/28 P65: 沿 SOUL #169 不撒谎 + #15: 沿 SOUL #103 治好不抢注意力
                    //   不再 showDialog, 直接给按钮用户主动选
                    ElevatedButton.icon(
                      onPressed: _openInBrowser,
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text('用浏览器打开'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.url,
                      style: TextStyle(fontSize: 11, color: AppTheme.hintColor(context)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}