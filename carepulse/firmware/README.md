# CarePulse ESP32 prototype

## Standalone BPM and SpO2 sketch

Open [`carepulse_bpm_spo2/carepulse_bpm_spo2.ino`](carepulse_bpm_spo2/carepulse_bpm_spo2.ino)
for a separate **ESP32 + MAX30102** sketch that measures BPM and SpO2 through
Serial Monitor. It only needs the sensor; BLE, external LEDs, and the buzzer
are omitted. The original firmware is unchanged.

Install the Espressif **esp32** board package and **SparkFun MAX3010x Pulse and
Proximity Sensor Library**, select **ESP32 Dev Module**, and upload the sketch.
Use the sensor wiring below: SDA **GPIO18**, SCL **GPIO19**, and common GND.
Use 3V3 power only for a breakout rated for that input.

Open Serial Monitor at **9600 baud** with **Newline** enabled. Keep your finger
steady on the sensor, send `SCAN`, and wait up to 10 seconds. Accepted results
print `state=complete bpm=... spo2=...`; rejected readings print a reason.
Send `SCAN` again for another measurement.

The sketch retains contact calibration (`CAL EMPTY`, then `CAL FINGER`, and
`CAL RESET`) and the original timing, signal-quality, and two-window checks.
It shares the saved contact threshold with the main sketch on the same ESP32;
calibration changes therefore apply to both. Follow the calibration instructions
below. Calibration detects contact and does not establish measurement accuracy.
This is a prototype estimate, not a medical diagnostic device.

This sketch tests an **ESP32 Dev Module (classic ESP32)** with a MAX30102 over
USB Serial. It gives each scan up to 15 seconds from the `SCAN` command, reports a BPM
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
three short beeps mean a device error.

## Calibrate in the final housing

Keep the sensor mounted and connect USB Serial Monitor at **9600 baud** with
newline enabled. Calibration measures the actual light level through the
housing; do it again if the sensor position or cover changes.

1. Leave the sensor completely uncovered. Send `CAL EMPTY`. Keep the
   `CAL_EMPTY min_ir=... max_ir=... mean_ir=...` line.
2. Place a finger over the sensor as it will be held during a scan, with
   steady, gentle contact. Send `CAL FINGER` and hold it still for three
   seconds. Keep the `CAL_FINGER` and `CAL_SAVED finger_ir_min=...` lines.
3. Repeat `CAL EMPTY` and `CAL FINGER` if calibration reports a weak finger
   signal. Check sensor alignment, cover opacity, and contact before changing
   code constants. `CAL RESET` restores the original 50000 IR threshold.

The threshold is saved on the ESP32. It only detects finger contact; it does
not calibrate BPM or SpO2 accuracy. `SIGNAL_QUALITY` and `ALGORITHM` lines
appear after a full scan and show sampling, signal range, and the calculated
readings. The main app sketch collects 100 consecutive pairs and calls the
library once, using a four-second window. It reports the library results
directly after validity and bounds checks, with no second window or averaging.
The main app sketch logs sampling rate and IR range for diagnostics, but does
not reject scans for collection rate, IR saturation, or low IR variation.
Contact checks, sample count, timeouts, algorithm validity, and result bounds
still apply. The library assumes 25 samples per second; passing the remaining
checks cannot prove that a result is accurate. Compare several still-finger scans
with a reference pulse measurement before relying on a result. Do not change
the BPM limit merely to hide a high reading.

Enable `DEBUG_RAW_DATA` only for deeper diagnostics. Printing every raw sample
at 9600 baud can consume the main sketch's 15-second allowance. Leave it `false` for normal
scans.
This is a prototype
estimate for personal logging; it is not a medical diagnostic device.

Finger confirmation must happen within the first 3 seconds. Contact then gets
1 second to settle. The main app sketch collects 100 consecutive valid RED/IR pairs and
finishes as soon as it has them; 15 seconds is the total deadline, including
finger acquisition and settling. Contact below the threshold for 3 continuous
seconds ends the scan with `finger_removed`. A shorter loss resets the sample
buffer and settling period when contact returns. If the deadline arrives before
100 pairs are collected, the scan ends with `too_few_samples`. `SCAN_SUMMARY`
reports collection duration, total received samples, valid contact samples,
`collected_samples` in the current uninterrupted batch, and received samples
per second. Valid contact samples during settling, or before a contact loss,
do not count toward the required 100 collected samples. The unchanged SparkFun
algorithm runs once on **100 collected red/IR pairs** in the main app sketch.

The sketch also accepts `SCAN <requestId>` for the USB gateway. It includes the
same ID in progress and terminal Serial lines, and refuses the same ID twice
in one boot. The gateway described in `../PHASE5_ACCESS.md` holds a narrow
device token on its host computer. No token or Firebase credential is embedded
in the sketch. App control still needs deployment, physical device testing,
and live Flutter data wiring.

## BLE connection and scan transport

The mobile BLE firmware is
[`carepulse_single_scan_debug/carepulse_single_scan_debug.ino`](carepulse_single_scan_debug/carepulse_single_scan_debug.ino).
Upload this updated sketch manually before using the updated app. Older BLE
firmware's plaintext handshake is rejected by the app.

Each board generates a random 128-bit pairing key once and saves it in ESP32
nonvolatile storage. To pair a phone:

1. Connect the board to a trusted computer over physical USB. Open Serial
   Monitor at **9600 baud**, with **Newline** enabled.
2. When no scan is running, send `PAIR`. The board prints its 32 hexadecimal
   character key on a single line. This also works when the sensor is missing.
3. Select the `CarePulse` device in the app and enter that key in the pairing
   prompt. Treat it as a password; do not include it in screenshots, support
   logs, source code, or uploaded readings. Only a trusted physical USB
   connection can retrieve the key; BLE cannot request it.

The board and app exchange fresh random nonces and derive separate transmit
and receive keys with HMAC-SHA256. All commands, readiness checks, progress,
and readings then use AES-128-GCM with a full authentication tag and strictly
increasing counters. The app verifies the board's encrypted response before
enabling scans. A phone without the pairing key cannot issue scan commands or
read measurement notifications. This application pairing does not create an
operating-system Bluetooth bond.

The board stops advertising during a connection and advertises again after
the connection and any old scan have ended. Invalid, tampered, replayed, or
out-of-order frames close the connection. An unfinished handshake times out
after 20 seconds; an authenticated connection with no active scan and no
activity times out after 120 seconds. Monitoring remains connected while its
scan is active. The app's **Disconnect** action also releases the device.

BLE is disabled if key storage or the firmware's deterministic cryptographic
self-test fails. Erasing ESP32 nonvolatile storage creates a different key on
the next successful initialization, so phones must pair again. Anyone with
physical USB access or a copy of the pairing key can authorize another client.

The firmware sends request-correlated progress and
terminal notifications through the event characteristic; the UUIDs and frame
format are in `../ARCHITECTURE_DECISION_BLE.md` and
`../lib/services/ble_protocol.dart`. Serial control remains available for
bench testing. The Flutter mobile dashboard now has a separate **Connect and
scan** flow for discovering the device and displaying BLE results. This
end-to-end scan flow has been verified on a phone with a debug APK. The app now
stores completed results on the phone and retries authenticated writes to
Firebase account history. The database rules are deployed to the development
project, and one phone upload and history read succeeded. The tap-to-connect
change was checked on a Samsung SM-A135F and the ESP32: discovery, connection
without a code, Disconnect, and reconnection all worked on the prior plaintext
firmware. The new authenticated protocol still needs a manual firmware upload
and an end-to-end test on the phone and board.
On the previous firmware flash to the connected board, USB Serial reported
`max30102_not_found`. BLE still starts and can report a sensor error, but the
MAX30102 power, ground, SDA (GPIO 18), and SCL (GPIO 19) wiring must be checked
before a new measurement can succeed.

## References

- [SparkFun MAX3010x Arduino library and SpO2 example](https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library)
- [Espressif Arduino-ESP32 I2C pins and API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/i2c.html)
- [Espressif Arduino-ESP32 buzzer tone API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html)
