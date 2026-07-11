import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/main.dart';
import 'package:qdbot_app_example/ui/login_page.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const QDBotApp());
    expect(find.byType(MaterialApp), findsOneWidget);

    // Session restore is async (secure storage + optional network)
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) break;
      if (find.text('聊天').evaluate().isNotEmpty) break;
    }

    final onLogin = find.byType(LoginPage).evaluate().isNotEmpty;
    final onHome = find.text('聊天').evaluate().isNotEmpty;
    expect(onLogin || onHome, isTrue);
  });
}
