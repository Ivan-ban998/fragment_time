// lib/services/web_console_web.dart
// 8/7 加 (沿 SOUL #137 真凶): web 端直接调 window.console.log
// 不走 dart:io print (release build 走 zone internal, 偶尔不进 Chrome console)
// 真凶链: 之前 print() 在 release build 进 main.dart.js, 但 Chrome DevTools console 不显示
//   (沿 #6 #137 诊断链, release build 把 print 改成 _printToZone 不进 stdout)
// 修法: dart:html 条件 import + window.console.log — 100% 进 Chrome console

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void log(String message) {
  html.window.console.log(message);
}