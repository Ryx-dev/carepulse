import 'package:flutter_test/flutter_test.dart';
import 'package:carepulse/services/ble_protocol.dart';
import 'package:carepulse/services/ble_device_transport.dart';

void main() {
  test('mobile transport API is available', () {
    expect(BleDeviceTransport, isNotNull);
  });
  test('rejects malformed requests and results', () {
    expect(() => BleProtocol.scanCommand('bad'), throwsFormatException);
    expect(BleProtocol.parseEvent('C|A1B2C3D4|78|98')?.bpm, 78);
    expect(BleProtocol.parseEvent('C|A1B2C3D4|0|98'), isNull);
    expect(BleProtocol.parseEvent('C|A1B2C3D4|78|101'), isNull);
    expect(BleProtocol.parseEvent('C|wrong|78|98'), isNull);
  });

  test('parses progress and terminal messages', () {
    expect(BleProtocol.scanCommand('A1B2C3D4'), 'S|A1B2C3D4');
    expect(BleProtocol.parseEvent('W|A1B2C3D4')?.stage, BleEventStage.waiting);
    expect(BleProtocol.parseEvent('S|A1B2C3D4')?.stage, BleEventStage.scanning);
    expect(
      BleProtocol.parseEvent('P|A1B2C3D4')?.stage,
      BleEventStage.processing,
    );
    expect(BleProtocol.parseEvent('I|A1B2C3D4|NF')?.reason, 'NF');
    expect(BleProtocol.parseEvent('E|A1B2C3D4|TO')?.reason, 'TO');
  });
}
