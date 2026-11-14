import '../models/device.dart';
import '../models/measurement.dart';

/// Converts Realtime Database snapshots into local models without accepting
/// incomplete or malformed measurements as successful scans.
class LiveDataParser {
  const LiveDataParser();

  List<Measurement> measurements(Object? value) {
    if (value == null) return [];
    final records = _record(value, 'measurements');
    final result = <Measurement>[];
    for (final entry in records.entries) {
      final requestId = _nonEmptyString(entry.key, 'measurement key');
      final data = _record(entry.value, 'measurement $requestId');
      if (_nonEmptyString(data['requestId'], 'requestId') != requestId) {
        throw FormatException('Measurement requestId does not match its key');
      }
      final note = data['note'] ?? '';
      if (note is! String || note.length > 100) {
        throw FormatException('Invalid measurement note');
      }
      final activity = _nonEmptyString(data['activity'], 'activity');
      if (activity.length > 40) throw FormatException('Invalid activity');
      result.add(
        Measurement(
          id: requestId,
          requestId: requestId,
          deviceId: _nonEmptyString(data['deviceId'], 'deviceId'),
          bpm: _wholeNumber(data['bpm'], 'bpm', min: 1, max: 250),
          spo2: _wholeNumber(data['spo2'], 'spo2', min: 0, max: 100),
          activity: activity,
          note: note,
          scanDurationSeconds: _wholeNumber(
            data['scanDuration'],
            'scanDuration',
            min: 1,
            max: 9007199254740991,
          ),
          timestamp: _timestamp(data['timestamp'], 'timestamp'),
        ),
      );
    }
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  CarePulseDevice? device(String deviceId, Object? value) {
    if (value == null) return null;
    final data = _record(value, 'device $deviceId');
    final online = data['online'];
    if (online is! bool) throw FormatException('Invalid device online flag');
    final lastSeen = data['lastSeen'];
    return CarePulseDevice(
      id: _nonEmptyString(deviceId, 'deviceId'),
      name: _nonEmptyString(data['name'], 'device name'),
      online: online,
      state: _nonEmptyString(data['state'], 'device state'),
      sensorStatus: _nonEmptyString(data['sensorStatus'], 'sensorStatus'),
      lastSeen: lastSeen == null ? null : _timestamp(lastSeen, 'lastSeen'),
    );
  }

  Map<Object?, Object?> _record(Object? value, String field) {
    if (value is! Map) throw FormatException('Invalid $field record');
    return value.cast<Object?, Object?>();
  }

  String _nonEmptyString(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $field');
    }
    return value.trim();
  }

  int _wholeNumber(Object? value, String field, {int? min, int? max}) {
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      throw FormatException('Invalid $field');
    }
    final number = value.toInt();
    if ((min != null && number < min) || (max != null && number > max)) {
      throw FormatException('Invalid $field');
    }
    return number;
  }

  DateTime _timestamp(Object? value, String field) {
    final millis = _wholeNumber(
      value,
      field,
      min: 1,
      max: 8640000000000000,
    );
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
