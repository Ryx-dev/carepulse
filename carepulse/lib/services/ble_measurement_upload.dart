import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/measurement.dart';

/// Writes only to the signed-in owner's validated measurement path.
class BleMeasurementUpload {
  BleMeasurementUpload({FirebaseAuth? auth, FirebaseDatabase? database})
    : _auth = auth ?? FirebaseAuth.instance,
      _database = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  Future<DateTime> save(Measurement measurement, {required String uid}) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Sign in to the account that owns this measurement.');
    }
    await _database
        .ref('users/$uid/measurements/${measurement.requestId}')
        .set({
          'requestId': measurement.requestId,
          'deviceId': measurement.deviceId,
          'bpm': measurement.bpm,
          'spo2': measurement.spo2,
          'activity': measurement.activity,
          'note': measurement.note,
          'scanDuration': measurement.scanDurationSeconds,
          'timestamp': measurement.timestamp.millisecondsSinceEpoch,
        })
        .timeout(const Duration(seconds: 15));
    return measurement.timestamp;
  }

  void dispose() {}
}
