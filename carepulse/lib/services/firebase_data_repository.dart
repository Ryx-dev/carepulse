import 'package:firebase_database/firebase_database.dart';

import '../models/device.dart';
import '../models/measurement.dart';
import 'live_data_parser.dart';
import 'measurement_history_cache.dart';

/// Read-only listeners for account-scoped device and measurement data.
class FirebaseDataRepository {
  FirebaseDataRepository({
    FirebaseDatabase? database,
    LiveDataParser? parser,
    MeasurementHistoryCache? cache,
  }) : _database = database ?? FirebaseDatabase.instance,
       _parser = parser ?? const LiveDataParser(),
       _cache = cache ?? MeasurementHistoryCache();

  final FirebaseDatabase _database;
  final LiveDataParser _parser;
  final MeasurementHistoryCache _cache;

  Stream<List<Measurement>> watchMeasurements(String uid) => _database
      .ref('users/$uid/measurements')
      .onValue
      .map((event) => _parser.measurements(event.snapshot.value));

  /// Shows the last saved cloud history first, then refreshes it from Firebase.
  Stream<List<Measurement>> watchCachedMeasurements(String uid) async* {
    List<Measurement>? lastKnown;
    try {
      lastKnown = await _cache.load(uid);
    } catch (_) {
      // A damaged local copy must not stop a fresh cloud read.
    }
    if (lastKnown != null) yield lastKnown;
    try {
      await for (final measurements in watchMeasurements(uid)) {
        lastKnown = measurements;
        yield measurements;
        try {
          await _cache.save(uid, measurements);
        } catch (_) {
          // The current cloud result is still usable if storage is unavailable.
        }
      }
    } catch (_) {
      if (lastKnown == null) rethrow;
    }
  }

  Stream<CarePulseDevice?> watchDevice(String uid, String deviceId) => _database
      .ref('users/$uid/devices/$deviceId')
      .onValue
      .map((event) => _parser.device(deviceId, event.snapshot.value));
}
