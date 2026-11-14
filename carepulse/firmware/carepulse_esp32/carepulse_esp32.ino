#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <string.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"

constexpr int SDA_PIN = 18;
constexpr int SCL_PIN = 19;
constexpr int SAMPLES = 100;
constexpr int UPDATE_SAMPLES = 25;
constexpr int FILTER_SIZE = 5;
constexpr uint32_t SETTLE_MS = 1000;
constexpr uint32_t SCAN_TIMEOUT_MS = 20000;
constexpr uint32_t SENSOR_TIMEOUT_MS = 2000;
constexpr uint32_t MAX_SAMPLE_GAP_MS = 150;
// Debug acceptance tolerances, not clinical accuracy limits.
constexpr int MAX_BPM_SPREAD = 10;
constexpr int MAX_SPO2_SPREAD = 3;

MAX30105 sensor;
uint32_t redData[SAMPLES], irData[SAMPLES];
int bpmHistory[FILTER_SIZE], spo2History[FILTER_SIZE];
uint32_t fingerThreshold = 50000;
uint32_t scanStarted, contactStarted, lastSampleAt;
int collected = 0, sinceCalculation = 0;
int filterCount = 0, filterIndex = 0;
bool sensorReady = false, scanActive = false, fingerDetected = false;
char command[32];
size_t commandLength = 0;
bool commandOverflow = false;

void resetMeasurement() {
  collected = sinceCalculation = filterCount = filterIndex = 0;
}

int median(const int *values) {
  int sorted[FILTER_SIZE];
  memcpy(sorted, values, sizeof(sorted));
  for (int i = 1; i < FILTER_SIZE; ++i) {
    int key = sorted[i], j = i - 1;
    while (j >= 0 && sorted[j] > key) {
      sorted[j + 1] = sorted[j];
      --j;
    }
    sorted[j + 1] = key;
  }
  return sorted[FILTER_SIZE / 2];
}

int spread(const int *values) {
  int low = values[0], high = values[0];
  for (int i = 1; i < FILTER_SIZE; ++i) {
    if (values[i] < low) low = values[i];
    if (values[i] > high) high = values[i];
  }
  return high - low;
}

void finishScan(const char *reason) {
  scanActive = false;
  fingerDetected = false;
  resetMeasurement();
  Serial.printf("state=%s\n", reason);
  Serial.println("state=ready command=SCAN");
}

void calculateVitals() {
  uint32_t low = UINT32_MAX, high = 0;
  uint64_t sum = 0;
  for (int i = 0; i < SAMPLES; ++i) {
    if (irData[i] < low) low = irData[i];
    if (irData[i] > high) high = irData[i];
    sum += irData[i];
  }
  float mean = static_cast<float>(sum) / SAMPLES;
  float variation = mean > 0 ? (high - low) / mean : 0;
  if (variation < 0.001f) {
    filterCount = filterIndex = 0;
    Serial.println("window=rejected reason=weak_pulse");
    return;
  }

  int32_t bpm = 0, spo2 = 0;
  int8_t hrValid = 0, spo2Valid = 0;
  maxim_heart_rate_and_oxygen_saturation(
      irData, SAMPLES, redData, &spo2, &spo2Valid, &bpm, &hrValid);
  Serial.printf("window bpm=%ld spo2=%ld hr_valid=%d spo2_valid=%d\n",
                static_cast<long>(bpm), static_cast<long>(spo2),
                hrValid, spo2Valid);
  if (!hrValid || !spo2Valid || bpm < 35 || bpm > 220 ||
      spo2 < 0 || spo2 > 100) {
    filterCount = filterIndex = 0;
    return;
  }

  bpmHistory[filterIndex] = bpm;
  spo2History[filterIndex] = spo2;
  filterIndex = (filterIndex + 1) % FILTER_SIZE;
  if (filterCount < FILTER_SIZE) ++filterCount;
  if (filterCount < FILTER_SIZE) return;

  int bpmSpread = spread(bpmHistory);
  int spo2Spread = spread(spo2History);
  Serial.printf("stability bpm_spread=%d spo2_spread=%d\n",
                bpmSpread, spo2Spread);
  if (bpmSpread > MAX_BPM_SPREAD || spo2Spread > MAX_SPO2_SPREAD) return;

  Serial.printf("result bpm=%d spo2=%d duration_ms=%lu\n",
                median(bpmHistory), median(spo2History),
                static_cast<unsigned long>(millis() - scanStarted));
  finishScan("complete");
}

void processSample(uint32_t red, uint32_t ir, uint32_t now) {
  if (ir < fingerThreshold) {
    if (fingerDetected) Serial.println("state=contact_lost buffers_reset=1");
    fingerDetected = false;
    resetMeasurement();
    return;
  }
  if (!fingerDetected) {
    fingerDetected = true;
    contactStarted = now;
    resetMeasurement();
    Serial.println("state=settling");
  }
  if (now - contactStarted < SETTLE_MS) return;
  if (collected == SAMPLES) {
    memmove(redData, redData + 1, (SAMPLES - 1) * sizeof(redData[0]));
    memmove(irData, irData + 1, (SAMPLES - 1) * sizeof(irData[0]));
    --collected;
  }
  redData[collected] = red;
  irData[collected++] = ir;
  ++sinceCalculation;
  if (collected == SAMPLES && sinceCalculation >= UPDATE_SAMPLES) {
    sinceCalculation = 0;
    calculateVitals();
  }
}

void handleCommand() {
  if (strcmp(command, "STOP") == 0) {
    if (scanActive) finishScan("cancelled");
    return;
  }
  if (strcmp(command, "SCAN") != 0) {
    Serial.println("error=unknown_command commands=SCAN,STOP");
    return;
  }
  if (!sensorReady) {
    Serial.println("error=sensor_not_ready");
    return;
  }
  if (scanActive) {
    Serial.println("error=busy");
    return;
  }
  while (sensor.available()) sensor.nextSample();
  sensor.clearFIFO();
  resetMeasurement();
  fingerDetected = false;
  scanStarted = lastSampleAt = millis();
  scanActive = true;
  Serial.println("state=waiting_for_finger");
}

void setup() {
  Serial.begin(9600);
  delay(1000);
  Preferences calibration;
  if (calibration.begin("carepulse", true)) {
    fingerThreshold = calibration.getUInt("finger_ir", 50000);
    calibration.end();
  }
  if (!Wire.begin(SDA_PIN, SCL_PIN) ||
      !sensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("error=sensor_initialization_failed");
    return;
  }
  sensor.setup(60, 4, 2, 100, 411, 4096);
  sensor.clearFIFO();
  sensorReady = true;
  Serial.printf("finger_ir_threshold=%lu\n",
                static_cast<unsigned long>(fingerThreshold));
  Serial.println("state=ready command=SCAN");
}

void loop() {
  while (Serial.available()) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r') continue;
    if (c == '\n') {
      command[commandLength] = '\0';
      if (commandOverflow) Serial.println("error=command_too_long");
      else if (commandLength) handleCommand();
      commandLength = 0;
      commandOverflow = false;
    } else if (commandLength < sizeof(command) - 1) {
      command[commandLength++] = c;
    } else {
      commandOverflow = true;
    }
  }
  if (!scanActive) {
    delay(1);
    return;
  }
  if (millis() - scanStarted >= SCAN_TIMEOUT_MS) {
    finishScan("invalid_scan reason=no_stable_result_before_timeout");
    return;
  }
  uint16_t arrived = sensor.check();
  if (arrived >= 4) {
    while (sensor.available()) sensor.nextSample();
    sensor.clearFIFO();
    fingerDetected = false;
    resetMeasurement();
    lastSampleAt = millis();
    Serial.println("state=backlog_reset");
    return;
  }
  while (scanActive && sensor.available()) {
    uint32_t now = millis();
    if (now - scanStarted >= SCAN_TIMEOUT_MS) {
      finishScan("invalid_scan reason=no_stable_result_before_timeout");
      return;
    }
    uint32_t red = sensor.getFIFORed(), ir = sensor.getFIFOIR();
    sensor.nextSample();
    if (now - lastSampleAt > MAX_SAMPLE_GAP_MS) {
      fingerDetected = false;
      resetMeasurement();
      Serial.println("state=sample_gap_reset");
    }
    lastSampleAt = now;
    processSample(red, ir, now);
  }
  if (scanActive && millis() - lastSampleAt > SENSOR_TIMEOUT_MS) {
    finishScan("error reason=sensor_timeout");
  }
  delay(1);
}
