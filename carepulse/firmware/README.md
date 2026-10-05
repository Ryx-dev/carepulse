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
appear after a full scan and show sampling, signal range, and two heart-rate
estimates. A scan now needs 125 consecutive samples so two overlapping
four-second windows can agree before a result is saved. Timing outside 22–28
samples per second, a flat or saturated IR signal, or inconsistent estimates
returns an invalid scan. These checks can reject some good scans; they cannot
prove that an accepted result is accurate. Compare several still-finger scans
with a reference pulse measurement before relying on a result. Do not change
the BPM limit merely to hide a high reading.

Enable `DEBUG_RAW_DATA` only for deeper diagnostics. Printing every raw sample
at 9600 baud can consume the 10-second allowance. Leave it `false` for normal
scans.
This is a prototype
estimate for personal logging; it is not a medical diagnostic device.

Finger confirmation must happen within the first 3 seconds. Contact then gets
1 second to settle. The sketch collects 125 consecutive valid RED/IR pairs and
finishes as soon as it has them; 10 seconds is the total deadline, including
finger acquisition and settling. Contact below the threshold for 3 continuous
seconds ends the scan with `finger_removed`. A shorter loss resets the sample
buffer and settling period when contact returns. If the deadline arrives before
125 pairs are collected, the scan ends with `too_few_samples`. `SCAN_SUMMARY`
reports collection duration, total received samples, valid contact samples,
`collected_samples` in the current uninterrupted batch, and received samples
per second. Valid contact samples during settling, or before a contact loss,
do not count toward the required 125 collected samples. The unchanged SparkFun
algorithm runs on two overlapping windows of **100 collected red/IR pairs**.

The sketch also accepts `SCAN <requestId>` for the USB gateway. It includes the
same ID in progress and terminal Serial lines, and refuses the same ID twice
in one boot. The gateway described in `../PHASE5_ACCESS.md` holds a narrow
device token on its host computer. No token or Firebase credential is embedded
in the sketch. App control still needs deployment, physical device testing,
and live Flutter data wiring.

## BLE connection and scan transport

The sketch advertises a `CarePulse` BLE service while no phone is connected.
Select it in the app to connect without entering a code. A short `P` / `T`
exchange confirms that notifications are ready before scans are enabled. The
ESP32 accepts scan commands from the connected phone, stops advertising during
that connection, and advertises again after it disconnects. The app has a
**Disconnect** action to release the device. A dropped BLE connection also
releases it.

This is temporary access for the connected phone, not permanent ownership or
authenticated Bluetooth pairing. Any nearby phone using the CarePulse protocol
can connect when the device is free. The BLE link and measurement notifications
are not encrypted by this application protocol. Use the device only where that
tradeoff is acceptable.

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
without a code, Disconnect, and reconnection all worked.
On the previous firmware flash to the connected board, USB Serial reported
`max30102_not_found`. BLE still starts and can report a sensor error, but the
MAX30102 power, ground, SDA (GPIO 18), and SCL (GPIO 19) wiring must be checked
before a new measurement can succeed.

## References

- [SparkFun MAX3010x Arduino library and SpO2 example](https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library)
- [Espressif Arduino-ESP32 I2C pins and API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/i2c.html)
- [Espressif Arduino-ESP32 buzzer tone API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html)
