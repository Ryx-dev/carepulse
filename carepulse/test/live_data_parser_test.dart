import 'package:carepulse/services/live_data_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = LiveDataParser();

  test(
    'parses and sorts complete measurements without merging note and context',
    () {
      final records = parser.measurements({
        'scan_old': {
          'requestId': 'scan_old',
          'deviceId': 'carepulse_001',
          'bpm': 76,
          'spo2': 98,
          'activity': 'Resting',
          'note': 'Morning',
          'scanDuration': 15,
          'timestamp': 1760000000000,
        },
        'scan_new': {
          'requestId': 'scan_new',
          'deviceId': 'carepulse_001',
          'bpm': 81.0,
          'spo2': 97,
          'activity': 'After warm-up',
          'note': 'Felt calm',
          'scanDuration': 15,
          'timestamp': 1760000015000,
        },
      });

      expect(records.map((record) => record.id), ['scan_new', 'scan_old']);
      expect(records.first.activity, 'After warm-up');
      expect(records.first.note, 'Felt calm');
      expect(records.first.timestamp.millisecondsSinceEpoch, 1760000015000);
    },
  );

  test('missing data is empty and malformed success records are rejected', () {
    expect(parser.measurements(null), isEmpty);
    expect(
      () => parser.measurements({
        'scan_1': {
          'requestId': 'another_request',
          'deviceId': 'carepulse_001',
          'bpm': 78,
          'spo2': 98,
          'activity': 'Resting',
          'scanDuration': 15,
          'timestamp': 1760000000000,
        },
      }),
      throwsFormatException,
    );
    expect(
      () => parser.measurements({
        'scan_1': {
          'requestId': 'scan_1',
          'deviceId': 'carepulse_001',
          'bpm': '78',
          'spo2': 98,
          'activity': 'Resting',
          'scanDuration': 15,
          'timestamp': 1760000000000,
        },
      }),
      throwsFormatException,
    );
  });

  test(
    'device parsing preserves unknown freshness for later status handling',
    () {
      expect(parser.device('carepulse_001', null), isNull);
      final device = parser.device('carepulse_001', {
        'name': 'CarePulse Device',
        'online': true,
        'state': 'ready',
        'sensorStatus': 'connected',
      });
      expect(device!.online, isTrue);
      expect(device.lastSeen, isNull);
    },
  );
}
