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

  testWidgets('App hot restart 重建 widget tree', (WidgetTester tester) async {
    // 8/28 P46-4 加 (沿 SOUL #137 真凶链): 验证 hot restart 不崩
    //   真凶: 之前 P31 / P32 修改后未测 hot restart
    //   修: 测 hot restart 后 MaterialApp + FragmentTimeApp 仍存在
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FragmentTimeApp());
    await tester.pump();
    expect(find.byType(FragmentTimeApp), findsOneWidget);

    // hot restart
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(find.byType(FragmentTimeApp), findsNothing);

    await tester.pumpWidget(const FragmentTimeApp());
    await tester.pump();
    expect(find.byType(FragmentTimeApp), findsOneWidget);
    print('✓ Hot restart OK');
  });

  testWidgets('App 多次 hot restart 稳定', (WidgetTester tester) async {
    // 8/28 P47-3 加 (沿 SOUL #189 智): 测多次 hot restart
    //   真凶: 之前只测 1 次, 多次循环可能漏内存泄漏
    //   修: 3 次 hot restart, 验证仍能 boot
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (int i = 0; i < 3; i++) {
      await tester.pumpWidget(const FragmentTimeApp());
      await tester.pump();
      expect(find.byType(FragmentTimeApp), findsOneWidget,
          reason: 'iteration $i: App should boot');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(find.byType(FragmentTimeApp), findsNothing,
          reason: 'iteration $i: App should be cleared');
    }
    print('✓ 3 hot restarts OK');
  });
}
