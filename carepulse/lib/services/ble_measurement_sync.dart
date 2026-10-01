import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../models/measurement.dart';
import 'ble_measurement_upload.dart';
import 'pending_measurement_store.dart';

/// Keeps completed scans on the device until the account upload succeeds.
class BleMeasurementSync extends ChangeNotifier with WidgetsBindingObserver {
  BleMeasurementSync({
    required this.uid,
    PendingMeasurementStorage? store,
    Future<void> Function(Measurement)? upload,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  }) : _store = store ?? PendingMeasurementStore(),
       _uploader = upload == null ? BleMeasurementUpload() : null,
       _customUpload = upload,
       _connectivityChanges =
           connectivityChanges ?? Connectivity().onConnectivityChanged;

  final String uid;
  final PendingMeasurementStorage _store;
  final BleMeasurementUpload? _uploader;
  final Future<void> Function(Measurement)? _customUpload;
  final Stream<List<ConnectivityResult>> _connectivityChanges;
  List<Measurement> _pending = const [];
  Future<void>? _ready;
  Future<void> _mutation = Future.value();
  Future<void>? _syncing;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _retryTimer;
  bool _disposed = false;
  Object? _lastError;

  List<Measurement> get pending => List.unmodifiable(_pending);
  int get pendingCount => _pending.length;
  bool get isSyncing => _syncing != null;
  Object? get lastError => _lastError;
  String? get failureMessage {
    final error = _lastError;
    if (error == null) return null;
    if (error is TimeoutException) {
      return 'Upload timed out. Check your internet connection and retry.';
    }
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Firebase rejected this scan. Sign in again or contact support.';
      }
      return 'Upload failed (${error.code}). Check your connection and retry.';
    }
    if (error is StateError &&
        error.message == 'Sign in to the account that owns this measurement.') {
      return 'Sign in to the account that owns this scan to upload it.';
    }
    return 'Upload failed. This scan remains saved on your phone; retry later.';
  }
  bool contains(String requestId) =>
      _pending.any((item) => item.requestId == requestId);

  Future<void> initialize() => _ready ??= _initialize().catchError((Object error) {
    _ready = null;
    _lastError = error;
    if (!_disposed) notifyListeners();
    throw error;
  });

  Future<void> _initialize() async {
    _pending = await _store.load(uid);
    if (_disposed) return;
    notifyListeners();
    WidgetsBinding.instance.addObserver(this);
    _connectivity = _connectivityChanges.listen((types) {
      if (!types.contains(ConnectivityResult.none)) unawaited(retry());
    });
    _retryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_pending.isNotEmpty) unawaited(retry());
    });
    if (_pending.isNotEmpty) unawaited(retry());
  }

  Future<void> enqueue(Measurement measurement) async {
    await initialize();
    if (_disposed) throw StateError('Measurement session ended.');
    await _commit((current) {
      if (current.any((item) => item.requestId == measurement.requestId)) {
        return current;
      }
      return [...current, measurement];
    });
    unawaited(retry());
  }

  Future<void> _commit(
    List<Measurement> Function(List<Measurement>) change,
  ) {
    final result = _mutation.then((_) async {
      final next = change(_pending);
      await _store.save(uid, next);
      _pending = next;
      if (!_disposed) notifyListeners();
    });
    _mutation = result.catchError((Object _) {});
    return result;
  }

  Future<void> retry() async {
    await initialize();
    if (_disposed || _pending.isEmpty) return;
    final active = _syncing;
    if (active != null) return active;
    final work = _flush();
    _syncing = work;
    notifyListeners();
    try {
      await work;
    } finally {
      _syncing = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _flush() async {
    while (!_disposed && _pending.isNotEmpty) {
      final measurement = _pending.first;
      try {
        if (_customUpload != null) {
          await _customUpload(measurement);
        } else {
          await _uploader!.save(measurement, uid: uid);
        }
        await _commit((current) => current
            .where((item) => item.requestId != measurement.requestId)
            .toList());
        _lastError = null;
      } catch (error) {
        _lastError = error;
        if (!_disposed) notifyListeners();
        return;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pending.isNotEmpty) {
      unawaited(retry());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    unawaited(_connectivity?.cancel());
    _uploader?.dispose();
    super.dispose();
  }
}
