import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import 'iframe_video_view_stub.dart'
    if (dart.library.html) 'iframe_video_view_web.dart' as impl;

/// 6/7 Brien 多种形式诉求 + §1.1 零服务器：
/// 视频小窗 = 官方 embed iframe（B 站/YouTube 自己承载视频，我们 0 成本）

/// 构造 embed URL。返回 null = 不是视频 / 平台不支持
String? buildVideoEmbedUrl(ContentItem item) {
  if (item.contentType != ContentType.video) return null;
  if (item.videoId == null || item.videoPlatform == null) {
    // 6/10 修: videoId 缺失时退到 externalUrl (B站搜索页/YouTube watch) - 弹 dialog 还能动
    if (item.externalUrl != null && item.externalUrl!.isNotEmpty) {
      return item.externalUrl!;
    }
    return null;
  }
  return item.videoPlatform!.buildEmbedUrl(item.videoId!);
}

class IframeVideoView extends StatefulWidget {
  final String embedUrl;
  final double aspectRatio;
  final String? externalUrl; // 6/9 修：mobile 跳原站

  const IframeVideoView({
    super.key,
    required this.embedUrl,
    this.aspectRatio = 16 / 9,
    this.externalUrl,
  });

  @override
  State<IframeVideoView> createState() => _IframeVideoViewState();
}

class _IframeVideoViewState extends State<IframeVideoView> {
  @override
  void initState() {
    super.initState();
    // 6/9 修：mobile 平台  自动跳原站（不显示 placeholder 误导）
    if (!kIsWeb && widget.externalUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final uri = Uri.parse(widget.externalUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return _buildMobileLanding();
    }
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: impl.buildIframeWidget(widget.embedUrl),
    );
  }

  Widget _buildMobileLanding() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.open_in_browser, color: Colors.white, size: 48),
            const SizedBox(height: 8),
            Text(
              'Opening in browser...',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
