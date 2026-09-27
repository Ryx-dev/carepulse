import 'package:carepulse/core/theme.dart';
import 'package:carepulse/screens/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> expectAuthLogoLoads(WidgetTester tester) async {
  final logoFinder = find.byWidgetPredicate(
    (widget) => widget is Image && widget.semanticLabel == 'CarePulse logo',
  );
  expect(logoFinder, findsOneWidget);

  final logo = tester.widget<Image>(logoFinder);
  Object? imageError;
  await tester.runAsync(() async {
    await precacheImage(
      logo.image,
      tester.element(logoFinder),
      onError: (error, stackTrace) => imageError = error,
    ).timeout(const Duration(seconds: 5));
  });

  expect(imageError, isNull, reason: 'The visible CarePulse logo must decode.');
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('sign in logo asset loads', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: appTheme, home: const LoginScreen()),
    );
    await tester.pumpAndSettle();
    await expectAuthLogoLoads(tester);
  });

  testWidgets('register logo asset loads', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: appTheme, home: const RegisterScreen()),
    );
    await tester.pumpAndSettle();
    await expectAuthLogoLoads(tester);
  });
}
