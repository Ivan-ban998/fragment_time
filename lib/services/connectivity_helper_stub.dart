// 8/8 stub: 非 web 端永远返回 true (mobile 端沿用 dart:io, 周末 mode 不接)
bool isOnline() => true;
void Function() addListener({required void Function(bool online) onChange}) {
  // 非 web 端不监听, 返 no-op 取消函数
  return () {};
}
