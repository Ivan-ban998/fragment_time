import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/main.dart';

void main() {
  testWidgets('App should build', (WidgetTester tester) async {
    await tester.pumpWidget(const FragmentTimeApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
