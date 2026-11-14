import 'dart:convert';

import 'package:carepulse/models/measurement.dart';
import 'package:carepulse/services/pending_measurement_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const record = <String, Object?>{
    'requestId': 'A1B2C3D4',
    'deviceId': 'carepulse_1',
    'bpm': 78,
    'spo2': 98,
    'activity': 'Resting',
    'note': 'Morning',
    'scanDuration': 6,
    'timestamp': 1760000000000,
  };

  test('secure pending storage keeps account queues separate', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = PendingMeasurementStore();
    final scan = Measurement(
      id: 'A1B2C3D4',
      requestId: 'A1B2C3D4',
      deviceId: 'carepulse_1',
      bpm: 78,
      spo2: 98,
      activity: 'Resting',
      note: 'Morning',
      scanDurationSeconds: 6,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1760000000000),
    );

    await store.save('alice', [scan]);
    expect((await store.load('alice')).single.note, 'Morning');
    expect(await store.load('bob'), isEmpty);
  });

  test('damaged pending results are rejected without deleting evidence', () async {
    for (final invalid in [
      {'bpm': 0},
      {'bpm': 251},
      {'spo2': 101},
      {'scanDuration': 0},
      {'timestamp': 8640000000000001},
      {'note': List.filled(101, 'x').join()},
    ]) {
      final raw = jsonEncode([{...record, ...invalid}]);
      FlutterSecureStorage.setMockInitialValues({'pending_ble_v1_alice': raw});
      final store = PendingMeasurementStore();

      await expectLater(store.load('alice'), throwsFormatException);
      expect(
        await const FlutterSecureStorage().read(key: 'pending_ble_v1_alice'),
        raw,
      );
    }
  });

  test('duplicate persisted scan IDs cannot create conflicting results', () async {
    FlutterSecureStorage.setMockInitialValues({
      'pending_ble_v1_alice': jsonEncode([record, {...record, 'bpm': 90}]),
    });
    await expectLater(
      PendingMeasurementStore().load('alice'),
      throwsFormatException,
    );
  });
}
