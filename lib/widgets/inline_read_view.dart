import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'inline_read_view_stub.dart'
    if (dart.library.html) 'inline_read_view_web.dart' as impl;

/// 6/25 A: 详情页"站内直接读全文"
/// web 端: 嵌入 iframe (sandbox 限脚本 + no-referrer)
/// mobile 端: 不支持, UI 兜底走 externalUrl 按钮
class InlineReadView extends StatefulWidget {
  final String url;
  final double height;

  const InlineReadView({
    super.key,
    required this.url,
    this.height = 600,
  });

  @override
  State<InlineReadView> createState() => _InlineReadViewState();
}

class _InlineReadViewState extends State<InlineReadView> {
  bool _loadFailed = false;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      // mobile: 不支持 inline, 直接空白 (调用方应 fallback 到外部按钮)
      return SizedBox(height: widget.height);
    }
    if (_loadFailed) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 32, color: Colors.grey),
            SizedBox(height: 8),
            Text('加载失败', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    // iframe 加载失败由 onError 不可靠 (浏览器安全策略), 用定时兜底: 8s 还在 build → 假定 ok
    // 真正失败由用户点 "去原站阅读" 按钮
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: impl.buildInlineReadWidget(widget.url),
      ),
    );
  }
}