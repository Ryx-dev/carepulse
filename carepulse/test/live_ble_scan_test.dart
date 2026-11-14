import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:carepulse/core/theme.dart';
import 'dart:async';
import 'package:carepulse/models/measurement.dart';
import 'package:carepulse/screens/live_ble_scan.dart';
import 'package:carepulse/services/ble_device_transport.dart';
import 'package:carepulse/services/ble_measurement_sync.dart';
import 'package:carepulse/services/ble_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class _TestTransport extends BleDeviceTransport {
  _TestTransport(this.currentStatus);

  BleStatus currentStatus;
  final statuses = StreamController<BleStatus>.broadcast();
  final discovered = StreamController<DiscoveredDevice>.broadcast();
  final scanEvents = StreamController<BleScanEvent>.broadcast();
  final connections = StreamController<bool>.broadcast();
  int searches = 0;
  bool connected = false;
  int cancels = 0;
  int monitors = 0;
  Completer<void>? connectionGate;

  @override
  BleStatus get status => currentStatus;
  @override
  Stream<BleStatus> get statusStream => statuses.stream;
  @override
  Stream<BleScanEvent> get events => scanEvents.stream;
  @override
  Stream<bool> get connectionStates => connections.stream;
  @override
  bool get isConnected => connected;

  void setStatus(BleStatus value) {
    currentStatus = value;
    statuses.add(value);
  }

  @override
  Stream<DiscoveredDevice> discover() {
    searches++;
    return discovered.stream;
  }

  @override
  Future<void> connect(String deviceId, {String? pairingCode}) async {
    await connectionGate?.future;
    connected = true;
  }

  @override
  Future<String> startScan() async => 'A1B2C3D4';

  @override
  Future<String> startMonitor() async {
    monitors++;
    return 'A1B2C3D4';
  }

  @override
  Future<void> cancelOperation(String requestId) async {
    cancels++;
  }

  @override
  void finishScan(String requestId) {}

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<void> dispose() async {
    await statuses.close();
    await discovered.close();
    await scanEvents.close();
    await connections.close();
  }
}

class _TestSync extends BleMeasurementSync {
  _TestSync()
    : super(
        uid: 'test-user',
        connectivityChanges: const Stream.empty(),
        upload: (_) async {},
      );

  int saves = 0;
  Measurement? lastSaved;

  @override
  Future<void> enqueue(Measurement measurement) async {
    saves++;
    lastSaved = measurement;
  }
}

const _channel = MethodChannel('carepulse/ble_permissions');

Future<void> _showScreen(
  WidgetTester tester,
  _TestTransport transport,
  _TestSync sync,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LiveBleScanScreen(
        activity: 'Resting',
        note: '',
        sync: sync,
        transport: transport,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets(
    'Bluetooth off offers the system prompt and searches after ready',
    (tester) async {
      final transport = _TestTransport(BleStatus.poweredOff);
      final sync = _TestSync();
      var enableCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'enable') {
              enableCalls++;
              return enableCalls > 1;
            }
            return true;
          });
      await _showScreen(tester, transport, sync);
      expect(find.text('Bluetooth is off'), findsOneWidget);
      expect(find.text('Turn on Bluetooth'), findsOneWidget);
      expect(transport.searches, 0);

      await tester.tap(find.text('Turn on Bluetooth'));
      await tester.pump();
      expect(enableCalls, 1);
      expect(find.text('Bluetooth is off'), findsOneWidget);
      expect(transport.searches, 0);

      await tester.tap(find.text('Turn on Bluetooth'));
      await tester.pump();
      transport.setStatus(BleStatus.ready);
      await tester.pump();
      expect(enableCalls, 2);
      expect(transport.searches, 1);
      expect(find.text('Searching for CarePulse nearby…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
    },
  );

  testWidgets('Bluetooth off on iOS gives Settings guidance', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final transport = _TestTransport(BleStatus.poweredOff);
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    expect(find.textContaining('iPhone Settings'), findsOneWidget);
    expect(find.text('Turn on Bluetooth'), findsNothing);
    expect(transport.searches, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
    sync.dispose();
  });

  testWidgets('permission and location problems have distinct guidance', (
    tester,
  ) async {
    final transport = _TestTransport(BleStatus.unauthorized);
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    expect(find.text('Bluetooth permission needed'), findsOneWidget);
    expect(transport.searches, 0);
    transport.setStatus(BleStatus.locationServicesDisabled);
    await tester.pump();
    await tester.pump();
    expect(find.text('Location services are off'), findsOneWidget);
    expect(find.textContaining('Turn on Location services'), findsOneWidget);
    expect(transport.searches, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('turning Bluetooth off during discovery stops the search', (
    tester,
  ) async {
    final transport = _TestTransport(BleStatus.ready);
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    expect(transport.searches, 1);
    transport.setStatus(BleStatus.poweredOff);
    await tester.pump();
    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(transport.connected, false);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('Bluetooth off clears a pending connection', (tester) async {
    final transport = _TestTransport(BleStatus.ready)
      ..connectionGate = Completer<void>();
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    transport.discovered.add(
      DiscoveredDevice(
        id: 'carepulse-1',
        name: 'CarePulse',
        serviceData: const {},
        manufacturerData: Uint8List(0),
        rssi: -50,
        serviceUuids: const [],
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Connecting to CarePulse…'), findsOneWidget);
    transport.setStatus(BleStatus.poweredOff);
    await tester.pump();
    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.text('Connecting to CarePulse…'), findsNothing);
    expect(find.text('Start live scan'), findsNothing);
    transport.connectionGate!.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('scan waits beyond 20 seconds and accepts its result', (
    tester,
  ) async {
    final transport = _TestTransport(BleStatus.ready)..connected = true;
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    await tester.tap(find.text('Start live scan'));
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.scanning),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 150));
    expect(find.textContaining('No result arrived'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.complete, bpm: 78, spo2: 98),
    );
    await tester.pump();
    expect(find.text('Scan complete'), findsOneWidget);
    expect(sync.saves, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('finger removal ends a long scan without saving a result', (
    tester,
  ) async {
    final transport = _TestTransport(BleStatus.ready)..connected = true;
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    await tester.tap(find.text('Start live scan'));
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.scanning),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.invalid, reason: 'FR'),
    );
    await tester.pump();
    expect(
      find.text('Finger contact was lost during the scan.'),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Start live scan'),
    );
    expect(button.onPressed, isNotNull);
    expect(sync.saves, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets(
    'monitor streams live values, clears contact loss, and never saves',
    (tester) async {
      final transport = _TestTransport(BleStatus.ready)..connected = true;
      final sync = _TestSync();
      await _showScreen(tester, transport, sync);
      await tester.tap(find.text('Monitor'));
      await tester.pump();
      transport.scanEvents.add(
        const BleScanEvent('A1B2C3D4', BleEventStage.waiting),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      transport.scanEvents.add(
        const BleScanEvent(
          'A1B2C3D4',
          BleEventStage.reading,
          bpm: 78,
          spo2: 98,
        ),
      );
      await tester.pump();
      expect(find.text('78 BPM'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
      expect(find.text('Monitoring'), findsOneWidget);
      expect(sync.saves, 0);
      transport.scanEvents.add(
        const BleScanEvent(
          'BBBBBBBB',
          BleEventStage.reading,
          bpm: 90,
          spo2: 99,
        ),
      );
      await tester.pump();
      expect(find.text('90 BPM'), findsNothing);
      transport.scanEvents.add(
        const BleScanEvent('A1B2C3D4', BleEventStage.contactLost),
      );
      await tester.pump();
      expect(find.text('78 BPM'), findsNothing);
      expect(find.textContaining('within 3 seconds'), findsOneWidget);
      transport.scanEvents.add(
        const BleScanEvent('A1B2C3D4', BleEventStage.unavailable),
      );
      await tester.pump();
      transport.scanEvents.add(
        const BleScanEvent(
          'A1B2C3D4',
          BleEventStage.reading,
          bpm: 80,
          spo2: 97,
        ),
      );
      await tester.pump();
      expect(find.text('80 BPM'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Stopping…'), findsWidgets);
      expect(transport.cancels, 1);
      transport.scanEvents.add(
        const BleScanEvent(
          'A1B2C3D4',
          BleEventStage.reading,
          bpm: 100,
          spo2: 99,
        ),
      );
      await tester.pump();
      expect(find.text('100 BPM'), findsNothing);
      transport.scanEvents.add(
        const BleScanEvent('A1B2C3D4', BleEventStage.cancelled),
      );
      await tester.pump();
      expect(find.text('Measurement cancelled'), findsOneWidget);
      expect(find.text('80 BPM'), findsNothing);
      expect(sync.saves, 0);
      await tester.tap(find.text('Monitor'));
      await tester.pump();
      transport.scanEvents.add(
        const BleScanEvent('A1B2C3D4', BleEventStage.invalid, reason: 'FR'),
      );
      await tester.pump();
      expect(
        find.text('Finger contact was lost during the scan.'),
        findsOneWidget,
      );
      expect(sync.saves, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
    },
  );

  testWidgets('Cancel before a scan result suppresses late completion', (
    tester,
  ) async {
    final transport = _TestTransport(BleStatus.ready)..connected = true;
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    await tester.tap(find.text('Start live scan'));
    await tester.pump();
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.complete, bpm: 78, spo2: 98),
    );
    await tester.pump();
    expect(sync.saves, 0);
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.cancelled),
    );
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.complete, bpm: 78, spo2: 98),
    );
    await tester.pump();
    expect(sync.saves, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets(
    'missing monitor acknowledgement disconnects with firmware guidance',
    (tester) async {
      final transport = _TestTransport(BleStatus.ready)..connected = true;
      final sync = _TestSync();
      await _showScreen(tester, transport, sync);
      await tester.tap(find.text('Monitor'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.textContaining('updated debug firmware'), findsOneWidget);
      expect(transport.connected, false);
      expect(sync.saves, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
    },
  );

  testWidgets('missing cancellation acknowledgement disconnects safely', (
    tester,
  ) async {
    final transport = _TestTransport(BleStatus.ready)..connected = true;
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    await tester.tap(find.text('Monitor'));
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.waiting),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      find.textContaining('could not confirm cancellation'),
      findsOneWidget,
    );
    expect(transport.connected, false);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('monitor controls fit a narrow mobile screen', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final transport = _TestTransport(BleStatus.ready)..connected = true;
    final sync = _TestSync();
    const previewKey = ValueKey('monitor-preview');
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: RepaintBoundary(
          key: previewKey,
          child: LiveBleScanScreen(
            activity: 'Resting',
            note: '',
            sync: sync,
            transport: transport,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Monitor'));
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.reading, bpm: 78, spo2: 98),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(previewKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build').create(recursive: true);
      await File(
        'build/monitor-mobile-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('monitor no-finger and sensor errors end without saving', (
    tester,
  ) async {
    for (final event in [
      const BleScanEvent('A1B2C3D4', BleEventStage.invalid, reason: 'NF'),
      const BleScanEvent('A1B2C3D4', BleEventStage.error, reason: 'TO'),
    ]) {
      final transport = _TestTransport(BleStatus.ready)..connected = true;
      final sync = _TestSync();
      await _showScreen(tester, transport, sync);
      await tester.tap(find.text('Monitor'));
      await tester.pump();
      transport.scanEvents.add(event);
      await tester.pump();
      expect(sync.saves, 0);
      expect(find.text('Cancel'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
    }
  });

  testWidgets('interrupted scan does not save a late result', (tester) async {
    final transport = _TestTransport(BleStatus.ready)..connected = true;
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    expect(find.text('Start live scan'), findsOneWidget);
    await tester.tap(find.text('Start live scan'));
    await tester.pump();
    transport.setStatus(BleStatus.poweredOff);
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.complete, bpm: 78, spo2: 98),
    );
    await tester.pump();
    expect(find.textContaining('scan was interrupted'), findsOneWidget);
    expect(find.text('Scan complete'), findsNothing);
    expect(sync.saves, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });

  testWidgets('a completed result stays visible when Bluetooth turns off', (
    tester,
  ) async {
    final transport = _TestTransport(BleStatus.ready)..connected = true;
    final sync = _TestSync();
    await _showScreen(tester, transport, sync);
    await tester.tap(find.text('Start live scan'));
    await tester.pump();
    transport.scanEvents.add(
      const BleScanEvent('A1B2C3D4', BleEventStage.complete, bpm: 78, spo2: 98),
    );
    await tester.pump();
    expect(sync.saves, 1);
    transport.setStatus(BleStatus.poweredOff);
    await tester.pump();
    expect(find.text('78 BPM'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('Bluetooth is off'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
  });
}
