// CarePulse beginner sketch for ESP32 + MAX30102.
// Open Serial Monitor at 9600 baud and send SCAN with a newline.
// The USB gateway sends SCAN <requestId> to correlate each result.
// The Flutter app is still a demo; this sketch is tested through USB Serial.

#include <Arduino.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "MAX30105.h"       // SparkFun's MAX30102-compatible sensor class
#include "spo2_algorithm.h" // Calculates BPM and SpO2 from red/IR samples

// Wiring: sensor SDA/SCL = 18/19, green LED = 25, red LED = 26,
// passive piezo buzzer = 27. Each external LED needs its own resistor.
const int SDA_PIN = 18;
const int SCL_PIN = 19;
const int GREEN_LED = 25;
const int RED_LED = 26;
const int BUZZER = 27;

const unsigned long SCAN_TIME_MS = 10000;  // Maximum time from SCAN to 100 samples.
const unsigned long FINGER_WAIT_MS = 3000; // Wait up to 3 seconds.
const unsigned long FINGER_SETTLE_MS = 1000; // Let contact settle before collection.
const unsigned long FINGER_REMOVED_MS = 3000; // Require 3 seconds of lost contact.
const unsigned long SAMPLE_WAIT_MS = 2000; // Sensor must send data within 2 seconds.
// Calibrate using measured no-finger and finger-present IR ranges on this unit.
// No-finger IR near 850 (and sometimes higher) does not make 900 a safe cutoff.
const uint32_t FINGER_IR_MIN = 50000;
const int FINGER_CONFIRMATION_SAMPLES = 3;
// Raw output at 9600 baud slows sampling; leave off for timed scans.
const bool DEBUG_RAW_DATA = false; // Enable only for sensor diagnostics.
const int SAMPLE_COUNT = 100;              // Algorithm uses the latest 100 samples.

MAX30105 sensor;
uint32_t redSamples[SAMPLE_COUNT];
uint32_t irSamples[SAMPLE_COUNT];
bool sensorReady = false;
bool greenOn = true;
unsigned long lastBlink = 0;
String lastRequestId;
char pendingBleRequestId[9] = {0};
portMUX_TYPE bleQueueMux = portMUX_INITIALIZER_UNLOCKED;
bool scanActive = false;
BLECharacteristic *eventCharacteristic = nullptr;
bool bleConnected = false;

const char *BLE_SERVICE_ID = "11c0a001-9ef2-4b77-9f6c-111111111111";
const char *BLE_COMMAND_ID = "11c0a002-9ef2-4b77-9f6c-111111111111";
const char *BLE_EVENT_ID = "11c0a003-9ef2-4b77-9f6c-111111111111";

void bleEvent(const String &frame) {
  if (!bleConnected || eventCharacteristic == nullptr || frame.length() > 20) return;
  eventCharacteristic->setValue(frame.c_str());
  eventCharacteristic->notify();
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
  void onConnect(BLEServer *) override { bleConnected = true; }
  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    server->getAdvertising()->start();
  }
};

class CarePulseCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String command = String(characteristic->getValue().c_str());
    if (!command.startsWith("S|")) return;
    String id = command.substring(2);
    if (!validBleId(id)) return;
    // The sensor routine runs in loop(), never inside a BLE callback.
    portENTER_CRITICAL(&bleQueueMux);
    if (!scanActive && pendingBleRequestId[0] == 0) {
      memcpy(pendingBleRequestId, id.c_str(), 9);
    }
    portEXIT_CRITICAL(&bleQueueMux);
  }
};

void setupBle() {
  BLEDevice::init("CarePulse");
  BLEServer *server = BLEDevice::createServer();
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

void invalidScan(const char *reason, const String &requestId) {
  Serial.printf("state=invalid_scan reason=%s requestId=%s\n",
                reason, requestId.c_str());
  String code = "AR";
  if (strcmp(reason, "no_finger") == 0) code = "NF";
  else if (strcmp(reason, "finger_removed") == 0) code = "FR";
  else if (strcmp(reason, "too_few_samples") == 0) code = "FS";
  bleEvent("I|" + requestId + "|" + code);
  beep(1, 500);
  showReady();
}

void sensorError(const char *reason, const String &requestId = "") {
  if (requestId.length() > 0) {
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

// Read one pair of red and infrared values from the MAX30102.
// Return false if no new reading arrives within 2 seconds.
bool readSample(uint32_t &red, uint32_t &ir, unsigned long timeoutMs = SAMPLE_WAIT_MS) {
  unsigned long started = millis();
  while (millis() - started < timeoutMs) {
    // A second SCAN cannot start while this one is running.
    if (Serial.available()) {
      Serial.readStringUntil('\n');
      Serial.println("error=busy");
    }

    sensor.check();
    if (sensor.available()) {
      red = sensor.getFIFORed();
      ir = sensor.getFIFOIR();
      sensor.nextSample();
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

void startScan(const String &requestId) {
  unsigned long requestStarted = millis();
  uint32_t red = 0;
  uint32_t ir = 0;
  int fingerReadings = 0;
  greenOn = true;
  lastBlink = millis();
  digitalWrite(GREEN_LED, HIGH);
  sensor.clearFIFO();
  Serial.printf("state=waiting_for_finger requestId=%s\n", requestId.c_str());
  if (requestId.length() == 8) bleEvent("W|" + requestId);

  // Step A: three readings above the IR threshold mean a finger is present.
  unsigned long waitStarted = requestStarted;
  while (millis() - waitStarted < FINGER_WAIT_MS) {
    unsigned long remaining = FINGER_WAIT_MS - (millis() - waitStarted);
    unsigned long timeout = remaining < SAMPLE_WAIT_MS ? remaining : SAMPLE_WAIT_MS;
    if (!readSample(red, ir, timeout)) {
      if (millis() - waitStarted >= FINGER_WAIT_MS) break;
      sensorError("sensor_timeout", requestId);
      return;
    }
    unsigned long sampleTime = millis();
    if (sampleTime - waitStarted >= FINGER_WAIT_MS) break;
    fingerReadings = (ir >= FINGER_IR_MIN) ? fingerReadings + 1 : 0;
    if (DEBUG_RAW_DATA) {
      Serial.printf("WAIT time_ms=%lu red=%lu ir=%lu finger=%s\n",
                    sampleTime, static_cast<unsigned long>(red),
                    static_cast<unsigned long>(ir),
                    fingerReadings >= FINGER_CONFIRMATION_SAMPLES ? "YES" : "NO");
    }
    if (fingerReadings >= FINGER_CONFIRMATION_SAMPLES) break;
  }
  if (fingerReadings < FINGER_CONFIRMATION_SAMPLES) {
    invalidScan("no_finger", requestId);
    return;
  }

  // Step B: settle contact, then collect 100 consecutive valid pairs.
  // The 10-second deadline includes finger acquisition and settling.
  sensor.clearFIFO();
  Serial.printf("state=scanning requestId=%s\n", requestId.c_str());
  if (requestId.length() == 8) bleEvent("S|" + requestId);
  int saved = 0;
  unsigned long totalSamples = 0;
  unsigned long validSamples = 0;
  unsigned long scanStarted = millis();
  unsigned long settleStarted = scanStarted;
  unsigned long fingerMissingSince = 0;
  while (saved < SAMPLE_COUNT && millis() - requestStarted < SCAN_TIME_MS) {
    unsigned long remaining = SCAN_TIME_MS - (millis() - requestStarted);
    unsigned long timeout = remaining < SAMPLE_WAIT_MS ? remaining : SAMPLE_WAIT_MS;
    if (!readSample(red, ir, timeout)) {
      if (millis() - requestStarted >= SCAN_TIME_MS) break;
      printScanSummary(scanStarted, totalSamples, validSamples, saved);
      sensorError("sensor_timeout", requestId);
      return;
    }
    unsigned long sampleTime = millis();
    if (sampleTime - requestStarted >= SCAN_TIME_MS) break;
    totalSamples++;
    bool fingerPresent = ir >= FINGER_IR_MIN;
    if (DEBUG_RAW_DATA) {
      Serial.printf("DATA time_ms=%lu elapsed_ms=%lu sample=%lu red=%lu "
                    "ir=%lu finger=%s\n",
                    sampleTime, sampleTime - scanStarted, totalSamples,
                    static_cast<unsigned long>(red),
                    static_cast<unsigned long>(ir), fingerPresent ? "YES" : "NO");
    }
    if (!fingerPresent) {
      if (fingerMissingSince == 0) {
        fingerMissingSince = sampleTime;
        if (saved > 0) {
          Serial.printf("state=sample_buffer_reset discarded_samples=%d time_ms=%lu\n",
                        saved, sampleTime);
        }
        saved = 0; // Require a fresh, continuous set after contact returns.
        settleStarted = 0;
        Serial.printf("state=finger_maybe_removed ir=%lu time_ms=%lu\n",
                      static_cast<unsigned long>(ir), sampleTime);
      }
      if (sampleTime - fingerMissingSince >= FINGER_REMOVED_MS) {
        Serial.printf("state=finger_removed ir=%lu time_ms=%lu\n",
                      static_cast<unsigned long>(ir), sampleTime);
        printScanSummary(scanStarted, totalSamples, validSamples, saved);
        invalidScan("finger_removed", requestId);
        return;
      }
    } else {
      if (fingerMissingSince != 0) {
        Serial.printf("state=finger_restored ir=%lu time_ms=%lu\n",
                      static_cast<unsigned long>(ir), sampleTime);
        settleStarted = sampleTime;
      }
      fingerMissingSince = 0;
    }

    if (!fingerPresent) continue;
    validSamples++;
    if (sampleTime - settleStarted < FINGER_SETTLE_MS) continue;
    redSamples[saved] = red;
    irSamples[saved] = ir;
    saved++;
  }

  unsigned long scanElapsedMs = millis() - requestStarted;
  if (saved == SAMPLE_COUNT) {
    Serial.printf("state=samples_complete collected_samples=%d elapsed_ms=%lu\n",
                  saved, scanElapsedMs);
  }
  float measuredSampleRate = printScanSummary(
      scanStarted, totalSamples, validSamples, saved);

  // A full 3-second loss was handled above; any shorter loss resets the buffer.
  if (saved < SAMPLE_COUNT) {
    invalidScan("too_few_samples", requestId);
    return;
  }

  // Step C: ask the SparkFun/Maxim library to calculate the result.
  Serial.printf("state=processing requestId=%s\n", requestId.c_str());
  if (requestId.length() == 8) bleEvent("P|" + requestId);
  int32_t bpm = 0;
  int32_t spo2 = 0;
  int8_t bpmValid = 0;
  int8_t spo2Valid = 0;
  maxim_heart_rate_and_oxygen_saturation(
      irSamples, SAMPLE_COUNT, redSamples,
      &spo2, &spo2Valid, &bpm, &bpmValid);

  // Step D: show a result only if the validity flags and basic bounds pass.
  if (!bpmValid || !spo2Valid || bpm <= 0 || bpm > 250 ||
      spo2 < 0 || spo2 > 100) {
    invalidScan("algorithm_rejected", requestId);
    return;
  }

  Serial.printf("state=complete requestId=%s bpm=%ld spo2=%ld "
                "durationSeconds=%lu sample_rate=%.2f\n",
                requestId.c_str(),
                static_cast<long>(bpm), static_cast<long>(spo2),
                (scanElapsedMs + 999) / 1000, measuredSampleRate);
  if (requestId.length() == 8) {
    bleEvent("C|" + requestId + "|" + String(bpm) + "|" + String(spo2));
  }
  beep(2, 100);
  showReady();
}

void setup() {
  Serial.begin(9600);
  Serial.setTimeout(100);
  pinMode(GREEN_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);
  digitalWrite(RED_LED, HIGH); // Red means the device is starting.

  if (!ledcAttach(BUZZER, 2000, 8)) {
    Serial.println("state=error reason=buzzer_setup_failed");
    return;
  }
  if (!Wire.begin(SDA_PIN, SCL_PIN)) {
    sensorError("i2c_setup_failed");
    return;
  }
  if (!sensor.begin(Wire, I2C_SPEED_STANDARD)) {
    sensorError("max30102_not_found");
    return;
  }

  // 100 conversions/s averaged by 4 = about 25 red/IR pairs each second.
  sensor.setup(60, 4, 2, 100, 411, 4096);
  sensor.clearFIFO();
  sensorReady = true;
  setupBle();
  showReady();
}

void loop() {
  if (!sensorReady) {
    delay(10);
    return;
  }

  char queuedId[9] = {0};
  portENTER_CRITICAL(&bleQueueMux);
  if (pendingBleRequestId[0] != 0) {
    memcpy(queuedId, pendingBleRequestId, 9);
    pendingBleRequestId[0] = 0;
    scanActive = true;
  }
  portEXIT_CRITICAL(&bleQueueMux);
  if (queuedId[0] != 0) {
    String id = String(queuedId);
    if (id != lastRequestId) {
      lastRequestId = id;
      startScan(id);
    }
    portENTER_CRITICAL(&bleQueueMux);
    scanActive = false;
    portEXIT_CRITICAL(&bleQueueMux);
    return;
  }
  if (!Serial.available()) {
    delay(10);
    return;
  }

  String command = Serial.readStringUntil('\n');
  command.trim();
  if (command == "SCAN") {
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
}
