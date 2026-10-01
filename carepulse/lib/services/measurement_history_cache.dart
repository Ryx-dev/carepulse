import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/measurement.dart';
import 'live_data_parser.dart';

/// Encrypted last-known cloud history, kept separately for each account.
class MeasurementHistoryCache {
  MeasurementHistoryCache({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final LiveDataParser _parser = const LiveDataParser();

  String _key(String uid) => 'live_history_v1_$uid';

  Future<List<Measurement>?> load(String uid) async {
    final raw = await _storage.read(key: _key(uid));
    if (raw == null) return null;
    return _parser.measurements(jsonDecode(raw));
  }

  Future<void> save(String uid, List<Measurement> measurements) async {
    final records = <String, Object?>{};
    for (final m in measurements) {
      records[m.requestId] = {
        'requestId': m.requestId,
        'deviceId': m.deviceId,
        'bpm': m.bpm,
        'spo2': m.spo2,
        'activity': m.activity,
        'note': m.note,
        'scanDuration': m.scanDurationSeconds,
        'timestamp': m.timestamp.millisecondsSinceEpoch,
      };
    }
    await _storage.write(key: _key(uid), value: jsonEncode(records));
  }
}
