// Stub for non-web platforms (Android/iOS/desktop)
// Web-only dart:js calls are no-ops here.
import 'package:flutter/foundation.dart';

void webReloadPage() {
  debugPrint('webReloadPage 在非 web 端无操作');
}

void webForceReload() {
  debugPrint('webForceReload 在非 web 端无操作');
}
