// test/widget_test.dart
// 修正类名匹配 main.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/main.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const FragmentTimeApp());
    expect(find.byType(FragmentTimeApp), findsOneWidget);
  });
}
