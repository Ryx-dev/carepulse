class Measurement {
  const Measurement({
    required this.id,
    required this.requestId,
    required this.deviceId,
    required this.bpm,
    required this.spo2,
    required this.activity,
    required this.note,
    required this.scanDurationSeconds,
    required this.timestamp,
  });
  final String id;
  final String requestId;
  final String deviceId;
  final int bpm;
  final int spo2;
  final String activity;
  final String note;
  final int scanDurationSeconds;
  final DateTime timestamp;
}
