#pragma once

#include "secure_ble_session.h"

// Public test fixtures only; these bytes are NEVER a deployed pairing key.
// Generated independently with Node's HMAC-SHA256 and AES-128-GCM and shared
// with the Dart interoperability test. Run once at boot; fail closed on error.
inline bool secureBleSelfTest() {
  uint8_t psk[16], clientNonce[16], deviceNonce[16];
  for (size_t i = 0; i < 16; ++i) {
    psk[i] = i;
    clientNonce[i] = i + 16;
    deviceNonce[i] = i + 32;
  }
  const uint8_t clientPacket[21] = {
      0x00, 0x00, 0x00, 0x00, 0xb8, 0x37, 0xbe, 0xdd, 0x15, 0x54, 0x38,
      0x3c, 0x18, 0xe4, 0x67, 0x65, 0xf7, 0xc3, 0xc2, 0x33, 0x91};
  const uint8_t devicePacket[21] = {
      0x00, 0x00, 0x00, 0x00, 0xd5, 0x7b, 0x55, 0xdb, 0x8d, 0x1e, 0x0e,
      0xca, 0xa6, 0x19, 0x00, 0x82, 0xf8, 0x6a, 0x9d, 0x26, 0xf2};
  uint8_t first[20] = {0x44, 0, 2}, last[7] = {0x44, 1, 2};
  memcpy(first + 3, clientPacket, 17);
  memcpy(last + 3, clientPacket + 17, 4);
  SecureBleSession test;
  uint8_t plaintext[SecureBleSession::MaxPlaintext] = {0};
  size_t length = 0;
  if (!test.begin(psk, clientNonce, deviceNonce) ||
      test.receiveFragment(first, sizeof(first), plaintext, length) != 0 ||
      test.receiveFragment(last, sizeof(last), plaintext, length) != 1 ||
      length != 1 || plaintext[0] != 'P') return false;
  uint8_t output[SecureBleSession::MaxPacket] = {0};
  const uint8_t ready = 'T';
  if (!test.encrypt(&ready, 1, output, length) || length != sizeof(devicePacket) ||
      memcmp(output, devicePacket, sizeof(devicePacket)) != 0) return false;
  // The same authenticated packet cannot be replayed in the current session.
  if (test.receiveFragment(first, sizeof(first), plaintext, length) != 0 ||
      test.receiveFragment(last, sizeof(last), plaintext, length) != -1) return false;
  // A modified tag fails authentication even when its packet counter is valid.
  last[sizeof(last) - 1] ^= 1;
  if (!test.begin(psk, clientNonce, deviceNonce) ||
      test.receiveFragment(first, sizeof(first), plaintext, length) != 0 ||
      test.receiveFragment(last, sizeof(last), plaintext, length) != -1) return false;
  // Fragments must start at zero and arrive sequentially.
  if (!test.begin(psk, clientNonce, deviceNonce) ||
      test.receiveFragment(last, sizeof(last), plaintext, length) != -1) return false;
  test.reset();
  return true;
}
