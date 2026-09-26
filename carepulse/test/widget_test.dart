import 'package:carepulse/core/theme.dart';
import 'package:carepulse/main.dart';
import 'package:carepulse/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo login shows loading and opens dashboard', (tester) async {
    await tester.pumpWidget(const CarePulseApp());
    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.text('Enter your email address'), findsNothing);
    expect(find.text('Enter your password'), findsNothing);

    await tester.enterText(
      find.byType(TextFormField).first,
      'demo@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Signing in...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Your overview'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('DEMO DATA'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Account settings'), findsOneWidget);
    expect(find.text('demo@example.com'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsNWidgets(2));
  });

  testWidgets('validation follows interaction or submission', (tester) async {
    await tester.pumpWidget(const CarePulseApp());
    expect(find.text('Enter your email address'), findsNothing);
    expect(find.text('Enter your password'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsNothing);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your password'), findsOneWidget);
    expect(find.text('Signing in...'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.pump();
    expect(find.text('Enter your email address'), findsOneWidget);
  });

  testWidgets('forgot password explains the demo placeholder', (tester) async {
    await tester.pumpWidget(const CarePulseApp());
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(
      find.text('Password reset is not available in demo mode yet.'),
      findsOneWidget,
    );
  });

  testWidgets('only auth action text is linked and has text-only states', (
    tester,
  ) async {
    await tester.pumpWidget(const CarePulseApp());

    final createLink = find.widgetWithText(TextButton, 'Create account');
    expect(createLink, findsOneWidget);
    expect(
      find.ancestor(
        of: find.text("Don't have an account? "),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );
    final button = tester.widget<TextButton>(createLink);
    expect(
      button.style!.textStyle!.resolve({WidgetState.hovered})!.decoration,
      TextDecoration.underline,
    );
    expect(
      button.style!.foregroundColor!.resolve({WidgetState.pressed}),
      slate,
    );
    expect(
      button.style!.overlayColor!.resolve({WidgetState.hovered}),
      Colors.transparent,
    );

    await tester.tap(createLink);
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Already have an account? '),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );
  });
  testWidgets('sign in remains usable on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CarePulseApp());
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    expect(find.widgetWithText(ElevatedButton, 'Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dashboard fits phone width and keeps navigation usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: const HomeShell(name: 'Demo User', email: 'demo@example.com'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Your overview'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Measurement history'), findsOneWidget);
    await tester.tap(find.text('Device'));
    await tester.pumpAndSettle();
    expect(find.text('Device'), findsWidgets);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Account settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide dashboard stays centered and scan button locks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: const HomeShell(name: 'Demo User', email: 'demo@example.com'),
      ),
    );
    final content = tester.getSize(
      find.byKey(const ValueKey('dashboard_content')),
    );
    expect(content.width, lessThanOrEqualTo(760));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start measurement'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Requesting scan...'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    expect(find.text('In progress...'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton).first,
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
