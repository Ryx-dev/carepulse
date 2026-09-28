// CarePulse beginner sketch for ESP32 + MAX30102.
// Open Serial Monitor at 115200 baud and send SCAN with a newline.
// The Flutter app is still a demo; this sketch is tested through USB Serial.

#include <Arduino.h>
#include <Wire.h>
#include "MAX30105.h"       // SparkFun's MAX30102-compatible sensor class
#include "spo2_algorithm.h" // Calculates BPM and SpO2 from red/IR samples

// Wiring: sensor SDA/SCL = 21/22, green LED = 25, red LED = 26,
// passive piezo buzzer = 27. Each external LED needs its own resistor.
const int SDA_PIN = 21;
const int SCL_PIN = 22;
const int GREEN_LED = 25;
const int RED_LED = 26;
const int BUZZER = 27;

const unsigned long SCAN_TIME_MS = 15000;  // Scan for 15 seconds.
const unsigned long FINGER_WAIT_MS = 10000; // Wait up to 10 seconds.
const unsigned long SAMPLE_WAIT_MS = 2000; // Sensor must send data within 2 seconds.
const uint32_t FINGER_IR_MIN = 50000;      // Adjust for your sensor/finger.
const int SAMPLE_COUNT = 100;              // Algorithm uses the latest 100 samples.

MAX30105 sensor;
uint32_t redSamples[SAMPLE_COUNT];
uint32_t irSamples[SAMPLE_COUNT];
bool sensorReady = false;
bool greenOn = true;
unsigned long lastBlink = 0;

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

void invalidScan(const char *reason) {
  Serial.printf("state=invalid_scan reason=%s\n", reason);
  beep(1, 500);
  showReady();
}

void sensorError(const char *reason) {
  Serial.printf("state=error reason=%s\n", reason);
  sensorReady = false;
  digitalWrite(GREEN_LED, LOW);
  digitalWrite(RED_LED, HIGH);
  beep(3, 100);
}

// Read one pair of red and infrared values from the MAX30102.
// Return false if no new reading arrives within 2 seconds.
bool readSample(uint32_t &red, uint32_t &ir) {
  unsigned long started = millis();
  while (millis() - started < SAMPLE_WAIT_MS) {
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

void startScan() {
  uint32_t red = 0;
  uint32_t ir = 0;
  int fingerReadings = 0;
  greenOn = true;
  lastBlink = millis();
  digitalWrite(GREEN_LED, HIGH);
  sensor.clearFIFO();
  Serial.println("state=waiting_for_finger");

  // Step A: three readings above the IR threshold mean a finger is present.
  unsigned long waitStarted = millis();
  while (millis() - waitStarted < FINGER_WAIT_MS) {
    if (!readSample(red, ir)) {
      sensorError("sensor_timeout");
      return;
    }
    fingerReadings = (ir >= FINGER_IR_MIN) ? fingerReadings + 1 : 0;
    if (fingerReadings >= 3) break;
  }
  if (fingerReadings < 3) {
    invalidScan("no_finger");
    return;
  }

  // Step B: check the finger for 15 seconds and save the latest 100 readings.
  sensor.clearFIFO();
  Serial.println("state=scanning");
  int saved = 0;
  unsigned long scanStarted = millis();
  while (millis() - scanStarted < SCAN_TIME_MS) {
    if (!readSample(red, ir)) {
      sensorError("sensor_timeout");
      return;
    }
    if (ir < FINGER_IR_MIN) {
      invalidScan("finger_removed");
      return;
    }

    if (saved < SAMPLE_COUNT) {
      redSamples[saved] = red;
      irSamples[saved] = ir;
      saved++;
    } else {
      // Drop the oldest reading, shift the rest, add the newest at the end.
      for (int i = 1; i < SAMPLE_COUNT; i++) {
        redSamples[i - 1] = redSamples[i];
        irSamples[i - 1] = irSamples[i];
      }
      redSamples[SAMPLE_COUNT - 1] = red;
      irSamples[SAMPLE_COUNT - 1] = ir;
    }
  }

  if (saved < SAMPLE_COUNT) {
    invalidScan("too_few_samples");
    return;
  }

  // Step C: ask the SparkFun/Maxim library to calculate the result.
  Serial.println("state=processing");
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
    invalidScan("algorithm_rejected");
    return;
  }

  Serial.printf("state=complete bpm=%ld spo2=%ld durationSeconds=%lu\n",
                static_cast<long>(bpm), static_cast<long>(spo2),
                SCAN_TIME_MS / 1000);
  beep(2, 100);
  showReady();
}

void setup() {
  Serial.begin(115200);
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
  showReady();
}

void loop() {
  if (!sensorReady || !Serial.available()) {
    delay(10);
    return;
  }

  String command = Serial.readStringUntil('\n');
  command.trim();
  command.toUpperCase();
  if (command == "SCAN") startScan();
  else if (command.length() > 0) Serial.println("error=unknown_command use=SCAN");
}
