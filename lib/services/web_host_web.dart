// lib/services/web_host_web.dart
// 6/11 条件 import: web 端用 window.location.hostname
// 避免 Chrome Private Network Access 拦截跨 host 私网调用
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String currentHostname() {
  try {
    return html.window.location.hostname ?? '192.168.1.20';
  } catch (_) {
    return '192.168.1.20';
  }
}
