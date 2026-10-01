import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/theme.dart';
import '../models/measurement.dart';
import '../services/ble_device_transport.dart';
import '../services/ble_measurement_sync.dart';
import '../services/ble_protocol.dart';
import 'pages.dart';

/// A live BLE scan with an authenticated upload of completed results.
class LiveBleScanScreen extends StatefulWidget {
  const LiveBleScanScreen({
    super.key,
    required this.activity,
    required this.note,
    required this.sync,
  });
  final String activity;
  final String note;
  final BleMeasurementSync sync;

  @override
  State<LiveBleScanScreen> createState() => _LiveBleScanScreenState();
}

class _LiveBleScanScreenState extends State<LiveBleScanScreen> {
  static const _permissions = MethodChannel('carepulse/ble_permissions');
  final BleDeviceTransport _transport = BleDeviceTransport();
  StreamSubscription<DiscoveredDevice>? _discovery;
  StreamSubscription<BleScanEvent>? _events;
  StreamSubscription<bool>? _connection;
  Timer? _discoveryTimer;
  Timer? _scanTimer;
  final Map<String, DiscoveredDevice> _devices = {};

  String _message = 'Looking for your CarePulse device';
  String? _error;
  String? _deviceName;
  String? _requestId;
  String? _deviceId;
  DateTime? _scanBeganAt;
  Measurement? _pendingMeasurement;
  bool _saving = false;
  bool _saved = false;
  String? _saveError;
  int? _bpm;
  int? _spo2;
  bool _discovering = false;
  bool _connecting = false;
  bool _scanInProgress = false;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_onSyncChanged);
    _events = _transport.events.listen(_onEvent);
    _connection = _transport.connectionStates.listen((connected) {
      if (!mounted || connected) return;
      _scanTimer?.cancel();
      setState(() {
        _deviceName = null;
        _scanInProgress = false;
        _requestId = null;
        if (_pendingMeasurement == null) {
          _bpm = null;
          _spo2 = null;
        }
        _deviceId = null;
        _error = 'CarePulse disconnected. Reconnect and try again.';
        _message = 'Disconnected';
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _findDevices());
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _findDevices() async {
    if (!mounted || _discovering || _connecting || _scanInProgress) return;
    await _discovery?.cancel();
    _discoveryTimer?.cancel();
    setState(() {
      _devices.clear();
      _discovering = true;
      if (_pendingMeasurement == null) {
        _requestId = null;
        _bpm = null;
        _spo2 = null;
        _saveError = null;
        _saved = false;
      }
      _error = null;
      _message = 'Searching for CarePulse nearby…';
    });
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final granted = await _permissions.invokeMethod<bool>('request');
        if (granted != true) {
          throw StateError('Bluetooth permission is needed to find CarePulse.');
        }
      }
      if (!mounted) return;
      _discovery = _transport.discover().listen(
        (device) {
          if (!mounted) return;
          setState(() => _devices[device.id] = device);
        },
        onError: (Object error) =>
            _showError('Could not search for CarePulse: $error'),
      );
      _discoveryTimer = Timer(const Duration(seconds: 10), () async {
        await _discovery?.cancel();
        if (!mounted) return;
        setState(() {
          _discovering = false;
          _message = _devices.isEmpty
              ? 'No CarePulse device found. Check that the ESP32 is powered on.'
              : 'Choose your CarePulse device';
        });
      });
    } catch (error) {
      _showError(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _connect(DiscoveredDevice device) async {
    _discoveryTimer?.cancel();
    await _discovery?.cancel();
    if (!mounted) return;
    setState(() {
      _discovering = false;
      _connecting = true;
      _error = null;
      _message = 'Connecting to CarePulse…';
    });
    try {
      await _transport.connect(device.id);
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _deviceName = device.name.isEmpty ? 'CarePulse' : device.name;
        _deviceId = device.id;
        _message = 'Connected. Place your finger on the sensor, then start.';
      });
    } catch (error) {
      _showError(
        'Could not connect. Move closer to CarePulse and retry. $error',
      );
    }
  }

  Future<void> _startScan() async {
    if (!_transport.isConnected ||
        _scanInProgress ||
        (_pendingMeasurement != null && !_saved)) {
      return;
    }
    setState(() {
      _scanInProgress = true;
      _error = null;
      _requestId = null;
      _bpm = null;
      _spo2 = null;
      _pendingMeasurement = null;
      _saveError = null;
      _saved = false;
      _scanBeganAt = DateTime.now();
      _message = 'Sending scan request…';
    });
    try {
      _requestId = await _transport.startScan();
      if (!mounted || !_scanInProgress) return;
      _scanTimer = Timer(const Duration(seconds: 20), () {
        final id = _requestId;
        if (id != null) _transport.finishScan(id);
        _showError(
          'No result arrived from CarePulse. Check the connection and retry.',
        );
      });
    } catch (error) {
      _showError('Could not start the scan: $error');
    }
  }

  void _onEvent(BleScanEvent event) {
    if (!mounted) return;
    if (event.stage == BleEventStage.complete ||
        event.stage == BleEventStage.invalid ||
        event.stage == BleEventStage.error) {
      _scanTimer?.cancel();
      _transport.finishScan(event.requestId);
    }
    setState(() {
      _requestId = event.requestId;
      switch (event.stage) {
        case BleEventStage.waiting:
          _message = 'Waiting for your finger (up to 3 seconds)…';
        case BleEventStage.scanning:
          _message = 'Collecting 100 samples. Keep your finger still.';
        case BleEventStage.processing:
          _message = 'Calculating your measurement…';
        case BleEventStage.complete:
          _scanInProgress = false;
          _bpm = event.bpm;
          _spo2 = event.spo2;
          _message = 'Scan complete';
          final started = _scanBeganAt ?? DateTime.now();
          final seconds =
              ((DateTime.now().difference(started).inMilliseconds + 999) ~/
                      1000)
                  .clamp(1, 20);
          _pendingMeasurement = Measurement(
            id: event.requestId,
            requestId: event.requestId,
            deviceId: _deviceId ?? 'CarePulse',
            bpm: event.bpm!,
            spo2: event.spo2!,
            activity: widget.activity,
            note: widget.note,
            scanDurationSeconds: seconds,
            timestamp: DateTime.now(),
          );
        case BleEventStage.invalid:
          _scanInProgress = false;
          _error = switch (event.reason) {
            'NF' => 'No finger was detected within 3 seconds.',
            'FR' => 'Finger contact was lost during the scan.',
            'FS' =>
              'Fewer than 100 usable samples were collected in 10 seconds.',
            'AR' => 'The sensor could not calculate a valid result. Try again.',
            _ => 'The scan was not valid. Try again.',
          };
          _message = 'Scan not completed';
        case BleEventStage.error:
          _scanInProgress = false;
          _error =
              'CarePulse reported a sensor error. Restart the device and try again.';
          _message = 'Device error';
      }
    });
    if (event.stage == BleEventStage.complete) unawaited(_saveResult());
  }

  Future<void> _saveResult() async {
    final measurement = _pendingMeasurement;
    if (measurement == null || _saving || _saved) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.sync.enqueue(measurement);
      if (!mounted) return;
      if (!identical(_pendingMeasurement, measurement)) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
    } catch (_) {
      if (!mounted) return;
      if (!identical(_pendingMeasurement, measurement)) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save this result on the phone. Retry before leaving this screen.';
      });
    }
  }

  void _openHistory() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Live history')),
          body: LiveHistoryScreen(
            uid: uid,
            sync: widget.sync,
            onDetails: (measurement) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MeasurementDetailsScreen(
                  measurement: measurement,
                  demo: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    _scanTimer?.cancel();
    setState(() {
      _discovering = false;
      _connecting = false;
      _scanInProgress = false;
      _error = message;
      _message = 'Connection needs attention';
    });
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _scanTimer?.cancel();
    unawaited(_discovery?.cancel());
    unawaited(_events?.cancel());
    unawaited(_connection?.cancel());
    unawaited(_transport.dispose());
    widget.sync.removeListener(_onSyncChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Live device scan')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.sensors_rounded,
                      size: 44,
                      color: primaryRed,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_requestId != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Scan ID: $_requestId',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: slate, fontSize: 12),
                      ),
                    ],
                    if (_discovering || _connecting || _scanInProgress) ...[
                      const SizedBox(height: 18),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: primaryRed),
                      ),
                    ],
                    if (_bpm != null && _spo2 != null) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _Result(
                              label: 'Heart rate',
                              value: '$_bpm BPM',
                            ),
                          ),
                          Expanded(
                            child: _Result(
                              label: 'Blood oxygen',
                              value: '$_spo2%',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_saving)
                        const Text(
                          'Saving on this phone…',
                          textAlign: TextAlign.center,
                        )
                      else if (_saved)
                        Text(
                          widget.sync.contains(_pendingMeasurement!.requestId)
                              ? 'Saved on this phone. ${widget.sync.isSyncing ? 'Uploading…' : 'Waiting to upload when online.'}'
                              : 'Uploaded to your account history',
                          textAlign: TextAlign.center,
                        )
                      else if (_saveError != null) ...[
                        Text(
                          _saveError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: primaryRed),
                        ),
                        TextButton(
                          onPressed: _saveResult,
                          child: const Text('Retry save'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 20),
                    if (_transport.isConnected)
                      ElevatedButton(
                        onPressed: _scanInProgress ||
                                (_pendingMeasurement != null && !_saved)
                            ? null
                            : _startScan,
                        child: Text(
                          _bpm == null ? 'Start live scan' : 'Scan again',
                        ),
                      )
                    else
                      OutlinedButton(
                        onPressed: _discovering || _connecting
                            ? null
                            : _findDevices,
                        child: const Text('Search again'),
                      ),
                    if (_saved) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _openHistory,
                        child: const Text('View live history'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_transport.isConnected && _devices.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Nearby CarePulse devices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ..._devices.values.map(
                (device) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(
                      device.name.isEmpty ? 'CarePulse' : device.name,
                    ),
                    subtitle: Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _connecting ? null : () => _connect(device),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              _deviceName == null
                  ? 'Keep the ESP32 powered on and near your phone.'
                  : 'Connected to $_deviceName. Completed scans are saved on this phone, then uploaded when online.',
              style: const TextStyle(color: slate),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Result extends StatelessWidget {
  const _Result({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: slate)),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: deepSlate,
        ),
      ),
    ],
  );
}
