// 6/9 修：Android build 不能 import dart:html
// 用 conditional import 隔离 web-only 实现
export 'share_service_stub.dart'
    if (dart.library.html) 'share_service_web.dart';
