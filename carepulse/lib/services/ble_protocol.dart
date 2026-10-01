/// Version 1 of the small CarePulse BLE wire format. Every frame is UTF-8 and
/// at most 20 bytes so it also fits the default BLE ATT notification payload.
class BleProtocol {
  static const service = '11c0a001-9ef2-4b77-9f6c-111111111111';
  static const command = '11c0a002-9ef2-4b77-9f6c-111111111111';
  static const events = '11c0a003-9ef2-4b77-9f6c-111111111111';

  static final RegExp _id = RegExp(r'^[0-9A-F]{8}$');

  static String scanCommand(String requestId) {
    if (!_id.hasMatch(requestId)) {
      throw const FormatException('Invalid request ID');
    }
    return 'S|$requestId';
  }

  static BleScanEvent? parseEvent(String frame) {
    if (frame.length > 20) return null;
    final parts = frame.split('|');
    if (parts.length < 2 || !_id.hasMatch(parts[1])) return null;
    final id = parts[1];
    switch (parts[0]) {
      case 'W' when parts.length == 2:
        return BleScanEvent(id, BleEventStage.waiting);
      case 'S' when parts.length == 2:
        return BleScanEvent(id, BleEventStage.scanning);
      case 'P' when parts.length == 2:
        return BleScanEvent(id, BleEventStage.processing);
      case 'C' when parts.length == 4:
        final bpm = int.tryParse(parts[2]);
        final spo2 = int.tryParse(parts[3]);
        if (bpm == null ||
            bpm < 1 ||
            bpm > 250 ||
            spo2 == null ||
            spo2 < 0 ||
            spo2 > 100) {
          return null;
        }
        return BleScanEvent(id, BleEventStage.complete, bpm: bpm, spo2: spo2);
      case 'I' when parts.length == 3:
        return BleScanEvent(id, BleEventStage.invalid, reason: parts[2]);
      case 'E' when parts.length == 3:
        return BleScanEvent(id, BleEventStage.error, reason: parts[2]);
    }
    return null;
  }
}

enum BleEventStage { waiting, scanning, processing, complete, invalid, error }

class BleScanEvent {
  const BleScanEvent(
    this.requestId,
    this.stage, {
    this.bpm,
    this.spo2,
    this.reason,
  });

  final String requestId;
  final BleEventStage stage;
  final int? bpm;
  final int? spo2;
  final String? reason;
}
