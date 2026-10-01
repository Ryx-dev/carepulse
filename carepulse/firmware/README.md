# CarePulse ESP32 prototype

This sketch tests an **ESP32 Dev Module (classic ESP32)** with a MAX30102 over
USB Serial. It gives each scan up to 10 seconds from the `SCAN` command, reports a BPM
and SpO2 estimate only when the library accepts both values, and drives status
LEDs and a passive piezo buzzer. It does not connect to Wi-Fi, Firebase, or the
Flutter app's demo history. A separate Node USB gateway can relay scan requests
and results through a server endpoint, but it has not been tried with physical
hardware. The mobile app has a separate live BLE result screen.

For a step-by-step explanation of the sketch, see
[`CarePulse_Arduino_Beginner_Guide.pdf`](../output/pdf/CarePulse_Arduino_Beginner_Guide.pdf).
The guide covers the original manual Serial scan; request ID handling was
added afterward for the gateway.

## Parts and wiring

| Part | Connect to ESP32 | Note |
| --- | --- | --- |
| MAX30102 `VCC`/`VIN` | `3V3` | Only for a breakout explicitly rated for 3.3 V input. Check the exact board pinout; do not apply 3.3 V to a bare MAX30102 IC. |
| MAX30102 `GND` | `GND` | Common ground. |
| MAX30102 `SDA` | `GPIO18` | I2C data. |
| MAX30102 `SCL` | `GPIO19` | I2C clock. |
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
3. Open Serial Monitor at **9600 baud** with newline enabled. On a good
   connection it prints `state=ready command=SCAN` and the green LED is on.
4. Place a finger steadily over the sensor. Type `SCAN` and press Enter.
   Waiting for a finger has a 3 second timeout. The green LED blinks while
   waiting/scanning. A valid result prints `state=complete bpm=... spo2=...`.
   Invalid contact or algorithm output prints `state=invalid_scan` with a
   reason. A missing/unresponsive sensor prints `state=error`.

The red LED stays on during initialization and for a device error. Two
short beeps mean a valid estimate, one long beep means an invalid scan, and
three short beeps mean a device error. `FINGER_IR_MIN` is a calibration value,
currently 50000, not a verified production threshold. A test saw no-finger
IR near 850 with occasional increases, so 900 must not be assumed safe.
Enable `DEBUG_RAW_DATA` to log `WAIT` readings, then record no-finger,
finger-present, and finger-removed RED/IR ranges on the actual hardware before
choosing a cutoff. Printing every raw sample at 9600 baud can consume the
10-second allowance. Keep `DEBUG_RAW_DATA = false` for scan timing tests,
normal scans, and USB gateway use.
This is a prototype
estimate for personal logging; it is not a medical diagnostic device.

Finger confirmation must happen within the first 3 seconds. Contact then gets
1 second to settle. The sketch collects 100 consecutive valid RED/IR pairs and
finishes as soon as it has them; 10 seconds is the total deadline, including
finger acquisition and settling. Contact below the threshold for 3 continuous
seconds ends the scan with `finger_removed`. A shorter loss resets the sample
buffer and settling period when contact returns. If the deadline arrives before
100 pairs are collected, the scan ends with `too_few_samples`. `SCAN_SUMMARY`
reports collection duration, total received samples, valid contact samples,
`collected_samples` in the current uninterrupted batch, and received samples
per second. Valid contact samples during settling, or before a contact loss,
do not count toward the required 100 collected samples. The unchanged SparkFun algorithm uses the
**100 collected red/IR pairs**.

The sketch also accepts `SCAN <requestId>` for the USB gateway. It includes the
same ID in progress and terminal Serial lines, and refuses the same ID twice
in one boot. The gateway described in `../PHASE5_ACCESS.md` holds a narrow
device token on its host computer. No token or Firebase credential is embedded
in the sketch. App control still needs deployment, physical device testing,
and live Flutter data wiring.

## BLE transport prototype

The sketch now advertises a `CarePulse` BLE service and accepts the compact
`S|<8 uppercase hex digits>` command. It sends request-correlated progress and
terminal notifications through the event characteristic; the UUIDs and frame
format are in `../ARCHITECTURE_DECISION_BLE.md` and
`../lib/services/ble_protocol.dart`. Serial control remains available for
bench testing. The Flutter mobile dashboard now has a separate **Connect and
scan** flow for discovering the device and displaying BLE results. This
end-to-end scan flow has been verified on a phone with a debug APK. The app now
stores completed results on the phone and retries authenticated writes to
Firebase account history. The database rules are deployed to the development
project, but phone/cloud synchronization still needs verification. The
current GATT service has no ownership check, so it is not ready for personal
measurements or deployment.

## References

- [SparkFun MAX3010x Arduino library and SpO2 example](https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library)
- [Espressif Arduino-ESP32 I2C pins and API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/i2c.html)
- [Espressif Arduino-ESP32 buzzer tone API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html)
