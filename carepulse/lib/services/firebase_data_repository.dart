import 'package:firebase_database/firebase_database.dart';

import '../models/device.dart';
import '../models/measurement.dart';
import 'live_data_parser.dart';

/// Read-only Phase 5 boundary. The current deny-all database rules intentionally
/// prevent these listeners from returning live data until access is designed.
class FirebaseDataRepository {
  FirebaseDataRepository({FirebaseDatabase? database, LiveDataParser? parser})
    : _database = database ?? FirebaseDatabase.instance,
      _parser = parser ?? const LiveDataParser();

  final FirebaseDatabase _database;
  final LiveDataParser _parser;

  Stream<List<Measurement>> watchMeasurements(String uid) => _database
      .ref('users/$uid/measurements')
      .onValue
      .map((event) => _parser.measurements(event.snapshot.value));

  Stream<CarePulseDevice?> watchDevice(String uid, String deviceId) => _database
      .ref('users/$uid/devices/$deviceId')
      .onValue
      .map((event) => _parser.device(deviceId, event.snapshot.value));
}
