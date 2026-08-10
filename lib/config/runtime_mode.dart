// lib/config/runtime_mode.dart
// 2026-08-10 Brien 拍板 (沿 SOUL #125 #137 #160 #188):
// - prod: 公开 RSS + Ollama 真接 + 跳原站 (宪法 §1.1 严)
// - staging: 24 桶 stub + LLM mock + banner "STAGING 测试"
// - dev: 同 staging + 额外 debugPrint
//
// 编译期 DART_DEFINES --dart-define=RUNTIME_MODE=prod|staging|dev
// runtime 不可改 (build 时定), 沿 #188 透明原则

import 'package:flutter/material.dart';

class RuntimeMode {
  final String _name;
  const RuntimeMode._(this._name);

  static const RuntimeMode prod = RuntimeMode._('PROD');
  static const RuntimeMode staging = RuntimeMode._('STAGING');
  static const RuntimeMode dev = RuntimeMode._('DEV');

  /// 从编译期 const 读, 不可改
  /// 用 String.fromEnvironment 直接比较 (const-eligible)
  static final RuntimeMode _resolved = _resolve();

  static RuntimeMode _resolve() {
    const s = String.fromEnvironment('RUNTIME_MODE', defaultValue: 'prod');
    if (s == 'staging') return staging;
    if (s == 'dev') return dev;
    return prod;
  }

  static RuntimeMode get current => _resolved;

  bool get isProd => current == prod;
  bool get isStaging => current == staging;
  bool get isDev => current == dev;

  /// 是否走 stub (staging + dev 都不走真源)
  bool get useStub => current != prod;

  String get label => _name;

  /// 用于 UI banner
  String get bannerText {
    if (this == prod) return '';
    if (this == staging) return 'STAGING 模式 - 测试数据, 非生产内容';
    return 'DEV 模式 - 调试日志开启';
  }

  Color get bannerColor {
    if (this == prod) return Colors.transparent;
    if (this == staging) return const Color(0xFFFFF3CD); // amber 100
    return const Color(0xFFCFE2FF); // blue 100
  }
}
