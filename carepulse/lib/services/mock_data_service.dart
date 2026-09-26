import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/device.dart';
import '../models/measurement.dart';

enum ScanStage {
  ready,
  requestingScan,
  waitingForFinger,
  scanning,
  processing,
  uploading,
  complete,
  invalidScan,
  error,
  offline,
}

class MockDataService extends ChangeNotifier {
  static const scanDurationSeconds = 15;
  static const contexts = [
    'Resting',
    'Before Exercise',
    'After Exercise',
    'Recovery',
    'Other',
  ];
  CarePulseDevice device = CarePulseDevice(
    id: 'carepulse_001',
    name: 'CarePulse Device',
    online: true,
    state: 'ready',
    sensorStatus: 'MAX30102 connected',
    lastSeen: DateTime(2026, 9, 26, 9, 46),
  );
  final List<Measurement> measurements = [
    Measurement(
      id: 'mock_1',
      requestId: 'mock_1',
      deviceId: 'carepulse_001',
      bpm: 78,
      spo2: 98,
      activity: 'Resting',
      note: 'Morning measurement',
      scanDurationSeconds: 15,
      timestamp: DateTime(2026, 9, 26, 9, 35),
    ),
    Measurement(
      id: 'mock_2',
      requestId: 'mock_2',
      deviceId: 'carepulse_001',
      bpm: 128,
      spo2: 97,
      activity: 'After Exercise',
      note: '',
      scanDurationSeconds: 15,
      timestamp: DateTime(2026, 9, 25, 17, 20),
    ),
    Measurement(
      id: 'mock_3',
      requestId: 'mock_3',
      deviceId: 'carepulse_001',
      bpm: 133,
      spo2: 97,
      activity: 'After Exercise',
      note: '',
      scanDurationSeconds: 15,
      timestamp: DateTime(2026, 9, 23, 16, 10),
    ),
    Measurement(
      id: 'mock_4',
      requestId: 'mock_4',
      deviceId: 'carepulse_001',
      bpm: 76,
      spo2: 98,
      activity: 'Resting',
      note: '',
      scanDurationSeconds: 15,
      timestamp: DateTime(2026, 9, 21, 8, 15),
    ),
  ];
  ScanStage stage = ScanStage.ready;
  int secondsRemaining = scanDurationSeconds;
  String? requestId;
  Timer? _timer;

  Measurement? get latest => measurements.isEmpty ? null : measurements.first;
  bool get canScan =>
      device.online &&
      device.state == 'ready' &&
      (stage == ScanStage.ready ||
          stage == ScanStage.complete ||
          stage == ScanStage.invalidScan ||
          stage == ScanStage.error);

  void startScan({required String activity, required String note}) {
    if (!canScan) return;
    requestId = 'scan_${DateTime.now().microsecondsSinceEpoch}';
    secondsRemaining = scanDurationSeconds;
    _setStage(ScanStage.requestingScan);
    _timer = Timer(const Duration(milliseconds: 500), () {
      _setStage(ScanStage.waitingForFinger);
      _timer = Timer(const Duration(seconds: 1), () {
        _setStage(ScanStage.scanning);
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          secondsRemaining--;
          notifyListeners();
          if (secondsRemaining > 0) return;
          timer.cancel();
          _setStage(ScanStage.processing);
          _timer = Timer(const Duration(seconds: 1), () {
            _setStage(ScanStage.uploading);
            _timer = Timer(const Duration(milliseconds: 500), () {
              measurements.insert(
                0,
                Measurement(
                  id: requestId!,
                  requestId: requestId!,
                  deviceId: device.id,
                  bpm: 78,
                  spo2: 98,
                  activity: activity,
                  note: note.trim(),
                  scanDurationSeconds: scanDurationSeconds,
                  timestamp: DateTime.now(),
                ),
              );
              _setStage(ScanStage.complete);
            });
          });
        });
      });
    });
  }

  void _setStage(ScanStage value) {
    stage = value;
    device = CarePulseDevice(
      id: device.id,
      name: device.name,
      online: device.online,
      state: switch (value) {
        ScanStage.requestingScan => 'requesting scan',
        ScanStage.waitingForFinger => 'waiting for finger',
        ScanStage.scanning => 'scanning',
        ScanStage.processing => 'processing',
        ScanStage.uploading => 'uploading',
        _ => 'ready',
      },
      sensorStatus: device.sensorStatus,
      lastSeen: DateTime.now(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
