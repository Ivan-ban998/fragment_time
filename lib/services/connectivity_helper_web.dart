// 8/8 web 端: 走 navigator.onLine + online/offline events
// 沿 SOUL #137 #160 公开浏览器 API 真凶链 + 沿 #117 沿用 alert (navigator.onLine 不绝对可靠)
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool isOnline() => html.window.navigator.onLine ?? true;

void Function() addListener({required void Function(bool online) onChange}) {
  void onlineHandler(html.Event e) => onChange(true);
  void offlineHandler(html.Event e) => onChange(false);
  html.window.addEventListener('online', onlineHandler);
  html.window.addEventListener('offline', offlineHandler);
  return () {
    html.window.removeEventListener('online', onlineHandler);
    html.window.removeEventListener('offline', offlineHandler);
  };
}
