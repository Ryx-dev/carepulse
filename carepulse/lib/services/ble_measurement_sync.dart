import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../models/measurement.dart';
import 'ble_measurement_upload.dart';
import 'pending_measurement_store.dart';

/// Keeps completed scans on the device until the account upload succeeds.
class BleMeasurementSync extends ChangeNotifier with WidgetsBindingObserver {
  // A replacement session must wait for an old session's already-started
  // secure-storage write before loading its queue for the same account.
  static final Map<String, Future<void>> _storageOperations = {};

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

  Future<void> initialize() {
    if (_disposed) return Future.error(StateError('Measurement session ended.'));
    return _ready ??= _initialize().catchError((Object error) {
      _ready = null;
      _lastError = error;
      if (!_disposed) notifyListeners();
      throw error;
    });
  }

  Future<void> _initialize() async {
    final pending = await _accessStorage(() => _store.load(uid));
    if (_disposed) return;
    _pending = pending;
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
      final duplicate = current.where(
        (item) => item.requestId == measurement.requestId,
      );
      if (duplicate.isNotEmpty) {
        if (!_sameMeasurement(duplicate.first, measurement)) {
          throw StateError('A different scan already uses this request ID.');
        }
        return current;
      }
      return [...current, measurement];
    });
    unawaited(retry());
  }

  bool _sameMeasurement(Measurement a, Measurement b) =>
      a.deviceId == b.deviceId &&
      a.bpm == b.bpm &&
      a.spo2 == b.spo2 &&
      a.activity == b.activity &&
      a.note == b.note &&
      a.scanDurationSeconds == b.scanDurationSeconds &&
      a.timestamp.millisecondsSinceEpoch == b.timestamp.millisecondsSinceEpoch;

  Future<void> _commit(
    List<Measurement> Function(List<Measurement>) change,
  ) {
    final result = _mutation.then(
      (_) => _accessStorage(() async {
        if (_disposed) throw StateError('Measurement session ended.');
        final next = change(_pending);
        await _store.save(uid, next);
        _pending = next;
        if (!_disposed) notifyListeners();
      }),
    );
    _mutation = result.catchError((Object _) {});
    return result;
  }

  Future<T> _accessStorage<T>(Future<T> Function() operation) {
    final previous = _storageOperations[uid] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    final drained = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _storageOperations[uid] = drained;
    unawaited(drained.then((_) {
      if (identical(_storageOperations[uid], drained)) {
        _storageOperations.remove(uid);
      }
    }));
    return result;
  }

  Future<void> retry() async {
    if (_disposed) return;
    try {
      await initialize();
    } catch (_) {
      // Connectivity and lifecycle callbacks retry in the background. Keep a
      // storage read failure in lastError instead of emitting an unhandled error.
      return;
    }
    if (_disposed) return;
    final active = _syncing;
    if (active != null) return active;
    if (_pending.isEmpty) return;
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
    final attempted = <String>{};
    Object? firstError;
    while (!_disposed) {
      final remaining = _pending.where(
        (item) => !attempted.contains(item.requestId),
      );
      if (remaining.isEmpty) break;
      final measurement = remaining.first;
      attempted.add(measurement.requestId);
      try {
        if (_customUpload != null) {
          await _customUpload(measurement);
        } else {
          await _uploader!.save(measurement, uid: uid);
        }
        // A new session may already have loaded this account's queue. Never let
        // the old session overwrite it after its upload finishes.
        if (_disposed) return;
        await _commit((current) => current
            .where((item) => item.requestId != measurement.requestId)
            .toList());
      } catch (error) {
        firstError ??= error;
      }
    }
    _lastError = firstError;
    if (!_disposed) notifyListeners();
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
