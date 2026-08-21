// test/widget_test.dart
// 修正类名匹配 main.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/main.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    // 8/28 P45-4 改: 加 MediaQuery + window size 模拟
    //   真凶: 之前裸 pumpWidget 在小窗口下 (test default 800x600) onboarding
    //     welcomeScreen 触发, 期望 MaterialApp.scaffold 找到
    tester.view.physicalSize = const Size(1080, 1920); // phone portrait
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FragmentTimeApp());
    await tester.pump(); // first frame
    expect(find.byType(FragmentTimeApp), findsOneWidget);
    // 8/28 P45-4: 验证 MaterialApp 渲染 (任何屏幕都该有)
    expect(find.byType(MaterialApp), findsOneWidget);
    print('✓ App boots OK');
  });
}
