#pragma once

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <mbedtls/gcm.h>
#include <mbedtls/md.h>
#include <mbedtls/platform_util.h>

// CarePulse v2. Callers serialize this object and the complete notification
// fragment sequence with a mutex. No key material or decrypted data is logged.
class SecureBleSession {
 public:
  static constexpr size_t MaxPlaintext = 20;
  static constexpr size_t MaxPacket = 40;

  SecureBleSession() {
    mbedtls_gcm_init(&incoming_);
    mbedtls_gcm_init(&outgoing_);
  }
  ~SecureBleSession() {
    mbedtls_gcm_free(&incoming_);
    mbedtls_gcm_free(&outgoing_);
  }
  SecureBleSession(const SecureBleSession &) = delete;
  SecureBleSession &operator=(const SecureBleSession &) = delete;

  void reset() {
    mbedtls_gcm_free(&incoming_);
    mbedtls_gcm_free(&outgoing_);
    mbedtls_gcm_init(&incoming_);
    mbedtls_gcm_init(&outgoing_);
    mbedtls_platform_zeroize(packet_, sizeof(packet_));
    incomingCounter_ = outgoingCounter_ = 0;
    used_ = fragmentIndex_ = fragmentCount_ = 0;
    started_ = false;
  }

  bool begin(const uint8_t psk[16], const uint8_t clientNonce[16],
             const uint8_t deviceNonce[16]) {
    reset();
    if (!derive(incoming_, IncomingLabel, psk, clientNonce, deviceNonce) ||
        !derive(outgoing_, OutgoingLabel, psk, clientNonce, deviceNonce)) {
      reset();
      return false;
    }
    started_ = true;
    return true;
  }

  // -1: invalid (caller must disconnect); 0: pending; 1: authenticated payload.
  int receiveFragment(const uint8_t *frame, size_t length,
                      uint8_t plaintext[MaxPlaintext], size_t &plainLength) {
    plainLength = 0;
    if (!started_ || length < 4 || length > 20 || frame[0] != 0x44 ||
        frame[2] < 2 || frame[2] > 3 || frame[1] != fragmentIndex_ ||
        frame[1] >= frame[2] ||
        (fragmentIndex_ != 0 && frame[2] != fragmentCount_) ||
        (frame[1] + 1 < frame[2] && length != 20) ||
        used_ + length - 3 > MaxPacket) return -1;
    if (fragmentIndex_ == 0) fragmentCount_ = frame[2];
    memcpy(packet_ + used_, frame + 3, length - 3);
    used_ += length - 3;
    ++fragmentIndex_;
    if (fragmentIndex_ != fragmentCount_) return 0;
    const size_t packetLength = used_;
    used_ = fragmentIndex_ = fragmentCount_ = 0;
    if (packetLength < 21 || packetLength > MaxPacket ||
        incomingCounter_ >= UINT32_MAX || readCounter(packet_) != incomingCounter_)
      return -1;
    const size_t payloadLength = packetLength - 20;
    uint8_t nonce[12] = {0};
    writeCounter(nonce + 8, incomingCounter_);
    const int result = mbedtls_gcm_auth_decrypt(
        &incoming_, payloadLength, nonce, sizeof(nonce),
        reinterpret_cast<const uint8_t *>(IncomingLabel), strlen(IncomingLabel),
        packet_ + 4 + payloadLength, 16, packet_ + 4, plaintext);
    mbedtls_platform_zeroize(packet_, sizeof(packet_));
    if (result != 0) {
      mbedtls_platform_zeroize(plaintext, MaxPlaintext);
      return -1;
    }
    ++incomingCounter_;
    plainLength = payloadLength;
    return 1;
  }

  bool encrypt(const uint8_t *plaintext, size_t length,
               uint8_t packet[MaxPacket], size_t &packetLength) {
    packetLength = 0;
    if (!started_ || length == 0 || length > MaxPlaintext ||
        outgoingCounter_ >= UINT32_MAX) return false;
    uint8_t nonce[12] = {0};
    writeCounter(nonce + 8, outgoingCounter_);
    writeCounter(packet, outgoingCounter_);
    const int result = mbedtls_gcm_crypt_and_tag(
        &outgoing_, MBEDTLS_GCM_ENCRYPT, length, nonce, sizeof(nonce),
        reinterpret_cast<const uint8_t *>(OutgoingLabel), strlen(OutgoingLabel),
        plaintext, packet + 4, 16, packet + 4 + length);
    if (result != 0) {
      mbedtls_platform_zeroize(packet, MaxPacket);
      return false;
    }
    ++outgoingCounter_;
    packetLength = length + 20;
    return true;
  }

 private:
  static constexpr const char *IncomingLabel = "CarePulse/v2/c2d";
  static constexpr const char *OutgoingLabel = "CarePulse/v2/d2c";
  mbedtls_gcm_context incoming_;
  mbedtls_gcm_context outgoing_;
  uint32_t incomingCounter_ = 0, outgoingCounter_ = 0;
  uint8_t packet_[MaxPacket] = {0};
  size_t used_ = 0;
  uint8_t fragmentIndex_ = 0, fragmentCount_ = 0;
  bool started_ = false;

  static uint32_t readCounter(const uint8_t *bytes) {
    return (static_cast<uint32_t>(bytes[0]) << 24) |
           (static_cast<uint32_t>(bytes[1]) << 16) |
           (static_cast<uint32_t>(bytes[2]) << 8) | bytes[3];
  }
  static void writeCounter(uint8_t *bytes, uint32_t value) {
    bytes[0] = value >> 24;
    bytes[1] = value >> 16;
    bytes[2] = value >> 8;
    bytes[3] = value;
  }
  static bool derive(mbedtls_gcm_context &context, const char *label,
                     const uint8_t psk[16], const uint8_t clientNonce[16],
                     const uint8_t deviceNonce[16]) {
    uint8_t material[64] = {0}, digest[32] = {0};
    const size_t labelLength = strlen(label);
    memcpy(material, label, labelLength);
    memcpy(material + labelLength, clientNonce, 16);
    memcpy(material + labelLength + 16, deviceNonce, 16);
    const mbedtls_md_info_t *sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    bool success = sha256 != nullptr &&
        mbedtls_md_hmac(sha256, psk, 16, material, labelLength + 32, digest) == 0;
    if (success) success = mbedtls_gcm_setkey(&context, MBEDTLS_CIPHER_ID_AES, digest, 128) == 0;
    mbedtls_platform_zeroize(material, sizeof(material));
    mbedtls_platform_zeroize(digest, sizeof(digest));
    return success;
  }
};
