import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/measurement.dart';

abstract class PendingMeasurementStorage {
  Future<List<Measurement>> load(String uid);
  Future<void> save(String uid, List<Measurement> measurements);
}

/// Encrypted, account-scoped storage for results awaiting cloud confirmation.
class PendingMeasurementStore implements PendingMeasurementStorage {
  PendingMeasurementStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String uid) => 'pending_ble_v1_$uid';

  @override
  Future<List<Measurement>> load(String uid) async {
    final raw = await _storage.read(key: _key(uid));
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid pending scans');
    return decoded.map((item) {
      if (item is! Map) throw const FormatException('Invalid pending scan');
      final data = Map<String, Object?>.from(item);
      final requestId = data['requestId'];
      final deviceId = data['deviceId'];
      final bpm = data['bpm'];
      final spo2 = data['spo2'];
      final activity = data['activity'];
      final note = data['note'];
      final duration = data['scanDuration'];
      final timestamp = data['timestamp'];
      if (requestId is! String || deviceId is! String || bpm is! int ||
          spo2 is! int || activity is! String || note is! String ||
          duration is! int || timestamp is! int) {
        throw const FormatException('Invalid pending scan');
      }
      return Measurement(
        id: requestId,
        requestId: requestId,
        deviceId: deviceId,
        bpm: bpm,
        spo2: spo2,
        activity: activity,
        note: note,
        scanDurationSeconds: duration,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    }).toList();
  }

  @override
  Future<void> save(String uid, List<Measurement> measurements) =>
      _storage.write(
        key: _key(uid),
        value: jsonEncode(measurements.map((m) => {
          'requestId': m.requestId,
          'deviceId': m.deviceId,
          'bpm': m.bpm,
          'spo2': m.spo2,
          'activity': m.activity,
          'note': m.note,
          'scanDuration': m.scanDurationSeconds,
          'timestamp': m.timestamp.millisecondsSinceEpoch,
        }).toList()),
      );
}
