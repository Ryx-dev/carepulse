import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_protocol.dart';

/// Android/iOS BLE transport. The caller owns the returned subscriptions and
/// should keep this object alive for the duration of a scan.
class BleDeviceTransport {
  BleDeviceTransport({FlutterReactiveBle? ble})
    : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  final StreamController<BleScanEvent> _events = StreamController.broadcast();
  final StreamController<bool> _connectionStates = StreamController.broadcast();
  String? _deviceId;
  String? _activeRequestId;
  bool _connected = false;

  Stream<BleScanEvent> get events => _events.stream;
  Stream<bool> get connectionStates => _connectionStates.stream;
  bool get isConnected => _connected;
  BleStatus get status => _ble.status;

  Stream<DiscoveredDevice> discover() => _ble.scanForDevices(
    withServices: [Uuid.parse(BleProtocol.service)],
    scanMode: ScanMode.lowLatency,
  );

  Future<void> connect(String deviceId) async {
    await disconnect();
    final service = Uuid.parse(BleProtocol.service);
    final command = Uuid.parse(BleProtocol.command);
    final event = Uuid.parse(BleProtocol.events);
    final connected = Completer<void>();
    _deviceId = deviceId;
    _connection = _ble
        .connectToAdvertisingDevice(
          id: deviceId,
          withServices: [service],
          prescanDuration: const Duration(seconds: 5),
          servicesWithCharacteristicsToDiscover: {
            service: [command, event],
          },
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected) {
              _connected = true;
              _connectionStates.add(true);
              if (!connected.isCompleted) connected.complete();
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _connected = false;
              _connectionStates.add(false);
              if (!connected.isCompleted) {
                connected.completeError(StateError('BLE device disconnected'));
              }
            }
          },
          onError: (Object error) {
            _connected = false;
            _connectionStates.add(false);
            if (!connected.isCompleted) connected.completeError(error);
          },
        );
    try {
      await connected.future.timeout(const Duration(seconds: 20));
      _notifications = _ble
          .subscribeToCharacteristic(
            QualifiedCharacteristic(
              serviceId: service,
              characteristicId: event,
              deviceId: deviceId,
            ),
          )
          .listen((bytes) {
            final parsed = BleProtocol.parseEvent(
              utf8.decode(bytes, allowMalformed: true),
            );
            if (parsed != null && parsed.requestId == _activeRequestId) {
              _events.add(parsed);
            }
          });
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  Future<String> startScan() async {
    final deviceId = _deviceId;
    if (!_connected || deviceId == null || _notifications == null) {
      throw StateError('Connect to a CarePulse device first');
    }
    if (_activeRequestId != null) throw StateError('A scan is already active');
    final id = Random.secure()
        .nextInt(0x100000000)
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();
    _activeRequestId = id;
    try {
      await _ble.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          serviceId: Uuid.parse(BleProtocol.service),
          characteristicId: Uuid.parse(BleProtocol.command),
          deviceId: deviceId,
        ),
        value: utf8.encode(BleProtocol.scanCommand(id)),
      );
      return id;
    } catch (_) {
      _activeRequestId = null;
      rethrow;
    }
  }

  void finishScan(String requestId) {
    if (_activeRequestId == requestId) _activeRequestId = null;
  }

  Future<void> disconnect() async {
    _connected = false;
    _activeRequestId = null;
    _deviceId = null;
    await _notifications?.cancel();
    _notifications = null;
    await _connection?.cancel();
    _connection = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _connectionStates.close();
  }
}
