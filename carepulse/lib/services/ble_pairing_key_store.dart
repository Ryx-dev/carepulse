import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ble_secure_session.dart';

/// Pairing secrets are never sent to Firebase or across the Bluetooth link.
class BlePairingKeyStore {
  BlePairingKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String uid, String deviceId) =>
      'ble_pairing_v2_${base64Url.encode(utf8.encode('$uid\u0000$deviceId'))}';

  Future<String?> load(String uid, String deviceId) async {
    final code = await _storage.read(key: _key(uid, deviceId));
    return code == null ? null : BleSecureSession.normalizePairingCode(code);
  }

  Future<void> save(String uid, String deviceId, String code) => _storage.write(
    key: _key(uid, deviceId),
    value: BleSecureSession.normalizePairingCode(code),
  );
}
