import 'dart:async';
import 'dart:math';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_pairing_key_store.dart';
import 'ble_protocol.dart';
import 'ble_secure_session.dart';

/// An authenticated, encrypted BLE session owned by one account and screen.
class BleDeviceTransport {
  BleDeviceTransport({FlutterReactiveBle? ble, this.uid, BlePairingKeyStore? pairingKeys})
    : _providedBle = ble, _pairingKeys = pairingKeys ?? BlePairingKeyStore();

  final String? uid;
  final FlutterReactiveBle? _providedBle;
  final BlePairingKeyStore _pairingKeys;
  late final FlutterReactiveBle _ble = _providedBle ?? FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  final StreamController<BleScanEvent> _events = StreamController.broadcast();
  final StreamController<bool> _connectionStates = StreamController.broadcast();
  String? _deviceId;
  String? _activeRequestId;
  BleSecureSession? _session;
  Future<void> _writes = Future<void>.value();
  bool _connected = false;
  bool _ready = false;
  bool _disposed = false;
  int _epoch = 0;

  Stream<BleScanEvent> get events => _events.stream;
  Stream<bool> get connectionStates => _connectionStates.stream;
  bool get isConnected => _connected && _ready;
  BleStatus get status => _ble.status;
  Stream<BleStatus> get statusStream => _ble.statusStream;

  Stream<DiscoveredDevice> discover() => _ble.scanForDevices(
    withServices: [Uuid.parse(BleProtocol.service)], scanMode: ScanMode.lowLatency,
  );

  void _checkSession(int epoch) {
    if (_disposed || epoch != _epoch) throw StateError('The device connection has ended.');
  }

  QualifiedCharacteristic _characteristic(String id, String deviceId) =>
      QualifiedCharacteristic(serviceId: Uuid.parse(BleProtocol.service),
        characteristicId: Uuid.parse(id), deviceId: deviceId);

  Future<void> _writeFrames(List<List<int>> frames, String deviceId, int epoch) {
    final previous = _writes;
    final result = () async {
      await previous;
      for (final frame in frames) {
        _checkSession(epoch);
        await _ble.writeCharacteristicWithResponse(
          _characteristic(BleProtocol.command, deviceId), value: frame,
        ).timeout(const Duration(seconds: 5));
      }
      _checkSession(epoch);
    }();
    // Each caller receives its failure; the next connection can still write.
    _writes = result.catchError((Object _) {});
    return result;
  }

  Future<void> connect(String deviceId, {String? pairingCode}) async {
    if (_disposed) throw StateError('The device connection has ended.');
    await disconnect();
    final epoch = _epoch;
    final owner = uid;
    if (owner == null || owner.isEmpty) throw StateError('Sign in before pairing a sensor.');
    final code = pairingCode == null ? await _pairingKeys.load(owner, deviceId)
        : BleSecureSession.normalizePairingCode(pairingCode);
    _checkSession(epoch);
    if (code == null) throw const BlePairingRequiredException();
    final key = BleSecureSession.pairingKey(code);
    final random = Random.secure();
    final clientNonce = List<int>.generate(16, (_) => random.nextInt(256));
    final connected = Completer<void>();
    Completer<void>? verified;
    final frames = BleSecureFrames();
    _deviceId = deviceId;

    void fail(Object error) {
      if (_disposed || epoch != _epoch) return;
      if (!connected.isCompleted) connected.completeError(error);
      if (verified != null && !verified!.isCompleted) verified!.completeError(error);
      if (_ready) unawaited(disconnect());
    }

    final connectedResult = connected.future.timeout(const Duration(seconds: 20));
    _connection = _ble.connectToAdvertisingDevice(
      id: deviceId, withServices: [Uuid.parse(BleProtocol.service)],
      prescanDuration: const Duration(seconds: 5),
      servicesWithCharacteristicsToDiscover: {
        Uuid.parse(BleProtocol.service): [Uuid.parse(BleProtocol.command), Uuid.parse(BleProtocol.events)],
      },
      connectionTimeout: const Duration(seconds: 10),
    ).listen((update) {
      if (_disposed || epoch != _epoch) return;
      if (update.connectionState == DeviceConnectionState.connected) {
        _connected = true;
        if (!connected.isCompleted) connected.complete();
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        fail(StateError('BLE device disconnected'));
        if (epoch != _epoch) return;
        _connected = _ready = false;
        _session?.close();
        _session = null;
        _connectionStates.add(false);
      }
    }, onError: (Object error) {
      fail(error);
      if (!_disposed && epoch == _epoch) {
        _connected = _ready = false;
        _connectionStates.add(false);
      }
    });
    try {
      await connectedResult;
      _checkSession(epoch);
      final verification = Completer<void>();
      verified = verification;
      final verificationResult = verification.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw const BleAuthenticationException(),
      );
      _notifications = _ble.subscribeToCharacteristic(
        _characteristic(BleProtocol.events, deviceId),
      ).listen((bytes) {
        if (_disposed || epoch != _epoch) return;
        try {
          if (_session == null) {
            if (bytes.length != 17 || bytes[0] != 0x52) throw const BleAuthenticationException();
            _session = BleSecureSession(pairingKey: key, clientNonce: clientNonce, deviceNonce: bytes.sublist(1));
            unawaited(_writeFrames(BleSecureFrames.split(_session!.seal('P')), deviceId, epoch).catchError(fail));
            return;
          }
          final packet = frames.add(bytes);
          if (packet == null) return;
          final message = _session!.open(packet);
          if (!_ready) {
            if (message != 'T') throw const BleAuthenticationException();
            _ready = true;
            if (!verification.isCompleted) verification.complete();
            return;
          }
          final parsed = BleProtocol.parseEvent(message);
          if (parsed != null && parsed.requestId == _activeRequestId) _events.add(parsed);
        } catch (_) {
          fail(const BleAuthenticationException());
        }
      }, onError: (Object _) => fail(const BleAuthenticationException()));
      await Future.wait<void>([
        _writeFrames([[0x48, ...clientNonce]], deviceId, epoch), verificationResult,
      ]);
      _checkSession(epoch);
      await _writes;
      _checkSession(epoch);
      // A wrong key or imitation device can never replace a trusted key.
      if (pairingCode != null) await _pairingKeys.save(owner, deviceId, code);
      _checkSession(epoch);
      _connectionStates.add(true);
    } catch (_) {
      if (epoch == _epoch) await disconnect();
      rethrow;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void> _send(String message) {
    final session = _session;
    final deviceId = _deviceId;
    if (!isConnected || session == null || deviceId == null) {
      throw StateError('Connect to a verified CarePulse device first');
    }
    return _writeFrames(BleSecureFrames.split(session.seal(message)), deviceId, _epoch);
  }

  Future<String> startScan() => _startOperation(false);
  Future<String> startMonitor() => _startOperation(true);

  Future<void> cancelOperation(String requestId) async {
    if (_activeRequestId != requestId) throw StateError('No matching operation is connected');
    await _send(BleProtocol.cancelCommand(requestId));
  }

  Future<String> _startOperation(bool monitor) async {
    if (!isConnected) throw StateError('Connect to a verified CarePulse device first');
    if (_activeRequestId != null) throw StateError('A scan is already active');
    final id = Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0').toUpperCase();
    _activeRequestId = id;
    try {
      await _send(monitor ? BleProtocol.monitorCommand(id) : BleProtocol.scanCommand(id));
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
    _epoch++;
    final wasConnected = _connected;
    _connected = _ready = false;
    _activeRequestId = null;
    _deviceId = null;
    _session?.close();
    _session = null;
    final notifications = _notifications;
    final connection = _connection;
    _notifications = null;
    _connection = null;
    if (wasConnected && !_connectionStates.isClosed) _connectionStates.add(false);
    try { await notifications?.cancel(); } finally { await connection?.cancel(); }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _events.close();
    await _connectionStates.close();
  }
}
