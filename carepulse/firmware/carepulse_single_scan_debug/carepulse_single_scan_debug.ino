// CarePulse full firmware with SparkFun beat-based BPM + sliding-window SpO2.
// Open Serial Monitor at 9600 baud and send SCAN with a newline.
// The USB gateway sends SCAN <requestId> to correlate each result.
// The Flutter app can start a BLE scan; Serial remains for bench testing.

#include <Arduino.h>
#include <atomic>
#include <Wire.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_random.h>
#include <freertos/semphr.h>
#include "secure_ble_session.h"
#include "secure_ble_self_test.h"
#include "MAX30105.h"       // SparkFun's MAX30102-compatible sensor class
#include "heartRate.h"
#include "spo2_algorithm.h" // Calculates BPM and SpO2 from red/IR samples

// Wiring: sensor SDA/SCL = 18/19, green LED = 25, red LED = 26,
// passive piezo buzzer = 27. Each external LED needs its own resistor.
const int SDA_PIN = 18;
const int SCL_PIN = 19;
const int GREEN_LED = 25;
const int RED_LED = 26;
const int BUZZER = 27;

const unsigned long FINGER_SETTLE_MS = 1000; // Let contact settle before collection.
const unsigned long FINGER_GRACE_MS = 3000;
const unsigned long SAMPLE_WAIT_MS = 2000; // Sensor must send data within 2 seconds.
// Calibrate using measured no-finger and finger-present IR ranges on this unit.
// No-finger IR near 850 (and sometimes higher) does not make 900 a safe cutoff.
const uint32_t DEFAULT_FINGER_IR_MIN = 50000;
const uint32_t MIN_CALIBRATION_GAP = 10000;
const int FINGER_CONFIRMATION_SAMPLES = 3;
// Raw output at 9600 baud slows sampling; leave off for timed scans.
const bool DEBUG_RAW_DATA = false; // Enable only for sensor diagnostics.
const int ALGORITHM_SAMPLES = 100; // Maxim algorithm assumes 100 samples at 25 Hz.
const int SAMPLE_COUNT = ALGORITHM_SAMPLES;
const int UPDATE_SAMPLES = 25;
const byte RATE_SIZE = 4;
const byte MIN_VALID_RATES = 1;
const unsigned long SAMPLE_PERIOD_MS = 40; // 100 Hz / averaging 4 = 25 FIFO pairs/s.
const unsigned long MAX_SAMPLE_GAP_MS = 150;
const unsigned long MAX_BEAT_AGE_MS = 2000;

MAX30105 sensor;
Preferences preferences;
bool preferencesReady = false;
uint32_t redSamples[SAMPLE_COUNT];
uint32_t irSamples[SAMPLE_COUNT];
byte rates[RATE_SIZE] = {0};
byte rateSpot = 0, validRates = 0;
unsigned long lastBeat = 0, lastAcceptedBeat = 0;
bool haveBeat = false;
float beatsPerMinute = 0;
int beatAvg = 0;
int32_t spo2 = 0, algorithmHeartRate = 0;
int8_t validSPO2 = 0, validHeartRate = 0;
unsigned long sampleDiscontinuities = 0;
struct ScanDiagnostics {
  uint32_t minIr = UINT32_MAX, maxIr = 0, minRed = UINT32_MAX, maxRed = 0;
  unsigned long received = 0, belowThreshold = 0;
  unsigned long detectedBeats = 0, acceptedIntervals = 0, rejectedIntervals = 0;
  unsigned long windows = 0, validOxygenWindows = 0;
  unsigned long contactResets = 0, sampleResets = 0, staleResets = 0;
  unsigned long maxGapMs = 0;
  int collected = 0;
} scanDebug;
uint32_t fingerIrMin = DEFAULT_FINGER_IR_MIN;
uint32_t emptyIrMax = 0;
bool emptyCalibrationReady = false;
std::atomic<bool> sensorReady{false};
bool greenOn = true;
unsigned long lastBlink = 0;
String lastRequestId;
char pendingBleRequestId[9] = {0};
portMUX_TYPE bleQueueMux = portMUX_INITIALIZER_UNLOCKED;
bool scanActive = false;
bool pendingMonitor = false;
char activeBleRequestId[9] = {0};
std::atomic<bool> cancelRequested{false};
BLECharacteristic *eventCharacteristic = nullptr;
std::atomic<bool> bleConnected{false};
std::atomic<bool> bleReady{false};
std::atomic<bool> restartAdvertising{false};
BLEServer *bleServer = nullptr;
bool activeBleScan = false;
char lastBleRequestId[9] = {0};
SemaphoreHandle_t bleSessionMutex = nullptr;
SecureBleSession bleSession;
uint8_t blePsk[16] = {0};
bool blePskReady = false;
enum class BlePhase { Closed, AwaitHello, AwaitProof, Ready };
BlePhase blePhase = BlePhase::Closed;
unsigned long bleConnectedAt = 0, bleLastActivityAt = 0;
const unsigned long BLE_HANDSHAKE_TIMEOUT_MS = 20000;
const unsigned long BLE_IDLE_TIMEOUT_MS = 120000;

// BLE callbacks and loop() run on different tasks. A recursive mutex permits a
// command callback to send a response without interleaving encrypted fragments.
class BleSessionLock {
 public:
  BleSessionLock() { xSemaphoreTakeRecursive(bleSessionMutex, portMAX_DELAY); }
  ~BleSessionLock() { xSemaphoreGiveRecursive(bleSessionMutex); }
};

const char *BLE_SERVICE_ID = "11c0a001-9ef2-4b77-9f6c-111111111111";
const char *BLE_COMMAND_ID = "11c0a002-9ef2-4b77-9f6c-111111111111";
const char *BLE_EVENT_ID = "11c0a003-9ef2-4b77-9f6c-111111111111";

void bleControlEvent(const uint8_t *frame, size_t length) {
  if (!bleConnected || eventCharacteristic == nullptr) return;
  eventCharacteristic->setValue(frame, length);
  eventCharacteristic->notify();
}

// Called with bleSessionMutex held. Closing immediately also prevents loop()
// from emitting any more data while the asynchronous disconnect is pending.
void closeBleSession() {
  const bool wasConnected = bleConnected.exchange(false);
  bleReady = false;
  blePhase = BlePhase::Closed;
  bleSession.reset();
  portENTER_CRITICAL(&bleQueueMux);
  pendingBleRequestId[0] = 0;
  lastBleRequestId[0] = 0;
  portEXIT_CRITICAL(&bleQueueMux);
  if (wasConnected && bleServer != nullptr) bleServer->disconnect(bleServer->getConnId());
}

bool encryptedBleReply(const uint8_t *plaintext, size_t length) {
  uint8_t packet[SecureBleSession::MaxPacket];
  size_t packetLength = 0;
  if (!bleSession.encrypt(plaintext, length, packet, packetLength)) {
    closeBleSession();
    return false;
  }
  const uint8_t count = (packetLength + 16) / 17;
  for (uint8_t index = 0; index < count; ++index) {
    const size_t offset = index * 17;
    const size_t remaining = packetLength - offset;
    const size_t payloadLength = remaining < 17 ? remaining : 17;
    uint8_t fragment[20] = {0x44, index, count};
    memcpy(fragment + 3, packet + offset, payloadLength);
    bleControlEvent(fragment, payloadLength + 3);
  }
  mbedtls_platform_zeroize(packet, sizeof(packet));
  bleLastActivityAt = millis();
  return true;
}

void bleReply(const String &frame) {
  if (bleSessionMutex == nullptr) return;
  BleSessionLock lock;
  if (!bleConnected || !bleReady || eventCharacteristic == nullptr) return;
  encryptedBleReply(reinterpret_cast<const uint8_t *>(frame.c_str()), frame.length());
}

void bleEvent(const String &frame) {
  // Serial measurements never belong to the connected phone.
  if (activeBleScan) bleReply(frame);
}

void clearSamples() {
  while (sensor.available()) sensor.nextSample();
  sensor.clearFIFO();
}

bool validBleId(const String &id) {
  if (id.length() != 8) return false;
  for (int i = 0; i < 8; i++) {
    char c = id.charAt(i);
    if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) return false;
  }
  return true;
}

class CarePulseServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    BleSessionLock lock;
    bleSession.reset();
    bleConnected = true;
    bleReady = false;
    blePhase = BlePhase::AwaitHello;
    bleConnectedAt = bleLastActivityAt = millis();
    server->getAdvertising()->stop();
  }
  void onDisconnect(BLEServer *server) override {
    BleSessionLock lock;
    bleConnected = false;
    bleReady = false;
    blePhase = BlePhase::Closed;
    bleSession.reset();
    portENTER_CRITICAL(&bleQueueMux);
    pendingBleRequestId[0] = 0;
    lastBleRequestId[0] = 0;
    portEXIT_CRITICAL(&bleQueueMux);
    // loop() restarts advertising after the old scan finishes, so its
    // notifications cannot reach a newly connected phone.
    restartAdvertising = true;
  }
};

class CarePulseCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    auto raw = characteristic->getValue();
    const uint8_t *bytes = reinterpret_cast<const uint8_t *>(raw.c_str());
    const size_t length = raw.length();
    BleSessionLock lock;
    if (!bleConnected) return;
    if (blePhase == BlePhase::AwaitHello) {
      if (length != 17 || bytes[0] != 0x48 || !blePskReady ||
          millis() - bleConnectedAt >= BLE_HANDSHAKE_TIMEOUT_MS) {
        closeBleSession();
        return;
      }
      uint8_t response[17] = {0x52};
      esp_fill_random(response + 1, 16);
      if (!bleSession.begin(blePsk, bytes + 1, response + 1)) {
        closeBleSession();
        return;
      }
      blePhase = BlePhase::AwaitProof;
      bleControlEvent(response, sizeof(response));
      mbedtls_platform_zeroize(response, sizeof(response));
      return;
    }
    if (blePhase != BlePhase::Ready && blePhase != BlePhase::AwaitProof) {
      closeBleSession();
      return;
    }
    if (blePhase == BlePhase::AwaitProof &&
        millis() - bleConnectedAt >= BLE_HANDSHAKE_TIMEOUT_MS) {
      closeBleSession();
      return;
    }
    uint8_t plaintext[SecureBleSession::MaxPlaintext + 1] = {0};
    size_t plainLength = 0;
    const int received = bleSession.receiveFragment(bytes, length, plaintext, plainLength);
    if (received < 0) {
      closeBleSession();
      return;
    }
    if (received == 0) return;
    bleLastActivityAt = millis();
    if (blePhase == BlePhase::AwaitProof) {
      if (plainLength != 1 || plaintext[0] != 'P') {
        closeBleSession();
        return;
      }
      const uint8_t ready = 'T';
      if (encryptedBleReply(&ready, 1)) {
        blePhase = BlePhase::Ready;
        bleReady = true;
      }
      return;
    }
    if (plainLength != 10 || plaintext[1] != '|' ||
        (plaintext[0] != 'S' && plaintext[0] != 'M' && plaintext[0] != 'X')) {
      closeBleSession();
      return;
    }
    String command = String(reinterpret_cast<const char *>(plaintext));
    mbedtls_platform_zeroize(plaintext, sizeof(plaintext));
    String id = command.substring(2);
    if (!validBleId(id)) { closeBleSession(); return; }
    if (command.startsWith("X|")) {
      portENTER_CRITICAL(&bleQueueMux);
      if (strcmp(activeBleRequestId, id.c_str()) == 0 ||
          strcmp(pendingBleRequestId, id.c_str()) == 0) cancelRequested = true;
      portEXIT_CRITICAL(&bleQueueMux);
      return;
    }
    if (!sensorReady) {
      bleReply("E|" + id + "|SE");
      return;
    }
    // The sensor routine runs in loop(), never inside a BLE callback.
    portENTER_CRITICAL(&bleQueueMux);
    const bool duplicate = strcmp(lastBleRequestId, id.c_str()) == 0;
    const bool busy = scanActive || pendingBleRequestId[0] != 0;
    if (!busy && !duplicate) {
      cancelRequested = false;
      pendingMonitor = command.startsWith("M|");
      memcpy(pendingBleRequestId, id.c_str(), 9);
      memcpy(lastBleRequestId, id.c_str(), 9);
    }
    portEXIT_CRITICAL(&bleQueueMux);
    // A retransmission of the running request must not terminate that scan.
    if (duplicate && busy) return;
    if (busy || duplicate) bleReply("E|" + id + (busy ? "|BS" : "|DU"));
  }
};

bool loadBleKey() {
  if (!preferencesReady) return false;
  if (preferences.isKey("ble_psk")) {
    return preferences.getBytesLength("ble_psk") == sizeof(blePsk) &&
           preferences.getBytes("ble_psk", blePsk, sizeof(blePsk)) == sizeof(blePsk);
  }
  esp_fill_random(blePsk, sizeof(blePsk));
  uint8_t saved[sizeof(blePsk)] = {0};
  const bool persisted = preferences.putBytes("ble_psk", blePsk, sizeof(blePsk)) == sizeof(blePsk) &&
      preferences.getBytes("ble_psk", saved, sizeof(saved)) == sizeof(saved) &&
      memcmp(blePsk, saved, sizeof(saved)) == 0;
  mbedtls_platform_zeroize(saved, sizeof(saved));
  if (!persisted) mbedtls_platform_zeroize(blePsk, sizeof(blePsk));
  return persisted;
}

void printBlePairingKey() {
  if (!blePskReady) {
    Serial.println("PAIR_ERROR storage_unavailable");
    return;
  }
  // Physical USB is the only provisioning channel. Never put this key in BLE
  // advertisements, normal diagnostics, source code, or cloud measurements.
  for (size_t i = 0; i < sizeof(blePsk); ++i) Serial.printf("%02X", blePsk[i]);
  Serial.println();
}

void serviceBleTimeouts() {
  if (bleSessionMutex == nullptr || !bleConnected) return;
  BleSessionLock lock;
  if (!bleConnected) return;
  const unsigned long now = millis();
  if (blePhase != BlePhase::Ready) {
    if (now - bleConnectedAt >= BLE_HANDSHAKE_TIMEOUT_MS) closeBleSession();
    return;
  }
  portENTER_CRITICAL(&bleQueueMux);
  const bool busy = scanActive || pendingBleRequestId[0] != 0;
  portEXIT_CRITICAL(&bleQueueMux);
  if (!busy && now - bleLastActivityAt >= BLE_IDLE_TIMEOUT_MS) closeBleSession();
}

void setupBle() {
  bleSessionMutex = xSemaphoreCreateRecursiveMutex();
  if (bleSessionMutex == nullptr) {
    Serial.println("state=error reason=ble_mutex_failed");
    return;
  }
  BLEDevice::init("CarePulse");
  if (!secureBleSelfTest()) {
    Serial.println("state=error reason=ble_security_self_test_failed");
    return;
  }
  // Starting Bluetooth enables the ESP32 hardware entropy source before key
  // generation. A missing or corrupt persisted key disables BLE completely.
  blePskReady = loadBleKey();
  if (!blePskReady) {
    Serial.println("state=error reason=ble_key_storage_failed");
    return;
  }
  BLEServer *server = BLEDevice::createServer();
  bleServer = server;
  server->setCallbacks(new CarePulseServerCallbacks());
  BLEService *service = server->createService(BLE_SERVICE_ID);
  BLECharacteristic *command = service->createCharacteristic(
      BLE_COMMAND_ID, BLECharacteristic::PROPERTY_WRITE);
  command->setCallbacks(new CarePulseCommandCallbacks());
  eventCharacteristic = service->createCharacteristic(
      BLE_EVENT_ID, BLECharacteristic::PROPERTY_NOTIFY);
  eventCharacteristic->addDescriptor(new BLE2902());
  service->start();
  server->getAdvertising()->addServiceUUID(BLE_SERVICE_ID);
  server->getAdvertising()->start();
}


void beep(int times, int lengthMs) {
  for (int i = 0; i < times; i++) {
    ledcWriteTone(BUZZER, 2000);
    delay(lengthMs);
    ledcWriteTone(BUZZER, 0);
    if (i + 1 < times) delay(100);
  }
}

void showReady() {
  digitalWrite(RED_LED, LOW);
  digitalWrite(GREEN_LED, HIGH);
  Serial.println("state=ready command=SCAN");
}

void printFailureDiagnostics() {
  Serial.printf("DEBUG_CONTACT threshold=%lu received=%lu below=%lu ir_min=%lu ir_max=%lu red_min=%lu red_max=%lu\n",
                static_cast<unsigned long>(fingerIrMin), scanDebug.received,
                scanDebug.belowThreshold,
                static_cast<unsigned long>(scanDebug.received ? scanDebug.minIr : 0),
                static_cast<unsigned long>(scanDebug.maxIr),
                static_cast<unsigned long>(scanDebug.received ? scanDebug.minRed : 0),
                static_cast<unsigned long>(scanDebug.maxRed));
  Serial.printf("DEBUG_BEATS detected=%lu accepted=%lu rejected=%lu current_count=%u required=%u avg=%d\n",
                scanDebug.detectedBeats, scanDebug.acceptedIntervals,
                scanDebug.rejectedIntervals, validRates, MIN_VALID_RATES, beatAvg);
  Serial.printf("DEBUG_OXYGEN windows=%lu valid_windows=%lu latest=%ld valid=%d collected=%d required=%d\n",
                scanDebug.windows, scanDebug.validOxygenWindows,
                static_cast<long>(spo2), validSPO2, scanDebug.collected, SAMPLE_COUNT);
  Serial.printf("DEBUG_RESETS contact=%lu sampling=%lu stale_beats=%lu max_gap_ms=%lu deadline=none\n",
                scanDebug.contactResets, scanDebug.sampleResets,
                scanDebug.staleResets, scanDebug.maxGapMs);
}

void invalidScan(const char *reason, const String &requestId) {
  printFailureDiagnostics();
  resetMeasurement();
  Serial.printf("state=invalid_scan reason=%s requestId=%s\n",
                reason, requestId.c_str());
  String code = "AR";
  if (strcmp(reason, "no_finger") == 0) code = "NF";
  else if (strcmp(reason, "finger_removed") == 0) code = "FR";
  else if (strcmp(reason, "too_few_samples") == 0) code = "FS";
  else if (strcmp(reason, "poor_signal") == 0 ||
           strcmp(reason, "unstable_pulse") == 0) code = "SQ";
  bleEvent("I|" + requestId + "|" + code);
  beep(1, 500);
  showReady();
}

void sensorError(const char *reason, const String &requestId = "") {
  if (requestId.length() > 0) {
    printFailureDiagnostics();
    resetMeasurement();
    Serial.printf("state=error reason=%s requestId=%s\n",
                  reason, requestId.c_str());
  } else {
    Serial.printf("state=error reason=%s\n", reason);
  }
  if (requestId.length() == 8) bleEvent("E|" + requestId + "|TO");
  sensorReady = false;
  digitalWrite(GREEN_LED, LOW);
  digitalWrite(RED_LED, HIGH);
  beep(3, 100);
}

// Bound input work so partial or oversized commands cannot stall sampling.
bool readSerialCommand(String &command, bool busy = false) {
  static char line[70];
  static size_t used = 0;
  static bool discard = false;
  for (int budget = 0; budget < 32 && Serial.available(); budget++) {
    const char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      if (discard) {
        Serial.println(busy ? "error=busy" : "error=discarded_command");
        discard = false;
        used = 0;
        continue;
      }
      line[used] = 0;
      command = line;
      used = 0;
      command.trim();
      if (busy) {
        if (command == "CANCEL") cancelRequested = true;
        else if (command.length()) Serial.println("error=busy");
        return false;
      }
      return command.length() > 0;
    }
    if (!discard) {
      if (used < sizeof(line) - 1) line[used++] = c;
      else { used = 0; discard = true; }
    }
  }
  return false;
}

// Read one pair of red and infrared values from the MAX30102.
// Return false if no new reading arrives within 2 seconds.
bool readSample(uint32_t &red, uint32_t &ir, unsigned long timeoutMs = SAMPLE_WAIT_MS) {
  unsigned long started = millis();
  while (millis() - started < timeoutMs) {
    serviceBleTimeouts();
    if (cancelRequested || (activeBleScan && !bleConnected)) return false;
    // A second SCAN cannot start while this one is running.
    String ignored;
    readSerialCommand(ignored, true);
    if (cancelRequested || (activeBleScan && !bleConnected)) return false;

    // Drain the software FIFO before fetching another batch into its 4 slots.
    const uint16_t arrived = sensor.available() ? 0 : sensor.check();
    if (arrived >= 4) {
      // SparkFun's four-slot software FIFO cannot retain this whole batch.
      clearSamples();
      ++sampleDiscontinuities;
      continue;
    }
    if (sensor.available()) {
      red = sensor.getFIFORed();
      ir = sensor.getFIFOIR();
      sensor.nextSample();
      if (scanActive) {
        ++scanDebug.received;
        if (ir < fingerIrMin) ++scanDebug.belowThreshold;
        if (ir < scanDebug.minIr) scanDebug.minIr = ir;
        if (ir > scanDebug.maxIr) scanDebug.maxIr = ir;
        if (red < scanDebug.minRed) scanDebug.minRed = red;
        if (red > scanDebug.maxRed) scanDebug.maxRed = red;
      }
      return true;
    }

    // Blink green while waiting for a finger and while scanning.
    if (millis() - lastBlink >= 350) {
      greenOn = !greenOn;
      digitalWrite(GREEN_LED, greenOn);
      lastBlink = millis();
    }
    delay(1);
  }
  return false;
}

// Run with the sensor already mounted in its final housing. CAL EMPTY must
// precede CAL FINGER so ambient light and housing reflections are included.
void calibrateSensor(bool fingerPresent) {
  if (!sensorReady) {
    Serial.println("CAL_ERROR sensor_not_ready");
    return;
  }
  if (fingerPresent && !emptyCalibrationReady) {
    Serial.println("CAL_ERROR run_CAL_EMPTY_first");
    return;
  }
  clearSamples();
  uint32_t minIr = UINT32_MAX;
  uint32_t maxIr = 0;
  uint64_t sumIr = 0;
  uint32_t red = 0;
  uint32_t ir = 0;
  unsigned long started = millis();
  for (int i = 0; i < 50; i++) {
    if (!readSample(red, ir) || millis() - started > 3500) {
      Serial.println("CAL_ERROR sensor_timeout");
      return;
    }
    if (ir < minIr) minIr = ir;
    if (ir > maxIr) maxIr = ir;
    sumIr += ir;
  }
  Serial.printf("CAL_%s min_ir=%lu max_ir=%lu mean_ir=%lu\n",
                fingerPresent ? "FINGER" : "EMPTY",
                static_cast<unsigned long>(minIr),
                static_cast<unsigned long>(maxIr),
                static_cast<unsigned long>(sumIr / 50));
  if (!fingerPresent) {
    emptyIrMax = maxIr;
    emptyCalibrationReady = true;
    Serial.println("CAL_NEXT place_finger_then_send_CAL_FINGER");
    return;
  }
  if (minIr <= emptyIrMax || minIr - emptyIrMax < MIN_CALIBRATION_GAP) {
    Serial.println("CAL_ERROR weak_finger_signal_check_contact_and_housing");
    return;
  }
  const uint32_t candidate = emptyIrMax + (minIr - emptyIrMax) / 2;
  if (!preferences.putUInt("finger_ir", candidate)) {
    Serial.println("CAL_ERROR could_not_save_threshold");
    return;
  }
  fingerIrMin = candidate;
  emptyCalibrationReady = false;
  Serial.printf("CAL_SAVED finger_ir_min=%lu\n",
                static_cast<unsigned long>(fingerIrMin));
}

float printScanSummary(unsigned long scanStarted, unsigned long totalSamples,
                       unsigned long validSamples, int collectedSamples) {
  unsigned long durationMs = millis() - scanStarted;
  float sampleRate = durationMs == 0 ? 0.0f :
      totalSamples * 1000.0f / durationMs;
  Serial.printf("SCAN_SUMMARY duration_ms=%lu total_samples=%lu "
                "valid_samples=%lu collected_samples=%d sample_rate=%.2f\n",
                durationMs, totalSamples, validSamples, collectedSamples, sampleRate);
  return sampleRate;
}

// Debug messages may be dropped if Serial is busy; samples take priority.
void debugLine(const char *line) {
  const size_t length = strlen(line);
  if (Serial.availableForWrite() >= static_cast<int>(length)) {
    Serial.write(reinterpret_cast<const uint8_t *>(line), length);
  }
}

void resetHeartRate() {
  memset(rates, 0, sizeof(rates));
  rateSpot = validRates = 0;
  lastBeat = lastAcceptedBeat = 0;
  haveBeat = false;
  beatsPerMinute = 0;
  beatAvg = 0;
}

void resetMeasurement() {
  resetHeartRate();
  spo2 = algorithmHeartRate = 0;
  validSPO2 = validHeartRate = 0;
}

void processHeartBeat(uint32_t ir, unsigned long sampleTime, bool settled) {
  // Feed each fresh sample, including settling, to warm the library's FIR.
  const bool detected = checkForBeat(ir);
  if (!settled || !detected) return;
  ++scanDebug.detectedBeats;
  if (!haveBeat) {
    lastBeat = sampleTime;
    haveBeat = true;
    debugLine("BEAT first=1\n");
    return;
  }
  const unsigned long delta = sampleTime - lastBeat;
  lastBeat = sampleTime;
  if (!delta) return;
  beatsPerMinute = 60000.0f / delta;
  const bool accepted = beatsPerMinute > 35 && beatsPerMinute < 220;
  if (accepted) {
    ++scanDebug.acceptedIntervals;
    rates[rateSpot] = static_cast<byte>(beatsPerMinute);
    rateSpot = (rateSpot + 1) % RATE_SIZE;
    if (validRates < RATE_SIZE) ++validRates;
    int total = 0;
    for (byte i = 0; i < validRates; ++i) total += rates[i];
    beatAvg = total / validRates;
    lastAcceptedBeat = sampleTime;
  } else {
    ++scanDebug.rejectedIntervals;
  }
  char line[128];
  snprintf(line, sizeof(line),
           "BEAT interval_ms=%lu bpm=%.1f avg=%d count=%u accepted=%d\n",
           delta, beatsPerMinute, beatAvg, validRates, accepted);
  debugLine(line);
}

void calculateSpO2() {
  ++scanDebug.windows;
  maxim_heart_rate_and_oxygen_saturation(
      irSamples, ALGORITHM_SAMPLES, redSamples,
      &spo2, &validSPO2, &algorithmHeartRate, &validHeartRate);
  if (validSPO2 && spo2 >= 0 && spo2 <= 100) ++scanDebug.validOxygenWindows;
  char line[128];
  snprintf(line, sizeof(line),
           "ALGORITHM maxim_bpm=%ld hr_valid=%d spo2=%ld spo2_valid=%d\n",
           static_cast<long>(algorithmHeartRate), validHeartRate,
           static_cast<long>(spo2), validSPO2);
  debugLine(line);
}

bool endRequested(const String &requestId) {
  if (!cancelRequested && !(activeBleScan && !bleConnected)) return false;
  resetMeasurement();
  clearSamples();
  Serial.printf("state=cancelled requestId=%s\n", requestId.c_str());
  bleEvent("A|" + requestId);
  showReady();
  return true;
}

void startScan(const String &requestId, bool monitor = false) {
  scanDebug = ScanDiagnostics{};
  resetMeasurement();
  unsigned long requestStarted = millis();
  uint32_t red = 0;
  uint32_t ir = 0;
  int fingerReadings = 0;
  greenOn = true;
  lastBlink = millis();
  digitalWrite(GREEN_LED, HIGH);
  clearSamples();
  Serial.printf("state=waiting_for_finger requestId=%s\n", requestId.c_str());
  if (requestId.length() == 8) bleEvent("W|" + requestId);

  // Step A: three readings above the calibrated IR threshold mean contact.
  const unsigned long fingerWaitStarted = millis();
  while (fingerReadings < FINGER_CONFIRMATION_SAMPLES &&
         millis() - fingerWaitStarted < FINGER_GRACE_MS) {
    const unsigned long remaining = FINGER_GRACE_MS - (millis() - fingerWaitStarted);
    const unsigned long timeout = remaining < SAMPLE_WAIT_MS ? remaining : SAMPLE_WAIT_MS;
    if (!readSample(red, ir, timeout)) {
      if (endRequested(requestId)) return;
      if (millis() - fingerWaitStarted >= FINGER_GRACE_MS) break;
      sensorError("sensor_timeout", requestId);
      return;
    }
    if (millis() - fingerWaitStarted >= FINGER_GRACE_MS) break;
    fingerReadings = ir >= fingerIrMin ? fingerReadings + 1 : 0;
  }
  if (fingerReadings < FINGER_CONFIRMATION_SAMPLES) {
    invalidScan("no_finger", requestId);
    return;
  }

  clearSamples();
  resetMeasurement();
  Serial.printf("state=scanning requestId=%s\n", requestId.c_str());
  if (requestId.length() == 8) bleEvent("S|" + requestId);
  int saved = 0, newSamples = 0;
  unsigned long totalSamples = 0, validSamples = 0;
  const unsigned long scanStarted = millis();
  unsigned long settleStarted = scanStarted;
  unsigned long fingerMissingSince = 0;
  bool fingerMissing = false;
  unsigned long lastReceivedAt = millis();
  unsigned long discontinuity = sampleDiscontinuities;
  // Timestamp samples at the configured FIFO cadence, so draining a short
  // queued batch does not turn two real beats into the same millis() time.
  unsigned long sampleTime = scanStarted;
  bool processingSent = false;
  // Contact and valid results determine scan duration; no overall deadline.
  while (true) {
    if (!readSample(red, ir)) {
      if (endRequested(requestId)) return;
      printScanSummary(scanStarted, totalSamples, validSamples, saved);
      sensorError("sensor_timeout", requestId);
      return;
    }
    if (endRequested(requestId)) return;
    const unsigned long receivedAt = millis();
    ++totalSamples;
    const unsigned long sampleGap = receivedAt - lastReceivedAt;
    if (sampleGap > scanDebug.maxGapMs) scanDebug.maxGapMs = sampleGap;
    if (sampleDiscontinuities != discontinuity ||
        receivedAt - lastReceivedAt > MAX_SAMPLE_GAP_MS) {
      ++scanDebug.sampleResets;
      resetMeasurement();
      saved = newSamples = scanDebug.collected = 0;
      settleStarted = receivedAt;
      sampleTime = receivedAt;
      discontinuity = sampleDiscontinuities;
      debugLine("RESET reason=sample_discontinuity\n");
      if (monitor) bleEvent("U|" + requestId);
    } else {
      sampleTime += SAMPLE_PERIOD_MS;
    }
    lastReceivedAt = receivedAt;

    const bool fingerPresent = ir >= fingerIrMin;
    if (!fingerPresent) {
      if (!fingerMissing) {
        fingerMissing = true;
        fingerMissingSince = receivedAt;
        ++scanDebug.contactResets;
        resetMeasurement();
        saved = newSamples = scanDebug.collected = 0;
        debugLine("CONTACT missing grace_ms=3000\n");
        if (monitor) bleEvent("F|" + requestId);
      }
      if (receivedAt - fingerMissingSince >= FINGER_GRACE_MS) {
        printScanSummary(scanStarted, totalSamples, validSamples, saved);
        invalidScan("finger_removed", requestId);
        return;
      }
      continue;
    }
    if (fingerMissing) {
      fingerMissing = false;
      settleStarted = receivedAt;
      debugLine("CONTACT restored=1\n");
      if (monitor) bleEvent("U|" + requestId);
    }
    ++validSamples;
    const bool settled = receivedAt - settleStarted >= FINGER_SETTLE_MS;
    if (validRates && sampleTime - lastAcceptedBeat > MAX_BEAT_AGE_MS) {
      ++scanDebug.staleResets;
      resetHeartRate();
      debugLine("RESET reason=stale_beats\n");
      if (monitor) bleEvent("U|" + requestId);
    }
    processHeartBeat(ir, sampleTime, settled);
    if (!settled) continue;

    if (saved == SAMPLE_COUNT) {
      memmove(redSamples, redSamples + 1, (SAMPLE_COUNT - 1) * sizeof(redSamples[0]));
      memmove(irSamples, irSamples + 1, (SAMPLE_COUNT - 1) * sizeof(irSamples[0]));
      --saved;
    }
    redSamples[saved] = red;
    irSamples[saved++] = ir;
    scanDebug.collected = saved;
    ++newSamples;
    if (saved != SAMPLE_COUNT || newSamples < UPDATE_SAMPLES) continue;
    newSamples = 0;
    if (!processingSent) {
      Serial.printf("state=processing requestId=%s\n", requestId.c_str());
      if (requestId.length() == 8) bleEvent("P|" + requestId);
      processingSent = true;
    }
    calculateSpO2();
    // SpO2's independent HR estimate is diagnostic only.
    if (validRates >= MIN_VALID_RATES && sampleTime - lastAcceptedBeat <= MAX_BEAT_AGE_MS &&
        validSPO2 && spo2 >= 0 && spo2 <= 100) {
      if (endRequested(requestId)) return;
      if (!monitor) break;
      bleEvent("V|" + requestId + "|" + String(beatAvg) + "|" + String(spo2));
      Serial.printf("state=monitoring requestId=%s bpm=%d spo2=%ld\n",
                    requestId.c_str(), beatAvg, static_cast<long>(spo2));
    } else if (monitor) {
      bleEvent("U|" + requestId);
    }
  }

  const unsigned long scanElapsedMs = millis() - requestStarted;
  const float measuredSampleRate = printScanSummary(
      scanStarted, totalSamples, validSamples, saved);
  Serial.printf("state=complete requestId=%s bpm=%d spo2=%ld "
                "durationSeconds=%lu sample_rate=%.2f\n",
                requestId.c_str(), beatAvg, static_cast<long>(spo2),
                (scanElapsedMs + 999) / 1000, measuredSampleRate);
  if (requestId.length() == 8) {
    bleEvent("C|" + requestId + "|" + String(beatAvg) + "|" + String(spo2));
  }
  resetMeasurement();
  beep(2, 100);
  showReady();
}

void setup() {
  Serial.setTxBufferSize(512);
  Serial.begin(9600);
  pinMode(GREEN_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);
  digitalWrite(RED_LED, HIGH); // Red means the device is starting.

  if (!ledcAttach(BUZZER, 2000, 8)) {
    Serial.println("state=error reason=buzzer_setup_failed");
    return;
  }
  preferencesReady = preferences.begin("carepulse", false);
  if (preferencesReady) {
    fingerIrMin = preferences.getUInt("finger_ir", DEFAULT_FINGER_IR_MIN);
  } else {
    Serial.println("CAL_WARNING storage_unavailable_using_default");
  }
  setupBle();
  Serial.printf("CAL_CURRENT finger_ir_min=%lu\n",
                static_cast<unsigned long>(fingerIrMin));
  if (!Wire.begin(SDA_PIN, SCL_PIN)) {
    sensorError("i2c_setup_failed");
    return;
  }
  if (!sensor.begin(Wire, I2C_SPEED_FAST)) {
    sensorError("max30102_not_found");
    return;
  }

  // 100 conversions/s averaged by 4 = about 25 red/IR pairs each second.
  sensor.setup(60, 4, 2, 100, 411, 4096);
  sensor.setPulseAmplitudeGreen(0);
  clearSamples();
  sensorReady = true;
  showReady();
}

void loop() {
  serviceBleTimeouts();
  if (restartAdvertising.exchange(false) && bleServer != nullptr) {
    bleServer->getAdvertising()->start();
  }
  if (!sensorReady) {
    String command;
    if (readSerialCommand(command)) {
      if (command == "PAIR") printBlePairingKey();
      else Serial.println("error=sensor_not_ready");
    }
    delay(10);
    return;
  }

  char queuedId[9] = {0};
  bool queuedMonitor = false;
  portENTER_CRITICAL(&bleQueueMux);
  if (pendingBleRequestId[0] != 0) {
    memcpy(queuedId, pendingBleRequestId, 9);
    memcpy(activeBleRequestId, pendingBleRequestId, 9);
    queuedMonitor = pendingMonitor;
    pendingBleRequestId[0] = 0;
    scanActive = true;
  }
  portEXIT_CRITICAL(&bleQueueMux);
  if (queuedId[0] != 0) {
    String id = String(queuedId);
    activeBleScan = true;
    startScan(id, queuedMonitor);
    activeBleScan = false;
    cancelRequested = false;
    portENTER_CRITICAL(&bleQueueMux);
    scanActive = false;
    activeBleRequestId[0] = 0;
    portEXIT_CRITICAL(&bleQueueMux);
    return;
  }
  if (!Serial.available()) {
    delay(10);
    return;
  }

  // Reserve the sensor before reading or executing a Serial command.
  portENTER_CRITICAL(&bleQueueMux);
  const bool bleQueued = pendingBleRequestId[0] != 0;
  if (!bleQueued) scanActive = true;
  portEXIT_CRITICAL(&bleQueueMux);
  if (bleQueued) return;
  String command;
  if (!readSerialCommand(command)) {
    portENTER_CRITICAL(&bleQueueMux);
    scanActive = false;
    portEXIT_CRITICAL(&bleQueueMux);
    delay(1);
    return;
  }
  cancelRequested = false;
  if (command == "PAIR") {
    printBlePairingKey();
  } else if (command == "MONITOR") {
    startScan("manual_" + String(millis()), true);
  } else if (command == "CANCEL") {
    Serial.println("state=ready command=SCAN");
  } else if (command == "CAL EMPTY") {
    calibrateSensor(false);
  } else if (command == "CAL FINGER") {
    calibrateSensor(true);
  } else if (command == "CAL RESET") {
    preferences.remove("finger_ir");
    fingerIrMin = DEFAULT_FINGER_IR_MIN;
    emptyCalibrationReady = false;
    Serial.println("CAL_RESET using_default_threshold");
  } else if (command == "SCAN") {
    startScan("manual_" + String(millis()));
  } else if (command.startsWith("SCAN ")) {
    String requestId = command.substring(5);
    requestId.trim();
    bool valid = requestId.length() > 0 && requestId.length() <= 64;
    for (unsigned int i = 0; i < requestId.length(); i++) {
      char ch = requestId.charAt(i);
      if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
            (ch >= '0' && ch <= '9') || ch == '_' || ch == '-')) valid = false;
    }
    if (valid && requestId == lastRequestId) {
      Serial.println("error=duplicate_request");
    } else if (valid) {
      lastRequestId = requestId;
      startScan(requestId);
    }
    else Serial.println("error=invalid_request_id");
  } else if (command.length() > 0) {
    Serial.println("error=unknown_command use=SCAN");
  }
  portENTER_CRITICAL(&bleQueueMux);
  scanActive = false;
  portEXIT_CRITICAL(&bleQueueMux);
}
