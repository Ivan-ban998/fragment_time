// 8/8 沿 SOUL #188 透明原则: 离线状态 helper
// 沿用 #137 #160 真凶链 (公开浏览器 API + 不用模拟器验):
//   - navigator.onLine (web 端简单 API)
//   - online / offline events 监听
//   - 跨平台 stub: 非 web 走 stub (mobile 端走 dart:io 但周末 mode 不接 mobile)
//
// 真凶链:
//   旧: 没有离线状态, 离线时 fetchTop 失败, 显 0 条假数据 (沿 SOUL #119 不撒谎)
//   修: 顶栏 banner 显示"离线模式 — 显示 X 小时前缓存", 用户知道为啥空
//
// 沿 #117 沿用 alert: navigator.onLine 在 web 端不可靠 (公司 WiFi 切 VPN / 飞行模式
//   浏览器不一定刷新), 只能做兜底 UX, 别依赖它做核心逻辑
import 'connectivity_helper_stub.dart'
    if (dart.library.html) 'connectivity_helper_web.dart' as conn;

class ConnectivityHelper {
  /// 当前是否在线 (web 端 navigator.onLine, native 端默认 true)
  static bool isOnline() {
    return conn.isOnline();
  }

  /// 监听 online / offline 事件, 返回取消订阅函数
  static void Function() addListener({required void Function(bool online) onChange}) {
    return conn.addListener(onChange: onChange);
  }
}
