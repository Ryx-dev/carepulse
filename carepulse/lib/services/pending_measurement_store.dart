import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/measurement.dart';
import 'live_data_parser.dart';

abstract class PendingMeasurementStorage {
  Future<List<Measurement>> load(String uid);
  Future<void> save(String uid, List<Measurement> measurements);
}

/// Encrypted, account-scoped storage for results awaiting cloud confirmation.
class PendingMeasurementStore implements PendingMeasurementStorage {
  PendingMeasurementStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final LiveDataParser _parser = const LiveDataParser();

  String _key(String uid) => 'pending_ble_v1_$uid';

  @override
  Future<List<Measurement>> load(String uid) async {
    final raw = await _storage.read(key: _key(uid));
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid pending scans');
    final seen = <String>{};
    return decoded.map((item) {
      if (item is! Map) throw const FormatException('Invalid pending scan');
      final data = Map<String, Object?>.from(item);
      final requestId = data['requestId'];
      if (requestId is! String || !seen.add(requestId)) {
        throw const FormatException('Invalid pending scan');
      }
      // Apply the same value bounds as cloud history before showing or retrying
      // a saved result. Preserve the source if any record is damaged.
      return _parser.measurements({requestId: data}).single;
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
