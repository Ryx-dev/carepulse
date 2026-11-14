import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

class BlePairingRequiredException implements Exception {
  const BlePairingRequiredException();
}

class BleAuthenticationException implements Exception {
  const BleAuthenticationException();

  @override
  String toString() =>
      'Device verification failed. Check the pairing code and update the sensor firmware.';
}

/// Version 2 uses separate AES-GCM keys in each direction, derived from a
/// physical device secret and fresh nonces from both peers. No plaintext scan
/// command or result is accepted. Counters are authenticated and never reused.
class BleSecureSession {
  BleSecureSession({
    required List<int> pairingKey,
    required List<int> clientNonce,
    required List<int> deviceNonce,
    bool client = true,
  }) {
    if (pairingKey.length != 16 ||
        clientNonce.length != 16 ||
        deviceNonce.length != 16) {
      throw const BleAuthenticationException();
    }
    _sendLabel = utf8.encode('CarePulse/v2/${client ? 'c2d' : 'd2c'}');
    _receiveLabel = utf8.encode('CarePulse/v2/${client ? 'd2c' : 'c2d'}');
    Uint8List derive(List<int> label) => Uint8List.fromList(
      Hmac(sha256, pairingKey)
          .convert([...label, ...clientNonce, ...deviceNonce])
          .bytes
          .sublist(0, 16),
    );
    _sendKey = derive(_sendLabel);
    _receiveKey = derive(_receiveLabel);
  }

  late final Uint8List _sendKey;
  late final Uint8List _receiveKey;
  late final List<int> _sendLabel;
  late final List<int> _receiveLabel;
  int _sendCounter = 0;
  int _receiveCounter = 0;
  bool _closed = false;

  static String normalizePairingCode(String value) {
    final code = value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(code)) {
      throw const FormatException('Enter the 32-character sensor pairing code.');
    }
    return code;
  }

  static Uint8List pairingKey(String code) {
    final normalized = normalizePairingCode(code);
    return Uint8List.fromList([
      for (var i = 0; i < normalized.length; i += 2)
        int.parse(normalized.substring(i, i + 2), radix: 16),
    ]);
  }

  Uint8List _counterBytes(int counter) =>
      (ByteData(4)..setUint32(0, counter)).buffer.asUint8List();

  Uint8List _nonce(int counter) =>
      Uint8List.fromList([...List<int>.filled(8, 0), ..._counterBytes(counter)]);

  Uint8List seal(String message) {
    final bytes = utf8.encode(message);
    if (_closed ||
        _sendCounter >= 0xFFFFFFFF ||
        bytes.isEmpty ||
        bytes.length > 20) {
      throw const BleAuthenticationException();
    }
    final counter = _sendCounter++;
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_sendKey), 128, _nonce(counter),
            Uint8List.fromList(_sendLabel)),
      );
    return Uint8List.fromList([
      ..._counterBytes(counter),
      ...cipher.process(Uint8List.fromList(bytes)),
    ]);
  }

  String open(List<int> packet) {
    if (_closed || packet.length < 21 || packet.length > 40) {
      throw const BleAuthenticationException();
    }
    final bytes = Uint8List.fromList(packet);
    final counter = ByteData.sublistView(bytes).getUint32(0);
    if (counter != _receiveCounter || counter >= 0xFFFFFFFF) {
      throw const BleAuthenticationException();
    }
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(_receiveKey), 128, _nonce(counter),
              Uint8List.fromList(_receiveLabel)),
        );
      final plaintext = cipher.process(Uint8List.sublistView(bytes, 4));
      final message = utf8.decode(plaintext);
      _receiveCounter++;
      return message;
    } catch (_) {
      throw const BleAuthenticationException();
    }
  }

  void close() {
    _closed = true;
    _sendKey.fillRange(0, _sendKey.length, 0);
    _receiveKey.fillRange(0, _receiveKey.length, 0);
  }
}

/// Bounded fragmentation keeps encrypted packets within the default ATT MTU.
class BleSecureFrames {
  final List<int> _pending = [];
  int _next = 0;
  int _total = 0;

  static List<List<int>> split(List<int> packet) {
    if (packet.length < 21 || packet.length > 40) {
      throw const BleAuthenticationException();
    }
    final count = (packet.length + 16) ~/ 17;
    return [
      for (var i = 0; i < count; i++)
        [0x44, i, count, ...packet.skip(i * 17).take(17)],
    ];
  }

  List<int>? add(List<int> frame) {
    if (frame.length < 4 ||
        frame.length > 20 ||
        frame[0] != 0x44 ||
        frame[1] != _next ||
        frame[2] < 2 ||
        frame[2] > 3 ||
        frame[1] >= frame[2] ||
        (_next != 0 && frame[2] != _total) ||
        (frame[1] < frame[2] - 1 && frame.length != 20)) {
      throw const BleAuthenticationException();
    }
    _total = frame[2];
    _next++;
    _pending.addAll(frame.skip(3));
    if (_pending.length > 40) throw const BleAuthenticationException();
    if (_next != _total) return null;
    final packet = List<int>.of(_pending);
    _pending.clear();
    _next = _total = 0;
    if (packet.length < 21) throw const BleAuthenticationException();
    return packet;
  }
}
