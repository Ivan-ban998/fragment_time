// lib/services/eye_protection_scope.dart
// 6/13 护眼 InheritedWidget：让任意 widget 拿当前护眼状态
// main.dart 在 MaterialApp.builder 里 Provider.of 提供；其他 widget 调 EyeProtectionScope.of(context)

import 'package:flutter/widgets.dart';

class EyeProtectionScope extends InheritedWidget {
  final bool isOn;
  const EyeProtectionScope({
    super.key,
    required this.isOn,
    required super.child,
  });

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<EyeProtectionScope>();
    return scope?.isOn ?? false;
  }

  @override
  bool updateShouldNotify(EyeProtectionScope oldWidget) => oldWidget.isOn != isOn;
}
