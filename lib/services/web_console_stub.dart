// lib/services/web_console_stub.dart
// 8/7 加 (沿 SOUL #137 真凶): native 端 stub — native 不该有 console.log, 仅 web 端用
// 真凶链: Flutter web release build 把 print() 改成走 zone 内部 stdout,
//   在 Chrome console 看 print() 输出有条件 (要 --source-maps or 启用 zone error handler)
// 修法: web 端条件 import dart:html, 直接调 window.console.log
// native 端走 stub (空函数)

void log(String message) {
  // ignore: avoid_print
  print(message);
}