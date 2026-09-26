# CarePulse — VS Code / Codex Development Handoff

## 1. Project Identity

**Project Name:** CarePulse

**Current Project Description:**

CarePulse is an ESP32-based heart rate and blood oxygen saturation (SpO₂) monitoring and logging system using a MAX30102 sensor. The user initiates a fixed-duration scan from a Flutter mobile application. The Flutter app communicates with the ESP32 through Firebase Realtime Database. The ESP32 performs the sensor measurement, validates the result, and sends the BPM and SpO₂ data back through Firebase for display and history logging in the Flutter app.

CarePulse is intended for **personal physiological measurement and organized data logging only**. It must **not** present itself as a medical diagnostic system.

---

# 2. Current Technology Stack

Use the following stack unless explicitly instructed otherwise:

- **Frontend / Mobile App:** Flutter
- **Language:** Dart
- **IDE:** Visual Studio Code
- **AI Coding Assistant:** Codex inside VS Code
- **Backend:** Firebase
- **Authentication:** Firebase Authentication using Email + Password
- **Database:** Firebase Realtime Database
- **IoT Device:** ESP32
- **Sensor:** MAX30102
- **ESP32 Development:** Arduino framework / Arduino IDE or PlatformIO
- **Communication:** Wi-Fi + Firebase Realtime Database

---

# 3. Final High-Level Architecture

```text
Flutter Mobile App
        │
        │ Start Scan command
        │ Activity / context
        ▼
Firebase Realtime Database
        │
        ▼
ESP32
        │
        ▼
MAX30102
        │
        │ BPM + SpO₂
        ▼
ESP32
        │
        │ Upload measurement
        ▼
Firebase Realtime Database
        │
        ▼
Flutter Mobile App
        │
        ├── Latest Measurement
        ├── Measurement History
        ├── Measurement Details
        └── Device Status
```

---

# 4. IMPORTANT — Latest Project Decisions

These instructions override any older CarePulse document or code that conflicts with them.

## 4.1 Scan initiation

**DO NOT use a physical scan button in the new design.**

The scan is now started from the Flutter application.

Correct flow:

```text
User opens Flutter app
        ↓
Selects activity/context
        ↓
Places finger on MAX30102
        ↓
Presses START SCAN in Flutter
        ↓
Flutter sends scan command to Firebase
        ↓
ESP32 receives scan command
        ↓
ESP32 checks sensor/finger
        ↓
ESP32 performs fixed-duration scan
        ↓
ESP32 calculates/obtains BPM and SpO₂
        ↓
ESP32 validates measurement
        ↓
ESP32 uploads result to Firebase
        ↓
Flutter displays the result
```

## 4.2 Fixed-duration scanning

CarePulse is **not a continuous heart-rate tracker**.

Each user-initiated scan creates one saved measurement.

Initial target scan duration:

```text
15 seconds
```

Keep scan duration configurable so it can be changed later.

## 4.3 Sensor

Use:

```text
MAX30102
```

The sensor is used for:

- Heart rate / BPM
- Blood oxygen saturation / SpO₂

Do **not** claim that MAX30102 directly measures blood pressure.

## 4.4 LEDs

LEDs represent **device status only**.

They must not indicate whether the user's health is "good", "bad", "normal", or "dangerous".

Recommended behavior:

```text
Red blinking   = Initializing / connecting
Green solid    = Ready
Green blinking = Scanning
Red solid      = Device or sensor error
```

## 4.5 Buzzer

Recommended feedback:

```text
Two short beeps   = valid measurement completed
One long beep     = invalid measurement
Three short beeps = sensor/device error
```

A valid local measurement should not be marked invalid simply because Firebase upload temporarily fails.

---

# 5. Development Strategy

We are restarting Flutter development.

Do NOT attempt to build everything at once.

Follow this development order.

## Phase 1 — Flutter UI only

Build the complete app interface using mock data.

Do not connect Firebase yet.

Create:

- Login screen
- Register screen
- Dashboard/Home screen
- Scan screen / Start Scan interface
- Measurement History screen
- Measurement Details screen
- Device Status screen

Use mock BPM, SpO₂, device-state, and history values.

## Phase 2 — Navigation and local models

Add:

- Proper routes/navigation
- Measurement model
- Device model
- Mock repositories/services
- Reusable UI widgets

## Phase 3 — Firebase setup

After the UI is stable:

- Add Firebase Core
- Configure FlutterFire
- Add Firebase Authentication
- Add Firebase Realtime Database
- Replace mock repositories incrementally

## Phase 4 — Authentication

Implement:

- Register with email/password
- Login with email/password
- Logout
- Authentication state handling

## Phase 5 — Firebase data

Implement:

- Live device state
- Scan commands
- Measurement records
- Measurement history
- Activity/context
- Optional notes

## Phase 6 — ESP32

After Flutter + Firebase are working:

- Initialize MAX30102
- Connect ESP32 to Wi-Fi
- Connect ESP32 to Firebase
- Listen for scan commands
- Detect finger
- Perform scan
- Validate measurement
- Upload result
- Update device status
- Control LEDs
- Control buzzer

---

# 6. Flutter Project Structure

Use a clean feature-oriented structure.

Recommended starting structure:

```text
lib/
│
├── main.dart
├── firebase_options.dart
│
├── core/
│   ├── constants/
│   │   ├── app_constants.dart
│   │   └── app_strings.dart
│   ├── theme/
│   │   └── app_theme.dart
│   └── utils/
│
├── models/
│   ├── measurement.dart
│   └── device.dart
│
├── services/
│   ├── auth_service.dart
│   ├── database_service.dart
│   └── mock_data_service.dart
│
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   │
│   ├── dashboard/
│   │   └── dashboard_screen.dart
│   │
│   ├── scan/
│   │   └── scan_screen.dart
│   │
│   ├── history/
│   │   ├── history_screen.dart
│   │   └── measurement_details_screen.dart
│   │
│   └── device/
│       └── device_screen.dart
│
└── widgets/
    ├── latest_measurement_card.dart
    ├── measurement_card.dart
    ├── device_status_indicator.dart
    ├── metric_card.dart
    └── primary_button.dart
```

Do not put the entire application inside `main.dart`.

---

# 7. Flutter UI Requirements

The UI should be:

- Modern
- Clean
- Mobile-first
- Simple to understand
- Appropriate for an academic IoT project
- Consistent across screens
- Responsive to normal Android phone sizes

Avoid an overly complex hospital-style interface.

This is a personal monitoring/logging application.

---

# 8. Main Navigation

Recommended bottom navigation:

```text
Home        History        Device
```

The scan action should be clearly accessible from Home.

Possible approach:

```text
Home
│
├── Device status
├── Latest measurement
├── Measurement context
├── START SCAN
└── Recent measurements
```

Do not add unnecessary pages unless required.

---

# 9. Login Screen

Create an email/password login.

Required:

- CarePulse branding
- Email input
- Password input
- Show/hide password
- Login button
- Link to register
- Basic validation
- Loading state
- Error-message area

During Phase 1, authentication can be simulated locally.

Firebase Authentication is connected later.

---

# 10. Registration Screen

Required:

- Name
- Email
- Password
- Confirm password
- Register button
- Link back to Login
- Input validation

When Firebase is eventually connected, the Firebase user UID becomes the main account identifier.

---

# 11. Dashboard / Home Screen

The dashboard should show:

## Device status

Examples:

```text
Online
Ready
Scanning
Processing
Uploading
Offline
Sensor Error
```

## Latest measurement

Display:

- BPM
- SpO₂
- Activity/context
- Date
- Time

Example mock data:

```text
78 BPM
98% SpO₂
Resting
September 26, 2026
9:35 AM
```

## Main scan area

Show:

- Selected measurement context
- Optional note
- Finger-placement instruction
- START SCAN button

Example:

```text
Measurement Context
[ Resting ▼ ]

Optional Note
[ Morning measurement ]

Place your finger on the MAX30102 sensor
and keep it still during the scan.

[ START SCAN ]
```

---

# 12. Measurement Context

Use these initial options:

```text
Resting
Before Exercise
After Exercise
Recovery
Other
```

If `Other` is selected, allow the user to enter a short note or custom context.

The user should select the context **before** starting the scan.

---

# 13. App-Controlled Scan Behavior

When the user taps `START SCAN`:

1. Verify device is online.
2. Verify device state is `ready`.
3. Disable the Start Scan button.
4. Create a unique `requestId`.
5. Send the scan command to Firebase.
6. Wait for ESP32 acknowledgment/state update.
7. Display the current scan state.
8. Display progress for the fixed scan duration.
9. Wait for processing/result.
10. Display successful result or error.
11. Re-enable scanning when the ESP32 returns to `ready`.

Do not start multiple scans at the same time.

---

# 14. Scan UI States

Design the UI for these states even during the mock-data phase:

```text
READY
REQUESTING_SCAN
WAITING_FOR_FINGER
SCANNING
PROCESSING
UPLOADING
COMPLETE
INVALID_SCAN
ERROR
OFFLINE
```

Example user-facing text:

### Ready

```text
Device ready
Place your finger on the sensor.
```

### Waiting for finger

```text
Waiting for finger...
Place your fingertip firmly on the MAX30102.
```

### Scanning

```text
Scanning...
Keep your finger still.
8 seconds remaining
```

### Processing

```text
Processing measurement...
```

### Complete

```text
Scan complete
78 BPM
98% SpO₂
```

### Invalid

```text
Measurement could not be completed.
Keep your finger on the sensor for the entire scan and try again.
```

### Offline

```text
CarePulse device is offline.
Connect the device to Wi-Fi before starting a scan.
```

---

# 15. Start Scan Button Rules

The button must be enabled only when:

```text
device.online == true
AND
device.state == ready
```

Disable it when:

```text
initializing
requesting scan
waiting for finger
scanning
processing
uploading
offline
sensor error
```

The ESP32 must also reject a second command while a scan is already active.

---

# 16. Request ID

Every scan request must use a unique request ID.

Example:

```text
scan_1727315200000
```

or UUID.

Purpose:

- prevent duplicate scans
- match command with result
- make asynchronous communication safer

Example command:

```json
{
  "action": "start_scan",
  "requestId": "scan_1727315200000",
  "activity": "Resting",
  "note": "Morning measurement"
}
```

The ESP32 should ignore a request ID that has already been processed.

---

# 17. Measurement History Screen

Display saved scans in reverse chronological order.

Each item should show:

- BPM
- SpO₂
- Activity/context
- Date
- Time

Example:

```text
Sep 26, 2026 · 9:35 AM
78 BPM
98% SpO₂
Resting
```

Allow tapping a measurement to open Measurement Details.

Filters can be added later.

Possible filters:

- Resting
- Before Exercise
- After Exercise
- Recovery
- Date

---

# 18. Measurement Details Screen

Show:

- Average BPM
- SpO₂
- Activity
- Note
- Date
- Time
- Scan duration
- Device ID

Example:

```text
Heart Rate
78 BPM

SpO₂
98%

Activity
Resting

Note
Morning measurement

Scan Duration
15 seconds

Device
carepulse_001
```

Do not provide medical diagnosis.

---

# 19. Device Screen

Display:

- Device name
- Device ID
- Online/offline
- Current state
- Sensor status
- Last seen
- Wi-Fi/Firebase connection status if available

Example:

```text
CarePulse Device
carepulse_001

Status: Online
State: Ready
Sensor: MAX30102 connected
Last Seen: 9:46 AM
```

---

# 20. Device State Model

The future ESP32 firmware should use a state machine.

Recommended states:

```cpp
enum DeviceState {
    INITIALIZING,
    READY,
    WAITING_FOR_FINGER,
    SCANNING,
    PROCESSING,
    UPLOADING,
    ERROR_STATE
};
```

Flutter should map Firebase state values to readable UI labels.

Suggested Firebase strings:

```text
initializing
ready
waiting_for_finger
scanning
processing
uploading
error
```

---

# 21. Measurement Data Model

Recommended Dart model fields:

```dart
class Measurement {
  final String id;
  final String requestId;
  final String deviceId;
  final double bpm;
  final double spo2;
  final String activity;
  final String note;
  final int scanDurationSeconds;
  final DateTime timestamp;
}
```

Adapt types only when technically necessary.

---

# 22. Device Data Model

Recommended fields:

```dart
class CarePulseDevice {
  final String id;
  final String name;
  final bool online;
  final String state;
  final String sensorStatus;
  final DateTime? lastSeen;
}
```

---

# 23. Planned Firebase Realtime Database Structure

Use this as the initial architecture.

```text
users/
  USER_UID/
    profile/
      name
      email

    devices/
      carepulse_001/
        name
        online
        state
        sensorStatus
        lastSeen

        command/
          action
          requestId
          activity
          note
          createdAt

    measurements/
      REQUEST_OR_MEASUREMENT_ID/
        requestId
        deviceId
        bpm
        spo2
        activity
        note
        scanDuration
        timestamp
```

A more normalized structure may be adopted later if needed, but do not redesign it prematurely.

---

# 24. Device Heartbeat / Online Status

The ESP32 should periodically update `lastSeen`.

Flutter should not blindly trust:

```text
online: true
```

Eventually, calculate online/offline using both:

- stored online flag
- freshness of `lastSeen`

Example idea:

```text
If lastSeen is older than the allowed timeout,
treat the device as offline.
```

The exact timeout can be finalized later.

---

# 25. Future ESP32 Wiring

Current intended pins:

```text
MAX30102 SDA   -> GPIO 21
MAX30102 SCL   -> GPIO 22
Green LED      -> GPIO 25
Red LED        -> GPIO 26
Buzzer         -> GPIO 27
```

The physical scan button has been removed from the new architecture.

GPIO 18 is therefore no longer reserved for a scan button.

MAX30102 power:

```text
VCC/VIN -> appropriate regulated supply
GND     -> GND
```

Prefer the clearly labeled 3.3V supply unless the exact MAX30102 breakout board explicitly supports another VIN level.

All components must share a common ground.

Use a resistor with each external LED.

---

# 26. ESP32 Responsibility

ESP32 is responsible for:

- Connecting to Wi-Fi
- Connecting to Firebase
- MAX30102 initialization
- Listening for scan commands
- Rejecting duplicate requests
- Detecting a finger
- Reading raw sensor data
- Running the fixed scan
- Calculating/obtaining BPM
- Calculating/obtaining SpO₂
- Validating the reading
- Controlling LEDs
- Controlling buzzer
- Uploading results
- Updating device status
- Updating heartbeat / last seen

Flutter must not calculate BPM or SpO₂ from raw sensor values.

---

# 27. Flutter Responsibility

Flutter is responsible for:

- Authentication
- Displaying device state
- Selecting activity/context
- Adding optional note
- Starting a scan
- Displaying scan progress/status
- Receiving/displaying results
- Showing latest measurement
- Showing history
- Showing measurement details
- User-friendly errors

---

# 28. Validation and Medical-Safety UI Rules

CarePulse must not claim to diagnose:

- hypertension
- heart disease
- hypoxemia
- respiratory disease
- any other medical condition

Do not show statements such as:

```text
You are healthy.
Your oxygen is dangerous.
You have hypertension.
Your heart condition is abnormal.
```

Instead, show measurements neutrally:

```text
Heart Rate: 78 BPM
SpO₂: 98%
```

A general disclaimer may be shown:

```text
CarePulse is intended for personal monitoring and logging only and is not a medical diagnostic device.
```

---

# 29. Features NOT to Build

Do not add the following unless explicitly requested:

- Blood pressure measurement
- Medical diagnosis
- Continuous exercise monitoring
- "Time in Target"
- Automatic emergency diagnosis
- Health-condition color judgments
- Physical scan button
- Complex analytics not supported by collected data

---

# 30. Coding Rules for Codex

When working on this repository:

1. Read the existing files before modifying them.
2. Preserve working code unless a change is necessary.
3. Do not rewrite unrelated files.
4. Keep widgets small and reusable.
5. Avoid putting business logic directly inside UI widgets.
6. Use clear Dart naming.
7. Use null safety correctly.
8. Keep the project compiling after each logical change.
9. Do not introduce a dependency unless it provides clear value.
10. When adding a dependency, update `pubspec.yaml`.
11. Explain required terminal commands.
12. Do not invent Firebase credentials.
13. Never hard-code passwords or private Firebase secrets.
14. Do not create fake sensor readings once real ESP32 integration begins.
15. During Phase 1, clearly identify mock data as mock data.
16. Avoid deprecated Flutter APIs.
17. Use current Flutter/Dart conventions available in the installed SDK.
18. Prefer maintainable code over overly clever code.
19. Maintain consistent spacing, typography, component radius, and design language.
20. Keep user-facing wording simple.

---

# 31. Codex Working Behavior

Before making a large change:

1. Inspect the current project structure.
2. Identify which files need changes.
3. Make the smallest coherent implementation.
4. Run or recommend:
   ```bash
   flutter analyze
   ```
5. Fix analyzer errors caused by the change.
6. If tests exist, run them.
7. Summarize:
   - files created
   - files changed
   - commands required
   - remaining work

Do not silently restructure the entire project.

---

# 32. First Development Task

## CURRENT TASK

Start with **Phase 1: Flutter UI using mock data only**.

Do not configure Firebase yet.

First inspect the existing Flutter repository.

If there is no Flutter project yet, create or instruct the developer to create one with:

```bash
flutter create carepulse
cd carepulse
code .
```

Then build the app in this order:

1. App theme
2. Login screen
3. Register screen
4. Main shell / bottom navigation
5. Dashboard screen
6. Scan UI
7. History screen
8. Measurement details
9. Device screen
10. Mock models and mock services

The app should be runnable with:

```bash
flutter pub get
flutter run
```

---

# 33. Phase 1 Mock Data

Use obvious mock data such as:

```text
Device:
carepulse_001
Online
Ready

Latest:
78 BPM
98% SpO₂
Resting
September 26, 2026
9:35 AM
```

Mock history:

```text
Sep 26, 2026 — Resting — 78 BPM — 98%
Sep 25, 2026 — After Exercise — 128 BPM — 97%
Sep 23, 2026 — After Exercise — 133 BPM — 97%
Sep 21, 2026 — Resting — 76 BPM — 98%
```

Mock scan behavior can simulate:

```text
ready
↓
waiting_for_finger
↓
scanning
↓
processing
↓
complete
```

This simulation is temporary and must be easy to remove when Firebase is added.

---

# 34. Suggested Scan Mock Simulation

During UI-only development, Start Scan may behave like this:

```text
Tap START SCAN
↓
waiting_for_finger
↓
1 second
↓
scanning
↓
simulate progress
↓
processing
↓
complete
```

Generate a fixed or clearly mocked result.

Do not make random results look like real sensor readings without labeling the behavior as mock/demo data.

---

# 35. UI Quality Checklist

Before considering Phase 1 finished:

- [ ] App launches without error
- [ ] Login screen works visually
- [ ] Register screen works visually
- [ ] Navigation works
- [ ] Dashboard is responsive
- [ ] Device status is visible
- [ ] Activity can be selected
- [ ] Optional note can be entered
- [ ] Start Scan has enabled/disabled states
- [ ] Mock scan progress works
- [ ] Latest result updates in mock flow
- [ ] History list renders
- [ ] Measurement details opens
- [ ] Device page renders
- [ ] Empty/error/loading states exist where needed
- [ ] `flutter analyze` has no project-caused errors
- [ ] No Firebase dependency is required yet

---

# 36. Later Firebase Packages

Do not add these during the first UI-only step unless specifically instructed.

Likely packages later:

```yaml
firebase_core:
firebase_auth:
firebase_database:
```

Use versions compatible with the installed Flutter SDK when integration begins.

Configure Firebase using FlutterFire rather than manually inventing configuration files.

Expected future commands:

```bash
firebase login
dart pub global activate flutterfire_cli
flutterfire configure
```

Only run these when the Firebase phase starts.

---

# 37. Future Firebase Command Example

A future scan command may look like:

```json
{
  "action": "start_scan",
  "requestId": "scan_1727315200000",
  "activity": "Resting",
  "note": "Morning measurement",
  "createdAt": 1727315200000
}
```

Example device status:

```json
{
  "online": true,
  "state": "ready",
  "sensorStatus": "connected",
  "lastSeen": 1727315200000
}
```

Example result:

```json
{
  "requestId": "scan_1727315200000",
  "deviceId": "carepulse_001",
  "bpm": 78,
  "spo2": 98,
  "activity": "Resting",
  "note": "Morning measurement",
  "scanDuration": 15,
  "timestamp": 1727315215000
}
```

These are schema examples, not credentials or production data.

---

# 38. Definition of MVP

The CarePulse MVP is complete when a user can:

1. Register/login.
2. See whether the CarePulse ESP32 is online and ready.
3. Select a measurement context.
4. Place a finger on the MAX30102.
5. Start a scan from Flutter.
6. See live scan/device state.
7. Receive BPM and SpO₂ after the scan.
8. View the latest measurement.
9. Review previous measurements.
10. Open detailed information for a measurement.
11. See device status.
12. Use the system without any claim of medical diagnosis.

---

# 39. Core Principle

Keep the project understandable for a student developer.

When choosing between:

```text
more complex architecture
```

and

```text
clean, working, explainable architecture
```

prefer the **clean, working, explainable architecture** unless the more complex approach is necessary.

---

# 40. Instruction to Codex

Use this document as the primary development handoff for CarePulse.

If existing code conflicts with this file, do not automatically delete the code. First inspect it and adapt it to the latest architecture.

The most important current instruction is:

> **Build the Flutter UI first with mock data. Do not connect Firebase or ESP32 yet. The scan must be initiated from the Flutter app, not from a physical hardware button.**

When Phase 1 is complete, stop and summarize the project status before beginning Firebase integration.
