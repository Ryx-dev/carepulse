// ESP32 + MAX30102 continuous diagnostics. Serial Monitor: 115200 baud.
// SDA = GPIO18, SCL = GPIO19. Uses the existing saved contact threshold.
// No SCAN command needed. First calculation follows settling + 100 pairs.
// Each subsequent calculation uses the latest 100 pairs, updated every second.
// No averaging of calculated BPM/SpO2 results. Estimates are for debugging.

#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"

constexpr int SDA_PIN = 18;
constexpr int SCL_PIN = 19;
constexpr int SAMPLES = 100;
constexpr int UPDATE_SAMPLES = 25;
constexpr bool PRINT_RAW = true; // RAW CSV: time_ms,red,ir,contact
constexpr uint32_t SETTLE_MS = 1000;
constexpr uint32_t SENSOR_TIMEOUT_MS = 2000;
constexpr uint32_t MAX_SAMPLE_GAP_MS = 120;

MAX30105 sensor;
uint32_t redData[SAMPLES];
uint32_t irData[SAMPLES];
uint32_t sampleTimes[SAMPLES];
uint32_t fingerThreshold = 50000;
uint32_t contactStarted = 0;
uint32_t lastSampleAt = 0;
bool ready = false;
bool contact = false;
bool timeoutReported = false;
int collected = 0;
int sinceCalculation = 0;

void resetWindow() {
  collected = 0;
  sinceCalculation = 0;
}

void reportWindow() {
  uint32_t minimum = UINT32_MAX;
  uint32_t maximum = 0;
  uint64_t sum = 0;
  for (int i = 0; i < SAMPLES; ++i) {
    minimum = min(minimum, irData[i]);
    maximum = max(maximum, irData[i]);
    sum += irData[i];
  }
  const uint32_t mean = sum / SAMPLES;
  const uint32_t duration = sampleTimes[SAMPLES - 1] - sampleTimes[0];
  const float rate = duration ? (SAMPLES - 1) * 1000.0f / duration : 0;
  int32_t bpm = 0;
  int32_t spo2 = 0;
  int8_t hrValid = 0;
  int8_t spo2Valid = 0;
  maxim_heart_rate_and_oxygen_saturation(
      irData, SAMPLES, redData, &spo2, &spo2Valid, &bpm, &hrValid);
  const bool bpmUsable = hrValid && bpm > 0 && bpm <= 250;
  const bool spo2Usable = spo2Valid && spo2 >= 0 && spo2 <= 100;
  // Print even invalid algorithm values to expose calculation failures.
  // Diagnostic flags below do not suppress or modify library outputs.
  Serial.printf("RESULT time_ms=%lu bpm=%ld spo2=%ld hr_valid=%d "
                "spo2_valid=%d bpm_usable=%d spo2_usable=%d rate=%.2f "
                "ir_min=%lu ir_max=%lu ir_mean=%lu ir_range=%lu "
                "timing_ok=%d saturated=%d low_variation=%d\n",
                static_cast<unsigned long>(millis()),
                static_cast<long>(bpm), static_cast<long>(spo2),
                hrValid, spo2Valid, bpmUsable, spo2Usable, rate,
                static_cast<unsigned long>(minimum),
                static_cast<unsigned long>(maximum),
                static_cast<unsigned long>(mean),
                static_cast<unsigned long>(maximum - minimum),
                rate >= 22 && rate <= 28, maximum >= 262000,
                maximum - minimum < mean / 500);
}

void handleSample(uint32_t red, uint32_t ir, uint32_t now) {
  if (PRINT_RAW) {
    Serial.printf("RAW,%lu,%lu,%lu,%d\n",
                  static_cast<unsigned long>(now),
                  static_cast<unsigned long>(red),
                  static_cast<unsigned long>(ir), ir >= fingerThreshold);
  }
  if (ir < fingerThreshold) {
    if (contact) Serial.println("STATE finger_removed window_reset");
    contact = false;
    resetWindow();
    return;
  }
  if (!contact) {
    contact = true;
    contactStarted = now;
    resetWindow();
    Serial.println("STATE contact_detected settling");
  }
  if (now - contactStarted < SETTLE_MS) return;
  if (collected == SAMPLES) {
    memmove(redData, redData + 1, (SAMPLES - 1) * sizeof(redData[0]));
    memmove(irData, irData + 1, (SAMPLES - 1) * sizeof(irData[0]));
    memmove(sampleTimes, sampleTimes + 1,
            (SAMPLES - 1) * sizeof(sampleTimes[0]));
    collected = SAMPLES - 1;
  }
  redData[collected] = red;
  irData[collected] = ir;
  sampleTimes[collected] = now;
  ++collected;
  ++sinceCalculation;
  if (collected == SAMPLES && sinceCalculation >= UPDATE_SAMPLES) {
    reportWindow();
    sinceCalculation = 0;
  }
}

void setup() {
  Serial.begin(115200);
  Preferences calibration;
  if (calibration.begin("carepulse", true)) {
    fingerThreshold = calibration.getUInt("finger_ir", 50000);
    calibration.end();
  }
  Serial.printf("DEBUG finger_ir_min=%lu raw=%d\n",
                static_cast<unsigned long>(fingerThreshold), PRINT_RAW);
  if (!Wire.begin(SDA_PIN, SCL_PIN) ||
      !sensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("ERROR sensor_not_found check_power_SDA18_SCL19 restart");
    return;
  }
  sensor.setup(60, 4, 2, 100, 411, 4096); // 25 pairs/second.
  while (sensor.available()) sensor.nextSample();
  sensor.clearFIFO();
  lastSampleAt = millis();
  ready = true;
  Serial.println("STATE ready place_finger first_result_in_about_5_seconds");
}

void loop() {
  if (!ready) { delay(10); return; }
  const uint16_t arrived = sensor.check();
  // SparkFun's software queue has only four slots. A large batch may have
  // overwritten unread pairs; discard it instead of calculating on gaps.
  if (arrived >= 4) {
    Serial.printf("WARNING sample_backlog=%u window_reset\n", arrived);
    while (sensor.available()) sensor.nextSample();
    sensor.clearFIFO();
    contact = false;
    resetWindow();
    lastSampleAt = millis();
    return;
  }
  while (sensor.available()) {
    const uint32_t now = millis();
    const uint32_t red = sensor.getFIFORed();
    const uint32_t ir = sensor.getFIFOIR();
    sensor.nextSample();
    if (timeoutReported || now - lastSampleAt > MAX_SAMPLE_GAP_MS) {
      Serial.println("WARNING sample_gap window_reset");
      contact = false;
      resetWindow();
    }
    lastSampleAt = now;
    timeoutReported = false;
    handleSample(red, ir, now);
  }
  if (!timeoutReported && millis() - lastSampleAt >= SENSOR_TIMEOUT_MS) {
    Serial.println("ERROR sensor_timeout no_new_data retrying");
    contact = false;
    resetWindow();
    timeoutReported = true;
  }
  delay(1);
}
