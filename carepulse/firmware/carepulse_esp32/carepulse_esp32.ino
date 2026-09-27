// CarePulse ESP32 hardware prototype.
// Board: ESP32 Dev Module (classic ESP32), Arduino-ESP32 core 3.x.
// Library: SparkFun MAX3010x Pulse and Proximity Sensor Library.
// Send SCAN followed by Enter in Serial Monitor (115200 baud).
// This USB Serial command is a test stand-in for the future Firebase command.

#include <Arduino.h>
#include <Wire.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"

constexpr uint8_t SDA_PIN = 21;
constexpr uint8_t SCL_PIN = 22;
constexpr uint8_t GREEN_LED_PIN = 25;
constexpr uint8_t RED_LED_PIN = 26;
constexpr uint8_t BUZZER_PIN = 27;

constexpr uint32_t SCAN_DURATION_MS = 15000;
constexpr uint32_t FINGER_TIMEOUT_MS = 10000;
constexpr uint32_t SAMPLE_TIMEOUT_MS = 2000;
constexpr uint32_t FINGER_IR_MIN = 50000;  // Tune for the actual breakout/finger.
constexpr size_t WINDOW_SIZE = 100;       // 4 seconds at 25 FIFO samples/s.

MAX30105 sensor;  // This SparkFun class also supports the MAX30102.
uint32_t irWindow[WINDOW_SIZE];
uint32_t redWindow[WINDOW_SIZE];
uint32_t irOrdered[WINDOW_SIZE];
uint32_t redOrdered[WINDOW_SIZE];

enum class LightMode { initializing, ready, scanning, error };
LightMode lightMode = LightMode::initializing;
uint32_t lastBlinkAt = 0;
bool blinkOn = false;

void setLights(LightMode mode) {
  lightMode = mode;
  lastBlinkAt = millis();
  blinkOn = true;
  digitalWrite(RED_LED_PIN, mode == LightMode::error || mode == LightMode::initializing);
  digitalWrite(GREEN_LED_PIN, mode == LightMode::ready || mode == LightMode::scanning);
}

void updateLights() {
  if (lightMode != LightMode::initializing && lightMode != LightMode::scanning) return;
  if (millis() - lastBlinkAt < 350) return;
  lastBlinkAt = millis();
  blinkOn = !blinkOn;
  digitalWrite(RED_LED_PIN, lightMode == LightMode::initializing && blinkOn);
  digitalWrite(GREEN_LED_PIN, lightMode == LightMode::scanning && blinkOn);
}

void beep(uint16_t durationMs) {
  ledcWriteTone(BUZZER_PIN, 2000);
  delay(durationMs);
  ledcWriteTone(BUZZER_PIN, 0);
}

void signalValid() {
  beep(100);
  delay(100);
  beep(100);
}

void signalInvalid() { beep(500); }

void signalError() {
  for (int i = 0; i < 3; ++i) {
    beep(100);
    if (i < 2) delay(100);
  }
}

void rejectQueuedCommand() {
  if (!Serial.available()) return;
  // A second request cannot start while this scan is active.
  Serial.readStringUntil('\n');
  Serial.println("error=busy");
}

// Returns the next paired red/IR reading, or false if the sensor stops sending.
bool readSample(uint32_t &red, uint32_t &ir) {
  const uint32_t startedAt = millis();
  while (millis() - startedAt < SAMPLE_TIMEOUT_MS) {
    rejectQueuedCommand();
    sensor.check();
    if (sensor.available()) {
      red = sensor.getFIFORed();
      ir = sensor.getFIFOIR();
      sensor.nextSample();
      return true;
    }
    updateLights();
    delay(1);
  }
  return false;
}

void finishScan(const char *state, const char *reason, bool deviceError) {
  Serial.printf("state=%s reason=%s\n", state, reason);
  if (deviceError) {
    setLights(LightMode::error);
    signalError();
  } else {
    signalInvalid();
    setLights(LightMode::ready);
    Serial.println("state=ready");
  }
}

void runScan() {
  Serial.println("state=waiting_for_finger");
  setLights(LightMode::scanning);
  sensor.clearFIFO();

  uint32_t red = 0, ir = 0;
  uint8_t fingerSamples = 0;
  const uint32_t waitStartedAt = millis();
  while (millis() - waitStartedAt < FINGER_TIMEOUT_MS) {
    if (!readSample(red, ir)) {
      finishScan("error", "sensor_timeout", true);
      return;
    }
    fingerSamples = ir >= FINGER_IR_MIN ? fingerSamples + 1 : 0;
    if (fingerSamples >= 3) break;
  }
  if (fingerSamples < 3) {
    finishScan("invalid_scan", "no_finger", false);
    return;
  }

  Serial.println("state=scanning");
  sensor.clearFIFO();
  size_t sampleCount = 0;
  const uint32_t scanStartedAt = millis();
  while (millis() - scanStartedAt < SCAN_DURATION_MS) {
    if (!readSample(red, ir)) {
      finishScan("error", "sensor_timeout", true);
      return;
    }
    if (ir < FINGER_IR_MIN) {
      finishScan("invalid_scan", "finger_removed", false);
      return;
    }
    const size_t slot = sampleCount % WINDOW_SIZE;
    redWindow[slot] = red;
    irWindow[slot] = ir;
    ++sampleCount;
  }

  if (sampleCount < WINDOW_SIZE) {
    finishScan("invalid_scan", "too_few_samples", false);
    return;
  }

  Serial.println("state=processing");
  // The library's algorithm uses exactly 100 chronologically ordered samples.
  const size_t oldest = sampleCount % WINDOW_SIZE;
  for (size_t i = 0; i < WINDOW_SIZE; ++i) {
    const size_t slot = (oldest + i) % WINDOW_SIZE;
    redOrdered[i] = redWindow[slot];
    irOrdered[i] = irWindow[slot];
  }

  int32_t spo2 = 0, bpm = 0;
  int8_t spo2Valid = 0, bpmValid = 0;
  maxim_heart_rate_and_oxygen_saturation(
      irOrdered, WINDOW_SIZE, redOrdered,
      &spo2, &spo2Valid, &bpm, &bpmValid);

  if (!spo2Valid || !bpmValid || spo2 < 0 || spo2 > 100 ||
      bpm <= 0 || bpm > 250) {
    finishScan("invalid_scan", "algorithm_rejected", false);
    return;
  }

  Serial.printf("state=complete bpm=%ld spo2=%ld durationSeconds=%lu\n",
                static_cast<long>(bpm), static_cast<long>(spo2),
                static_cast<unsigned long>(SCAN_DURATION_MS / 1000));
  signalValid();
  setLights(LightMode::ready);
  Serial.println("state=ready");
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(100);
  pinMode(GREEN_LED_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);
  setLights(LightMode::initializing);

  if (!ledcAttach(BUZZER_PIN, 2000, 8)) {
    Serial.println("state=error reason=buzzer_setup_failed");
    setLights(LightMode::error);
    return;
  }
  if (!Wire.begin(SDA_PIN, SCL_PIN)) {
    Serial.println("state=error reason=i2c_setup_failed");
    setLights(LightMode::error);
    signalError();
    return;
  }
  if (!sensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("state=error reason=max30102_not_found");
    setLights(LightMode::error);
    signalError();
    return;
  }

  // 100 sensor conversions/s with 4-sample FIFO averaging = 25 records/s.
  // Red + IR are both needed by the SpO2 algorithm.
  sensor.setup(60, 4, 2, 100, 411, 4096);
  sensor.clearFIFO();
  setLights(LightMode::ready);
  Serial.println("state=ready command=SCAN");
}

void loop() {
  updateLights();
  if (lightMode != LightMode::ready || !Serial.available()) {
    delay(10);
    return;
  }

  String command = Serial.readStringUntil('\n');
  command.trim();
  command.toUpperCase();
  if (command == "SCAN") {
    runScan();
  } else if (command.length() > 0) {
    Serial.println("error=unknown_command use=SCAN");
  }
}
