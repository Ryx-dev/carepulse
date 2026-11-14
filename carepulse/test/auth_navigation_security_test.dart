import 'dart:async';

import 'package:carepulse/core/theme.dart';
import 'package:carepulse/models/measurement.dart';
import 'package:carepulse/screens/auth.dart';
import 'package:carepulse/screens/auth_gate.dart';
import 'package:carepulse/screens/demo_session.dart';
import 'package:carepulse/screens/home.dart';
import 'package:carepulse/screens/pages.dart';
import 'package:carepulse/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstAccount = Account(
  uid: 'first-account',
  email: 'first@example.com',
  name: 'First Account',
);
const _privateNote = 'Private note belonging to the first account';

class _FakeAuthService implements AuthService {
  final _changes = StreamController<Account?>.broadcast();
  Account? _account;

  @override
  Account? get currentAccount => _account;

  @override
  Stream<Account?> get accountChanges => _changes.stream;

  void emit(Account? account) {
    _account = account;
    _changes.add(account);
  }

  void fail() => _changes.addError(StateError('Account access failed'));

  Future<void> dispose() => _changes.close();

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<void> signIn(String email, String password) async =>
      emit(Account(uid: 'signed-in-account', email: email));

  @override
  Future<void> register(String name, String email, String password) async =>
      emit(Account(uid: 'registered-account', email: email, name: name));

  @override
  Future<void> sendPasswordReset(String email) async {}
}

Future<_FakeAuthService> _pumpAccount(WidgetTester tester) async {
  final auth = _FakeAuthService()..emit(_firstAccount);
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme,
      home: AuthGate(auth: auth),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<Element> _openPrivateDetails(WidgetTester tester) async {
  final home = tester.widget<HomeShell>(find.byType(HomeShell));
  home.data.measurements
    ..clear()
    ..add(
      Measurement(
        id: 'private-measurement',
        requestId: 'private-request',
        deviceId: 'private-device',
        bpm: 81,
        spo2: 98,
        activity: 'Resting',
        note: _privateNote,
        scanDurationSeconds: 15,
        timestamp: DateTime(2026, 10, 23),
      ),
    );
  await tester.tap(find.text('History'));
  await tester.pumpAndSettle();
  // This invokes HomeShell.openDetails through the real history row callback.
  await tester.tap(find.byType(MeasurementRow));
  await tester.pumpAndSettle();
  expect(find.text(_privateNote), findsOneWidget);
  return tester.element(find.byType(MeasurementDetailsScreen));
}

void main() {
  testWidgets('external sign-out disposes pushed private screens immediately', (
    tester,
  ) async {
    final auth = await _pumpAccount(tester);
    final session = tester.element(find.byType(DemoSession));
    final details = await _openPrivateDetails(tester);

    auth.emit(null);
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(_privateNote, skipOffstage: false), findsNothing);
    expect(details.mounted, isFalse);
    expect(session.mounted, isFalse);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator).last).canPop(),
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_privateNote, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account switch disposes old routes and account data', (
    tester,
  ) async {
    final auth = await _pumpAccount(tester);
    final session = tester.element(find.byType(DemoSession));
    final oldData = tester.widget<HomeShell>(find.byType(HomeShell)).data;
    final details = await _openPrivateDetails(tester);

    auth.emit(
      const Account(
        uid: 'second-account',
        email: 'second@example.com',
        name: 'Second Account',
      ),
    );
    await tester.pump();

    expect(details.mounted, isFalse);
    expect(session.mounted, isFalse);
    expect(find.text(_privateNote, skipOffstage: false), findsNothing);
    final newHome = tester.widget<HomeShell>(find.byType(HomeShell));
    expect(newHome.name, 'Second Account');
    expect(newHome.data, isNot(same(oldData)));
    expect(
      newHome.data.measurements.any((item) => item.note == _privateNote),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth errors remove private screens and reset the session', (
    tester,
  ) async {
    final auth = await _pumpAccount(tester);
    final session = tester.element(find.byType(DemoSession));
    final oldData = tester.widget<HomeShell>(find.byType(HomeShell)).data;
    final details = await _openPrivateDetails(tester);

    auth.fail();
    await tester.pump();

    expect(
      find.text('Could not load your account. Restart the app.'),
      findsOneWidget,
    );
    expect(details.mounted, isFalse);
    expect(session.mounted, isFalse);
    expect(find.text(_privateNote, skipOffstage: false), findsNothing);

    auth.emit(_firstAccount);
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(
      tester.widget<HomeShell>(find.byType(HomeShell)).data,
      isNot(same(oldData)),
    );
    expect(find.text(_privateNote, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-account updates retain routes and system back works', (
    tester,
  ) async {
    final auth = await _pumpAccount(tester);
    final session = tester.element(find.byType(DemoSession));
    final oldData = tester.widget<HomeShell>(find.byType(HomeShell)).data;
    final details = await _openPrivateDetails(tester);

    auth.emit(
      const Account(
        uid: 'first-account',
        email: 'updated@example.com',
        name: 'Updated Name',
      ),
    );
    await tester.pumpAndSettle();

    expect(details.mounted, isTrue);
    expect(session.mounted, isTrue);
    expect(find.text(_privateNote), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(details.mounted, isFalse);
    final home = tester.widget<HomeShell>(find.byType(HomeShell));
    expect(home.name, 'Updated Name');
    expect(home.data, same(oldData));
    expect(tester.takeException(), isNull);
  });

  testWidgets('external sign-in removes an open registration route', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: AuthGate(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    final registration = tester.element(find.byType(RegisterScreen));

    auth.emit(_firstAccount);
    await tester.pump();

    expect(registration.mounted, isFalse);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(RegisterScreen, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
