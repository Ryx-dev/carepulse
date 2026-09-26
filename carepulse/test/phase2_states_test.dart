import 'package:carepulse/core/theme.dart';
import 'package:carepulse/models/device.dart';
import 'package:carepulse/screens/home.dart';
import 'package:carepulse/screens/pages.dart';
import 'package:carepulse/services/mock_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty session shows dashboard and history empty states', (
    tester,
  ) async {
    final service = MockDataService()..measurements.clear();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: HomeShell(
          name: 'Demo User',
          email: 'demo@example.com',
          data: service,
        ),
      ),
    );

    expect(
      find.text('No scans yet. Start a measurement to add one.'),
      findsOneWidget,
    );
    expect(find.byType(MeasurementRow), findsNothing);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(
      find.text('No measurements yet. Start a scan from Home.'),
      findsOneWidget,
    );
    expect(find.byType(MeasurementRow), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline session disables scanning and shows device status', (
    tester,
  ) async {
    final service = MockDataService();
    service.device = CarePulseDevice(
      id: service.device.id,
      name: service.device.name,
      online: false,
      state: 'offline',
      sensorStatus: 'Sensor unavailable',
      lastSeen: null,
    );
    service.stage = ScanStage.offline;
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: HomeShell(
          name: 'Demo User',
          email: 'demo@example.com',
          data: service,
        ),
      ),
    );

    expect(find.text('Disconnected'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(ElevatedButton, 'Start measurement'),
      200,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Start measurement'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Device'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Sensor unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline scan screen explains how to reconnect', (tester) async {
    final service = MockDataService()..stage = ScanStage.offline;
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: ScanScreen(data: service),
      ),
    );

    expect(find.text('Device offline'), findsOneWidget);
    expect(
      find.text('Connect the device to Wi-Fi before starting a scan.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid and error scan states show a way back', (tester) async {
    final service = MockDataService()..stage = ScanStage.invalidScan;
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: ScanScreen(data: service),
      ),
    );
    expect(find.text('Measurement could not be completed'), findsOneWidget);
    expect(
      find.text(
        'Keep your finger on the sensor for the full scan and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    service.stage = ScanStage.error;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: ScanScreen(data: service),
      ),
    );
    expect(find.text('Scan error'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
