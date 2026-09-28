# CarePulse ESP32 prototype

This sketch tests an **ESP32 Dev Module (classic ESP32)** with a MAX30102 over
USB Serial. It measures for 15 seconds after detecting a finger, reports a BPM
and SpO2 estimate only when the library accepts both values, and drives status
LEDs and a passive piezo buzzer. It does not connect to Wi-Fi, Firebase, or the
Flutter app yet. The app still displays mock measurements.

For a step-by-step explanation of the sketch, see
[`CarePulse_Arduino_Beginner_Guide.pdf`](../output/pdf/CarePulse_Arduino_Beginner_Guide.pdf).

## Parts and wiring

| Part | Connect to ESP32 | Note |
| --- | --- | --- |
| MAX30102 `VCC`/`VIN` | `3V3` | Only for a breakout explicitly rated for 3.3 V input. Check the exact board pinout; do not apply 3.3 V to a bare MAX30102 IC. |
| MAX30102 `GND` | `GND` | Common ground. |
| MAX30102 `SDA` | `GPIO21` | I2C data. |
| MAX30102 `SCL` | `GPIO22` | I2C clock. |
| Green LED anode (+) | `GPIO25` through 220–330 ohm resistor | Cathode (-) to GND. |
| Red LED anode (+) | `GPIO26` through 220–330 ohm resistor | Cathode (-) to GND. |
| Passive piezo (+) | `GPIO27` | Negative lead to GND. Use a driver transistor for a buzzer that exceeds the GPIO current rating. |

The sensor's `INT` pin is unused. The sensor breakout must support 3.3 V I2C
logic and have appropriate pullups or level shifting. Do not connect a 5 V
I2C pullup directly to the ESP32 pins. No physical scan button is used.

## Upload and test

1. In Arduino IDE, install the **esp32** board package by Espressif and the
   **SparkFun MAX3010x Pulse and Proximity Sensor Library**. This sketch uses
   Arduino-ESP32 core 3.x (`ledcAttach`/`ledcWriteTone`).
2. Open `carepulse_esp32/carepulse_esp32.ino`, choose **ESP32 Dev Module** and
   the correct port, then upload.
3. Open Serial Monitor at **115200 baud** with newline enabled. On a good
   connection it prints `state=ready command=SCAN` and the green LED is on.
4. Place a finger steadily over the sensor. Type `SCAN` and press Enter.
   Waiting for a finger has a 10 second timeout. The green LED blinks while
   waiting/scanning. A valid result prints `state=complete bpm=... spo2=...`.
   Invalid contact or algorithm output prints `state=invalid_scan` with a
   reason. A missing/unresponsive sensor prints `state=error`.

The red LED stays on during initialization and for a device error. Two
short beeps mean a valid estimate, one long beep means an invalid scan, and
three short beeps mean a device error. Adjust `FINGER_IR_MIN` for the actual
breakout and finger placement if detection is unreliable. This is a prototype
estimate for personal logging; it is not a medical diagnostic device.

The scan checks finger contact for the full 15 seconds. The SparkFun algorithm
calculates from the **latest 100 red/IR pairs** (about 4 seconds at the selected
sample settings).

The planned app flow will need Firebase authentication, a scan command/result
contract, database rules, and ESP32 networking before an app tap can trigger
this scan or display its result. No credentials or live readings are embedded
in this sketch.

## References

- [SparkFun MAX3010x Arduino library and SpO2 example](https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library)
- [Espressif Arduino-ESP32 I2C pins and API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/i2c.html)
- [Espressif Arduino-ESP32 buzzer tone API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html)
