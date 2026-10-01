import 'dart:async';

import 'package:carepulse/models/measurement.dart';
import 'package:carepulse/services/ble_measurement_sync.dart';
import 'package:carepulse/services/pending_measurement_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements PendingMeasurementStorage {
  final Map<String, List<Measurement>> values = {};
  bool failWrites = false;

  @override
  Future<List<Measurement>> load(String uid) async => [...?values[uid]];

  @override
  Future<void> save(String uid, List<Measurement> measurements) async {
    if (failWrites) throw StateError('storage unavailable');
    values[uid] = [...measurements];
  }
}

Measurement scan(String id) => Measurement(
  id: id,
  requestId: id,
  deviceId: 'carepulse_1',
  bpm: 78,
  spo2: 98,
  activity: 'Resting',
  note: 'Morning',
  scanDurationSeconds: 6,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1760000000000),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed upload stays local across restart, then uploads once', () async {
    final store = MemoryStore();
    final network = StreamController<List<ConnectivityResult>>.broadcast();
    var online = false;
    final uploads = <String>[];
    Future<void> upload(Measurement measurement) async {
      uploads.add(measurement.requestId);
      if (!online) throw StateError('offline');
    }

    final first = BleMeasurementSync(
      uid: 'alice', store: store, upload: upload,
      connectivityChanges: network.stream,
    );
    await first.enqueue(scan('A1B2C3D4'));
    await first.retry();
    expect(first.pendingCount, 1);
    expect(store.values['alice']!.single.requestId, 'A1B2C3D4');
    first.dispose();

    online = true;
    final second = BleMeasurementSync(
      uid: 'alice', store: store, upload: upload,
      connectivityChanges: network.stream,
    );
    await second.initialize();
    await second.retry();
    expect(second.pendingCount, 0);
    expect(store.values['alice'], isEmpty);
    expect(uploads.where((id) => id == 'A1B2C3D4').length, greaterThanOrEqualTo(2));
    second.dispose();
    await network.close();
  });

  test('pending scans belong only to the signed-in account', () async {
    final store = MemoryStore();
    store.values['alice'] = [scan('AAAAAAAA')];
    final network = StreamController<List<ConnectivityResult>>.broadcast();
    final bob = BleMeasurementSync(
      uid: 'bob', store: store,
      upload: (_) async => throw StateError('offline'),
      connectivityChanges: network.stream,
    );
    await bob.initialize();
    expect(bob.pending, isEmpty);
    await bob.enqueue(scan('BBBBBBBB'));
    expect(store.values['alice']!.single.requestId, 'AAAAAAAA');
    expect(store.values['bob']!.single.requestId, 'BBBBBBBB');
    bob.dispose();
    await network.close();
  });

  test('duplicate local enqueue retains one result', () async {
    final store = MemoryStore();
    final network = StreamController<List<ConnectivityResult>>.broadcast();
    final sync = BleMeasurementSync(
      uid: 'alice', store: store,
      upload: (_) async => throw StateError('offline'),
      connectivityChanges: network.stream,
    );
    await sync.enqueue(scan('A1B2C3D4'));
    await sync.enqueue(scan('A1B2C3D4'));
    expect(sync.pendingCount, 1);
    sync.dispose();
    await network.close();
  });

  test('a local storage failure never uploads an unqueued result', () async {
    final store = MemoryStore()..failWrites = true;
    final network = StreamController<List<ConnectivityResult>>.broadcast();
    var uploads = 0;
    final sync = BleMeasurementSync(
      uid: 'alice', store: store,
      upload: (_) async { uploads++; },
      connectivityChanges: network.stream,
    );
    await expectLater(sync.enqueue(scan('A1B2C3D4')), throwsStateError);
    expect(uploads, 0);
    expect(sync.pendingCount, 0);
    sync.dispose();
    await network.close();
  });
}
