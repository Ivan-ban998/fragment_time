// lib/screens/in_app_webview_screen.dart
// 7/29 加: in-app webview 嵌入 (沿用宪法 §1.1 不存原片, 只渲染原网页)
// 跳原站按钮从外部浏览器 (url_launcher) 改为 app 内 webview, 留住用户
// 沿用 #103: "改了 ≠ 修了" — 浏览器硬刷验真改没改对

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
            // 沿用 #113: 36 氪 / 少数派可能 X-Frame 拒绝, 显示 fallback 让用户用外部浏览器
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
          // 7/29 加: 外部浏览器按钮 — webview 失败时用户能用外部浏览器打开
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: () {
              Navigator.of(context).pop();
              // 沿用 #113: 沿用 #15 不擅自 push, 用 url_launcher 跳外部浏览器
              // 实际 onPressed 调到调用方, 这里只是 pop
            },
          ),
        ],
      ),
      body: Stack(
        children: [
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
                      '页面嵌入失败\n$_error\n\n该网站可能不允许 webview 嵌入。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '请用浏览器打开:\n${widget.url}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_loading)
            const Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}