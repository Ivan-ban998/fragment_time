// 6/9 stub for non-web platforms (Android / iOS / Desktop)
// 真实 share 走 share_service_web.dart（web only via conditional import）
import 'package:flutter/material.dart';
import '../models/models.dart';

class ShareCardResult {
  final String? downloadUrl;
  final String error;
  const ShareCardResult({this.downloadUrl, this.error = ''});
}

class ShareService {
  static final ShareService instance = ShareService._();
  ShareService._();

  Future<ShareCardResult> generateShareCard({
    required String title,
    required String description,
    required String source,
    required bool isEn,
  }) async {
    return const ShareCardResult(error: 'not_supported_on_android');
  }

  Future<void> downloadCard(ShareCardResult result) async {
    // noop
  }

  Future<bool> shareContent(ContentItem item, {required bool isEn}) async {
    // noop on android
    return false;
  }
}
