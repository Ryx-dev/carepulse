class CarePulseDevice {
  const CarePulseDevice({
    required this.id,
    required this.name,
    required this.online,
    required this.state,
    required this.sensorStatus,
    required this.lastSeen,
  });
  final String id;
  final String name;
  final bool online;
  final String state;
  final String sensorStatus;
  final DateTime? lastSeen;
}
