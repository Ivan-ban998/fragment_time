// Web-only 平台实现
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

void webReloadPage() {
  try {
    js.context.callMethod('reload', [true]);
  } catch (e) {
    debugPrint('webReloadPage 失败: $e');
    try {
      js.context.callMethod('reload');
    } catch (_) {}
  }
}

void webForceReload() {
  try {
    js.context['location']['href'] = '/?refreshed=1';
  } catch (e) {
    debugPrint('webForceReload 失败: $e');
    webReloadPage();
  }
}
