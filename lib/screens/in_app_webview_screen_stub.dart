// 8/28 P65: in-app webview stub (iOS/Android)
//   实际 webview_flutter 在 mobile 上工作, 直接返空 Widget
//   (主 in_app_webview_screen.dart 在 mobile 走 WebViewWidget 不走 stub)
import 'package:flutter/material.dart';

Widget buildIframeView(String url) {
  // 8/28 P65: Mobile 平台不调用此 stub (主 dart 用 kIsWeb 分支)
  return const SizedBox.shrink();
}