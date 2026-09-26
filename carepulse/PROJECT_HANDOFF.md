# CarePulse project handoff

**Status checked:** September 27, 2026  
**Application root:** `carepulse/` (the directory containing `pubspec.yaml`)  
**Planning document:** `../CAREPULSE_CODEX.md`

## Read this first

CarePulse is currently a **Flutter UI demo with local mock data**. The intended product is an app controlled ESP32/MAX30102 heart rate and SpO2 measurement and logging system. The app does not yet authenticate users, connect to Firebase, communicate with an ESP32, or read a sensor. The values displayed in the current UI are fixed examples. Do not describe the current app as a working IoT or medical device.

The older `../CAREPULSE_CODEX.md` records product decisions, proposed Firebase schema, hardware pins, and the intended development order. It is a **plan**, not an implementation report. This file records what the repository actually contains at the date above. If the two differ about progress, use this file and inspect the code.

## Intended product and constraints

- User starts one fixed duration scan from the Flutter app, after choosing a measurement context and optionally entering a note.
- ESP32 with a MAX30102 sensor is intended to collect BPM and SpO2, then publish a validated result through Firebase Realtime Database. Firebase Authentication is planned for email/password accounts.
- The initial scan target is 15 seconds. The system is for personal measurement and logging, with no diagnosis, blood pressure claim, continuous monitoring, or physical scan button.
- Proposed contexts: Resting, Before Exercise, After Exercise, Recovery, Other.
- Proposed hardware behavior, database tree, state machine, pin assignments, and MVP criteria are in `../CAREPULSE_CODEX.md`. None of those hardware or backend details is verified by this repository.

## Current implementation at a glance

| Area | Current state | Evidence |
| --- | --- | --- |
| Flutter shell and theme | Implemented | `lib/main.dart`, `lib/core/theme.dart`, bundled Nunito font |
| Login and registration | Demo UI implemented | `lib/screens/auth.dart`; valid form submission navigates locally after a 500 ms delay |
| Account persistence/authentication | Not implemented | No Firebase packages or auth service; any valid demo credentials enter the app |
| Main navigation | Implemented | `lib/screens/home.dart`; Home, History, Device, Profile tabs |
| Dashboard | Implemented with sample readings | Device card, latest measurement, context/custom context/note fields, scan button, recent measurements |
| Scan | Simulated | `lib/services/mock_data_service.dart`; timer driven states and fixed 78 BPM / 98% SpO2 result |
| History and details | Implemented for in-memory sample data | `lib/screens/pages.dart`; newest item first and tappable detail page |
| Device status | Simulated | `lib/screens/pages.dart`; seeded online/ready/MAX30102 status, no live connection |
| Profile/sign out | Demo UI implemented | `lib/screens/profile.dart`, `lib/screens/home.dart`; local name/email and navigation to login |
| Firebase / ESP32 / sensor | Not implemented in repository | No Firebase dependencies/configuration or firmware files found |
| Automated tests | Nine widget tests pass | `test/widget_test.dart`; `flutter test` and `flutter analyze` passed on September 27, 2026 |

## How the app currently works

1. `main.dart` launches `CarePulseApp`, a Material 3 app that starts at `LoginScreen`.
2. Login validates email and a nonempty password. Registration validates name, email, password length, and confirmation. Both only simulate an account transition; no account is created or checked. Forgot password shows a demo placeholder message.
3. `HomeShell` creates one `MockDataService` for that signed in demo session. This service initially has one mock online device and four dated sample measurements. Its data lives only in memory and resets when the shell is recreated or the app restarts.
4. Home shows the latest item, device state, two recent rows, a context dropdown, an optional note with a 100 character limit, and **Start measurement**. Selecting `Other` reveals a separate optional custom context field with a 40 character limit; leaving it blank saves the activity as `Other`. A demo label appears in the UI.
5. Pressing Start generates a timestamp based request ID and moves the mock service through requesting scan, waiting for finger, scanning, processing, uploading, and complete. The scanning stage counts down from 15 seconds. The new measurement always uses 78 BPM and 98% SpO2, then appears first in the dashboard and history.
6. The scan button is disabled while the simulated scan is active. A scan continues if the scan page is closed because the service belongs to `HomeShell`.
7. History lists the in-memory measurements in current list order. Tapping one opens details with BPM, SpO2, context, note, date/time, scan duration, and device ID.
8. Device and Profile show demo information. Sign out navigates to login and discards the session's mock data.

The `ScanStage` enum also defines invalid, error, and offline states and the scan page has text for them, but the current timer flow does **not** produce those states. The mock device begins online and ready; there is no UI control to simulate a disconnected device or invalid scan.

## Code map

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App entry point and root `MaterialApp` |
| `lib/core/theme.dart` | Material theme, colors, input/button/navigation styles |
| `lib/core/formatters.dart` | Simple date and time labels |
| `lib/models/measurement.dart` | Immutable measurement fields: IDs, BPM, SpO2, activity, note, duration, timestamp |
| `lib/models/device.dart` | Immutable device fields: ID, name, online flag, state, sensor status, last seen |
| `lib/services/mock_data_service.dart` | Seed data, `ChangeNotifier`, scan timer, scan gating, in-memory results |
| `lib/screens/auth.dart` | Login/register UI, validation, local demo transitions |
| `lib/screens/home.dart` | Tab shell, dashboard, scan launch, details routing, sign out |
| `lib/screens/pages.dart` | Shared metric/row widgets; Scan, History, Details, Device screens |
| `lib/screens/profile.dart` | Demo profile and sign out UI |
| `test/widget_test.dart` | Widget tests for auth flow, validation, navigation, small/wide layouts, scan lock |
| `pubspec.yaml` | Flutter package configuration; Flutter, Cupertino Icons, test/lint packages, Nunito assets |

The repository contains standard Flutter generated platform scaffolding for Android, iOS, web, Windows, Linux, and macOS. This does not establish that release builds on each platform have been tested. Android still uses the template `com.example.carepulse` application ID and debug signing for the release build.

## Progress against the planned phases

- **Phase 1, Flutter UI with mock data:** Complete as a UI demo. Login, registration, dashboard, scan progress, history, details, device, and profile screens were opened on an Android emulator. The demo data is labeled in key screens. A widget test and an emulator run verified the complete simulated scan through its result, latest measurement, history, and details. Empty history/latest views are coded, though no normal UI path empties the seeded history.
- **Phase 2, navigation and local models:** Partly implemented. Model classes, mock service, reusable theme/formatting/widgets, and navigation exist. There is no repository abstraction or persistent local store. Most navigation is direct `MaterialPageRoute` or tab switching.
- **Phase 3, Firebase setup:** Not started in code. No `firebase_core`, `firebase_auth`, `firebase_database`, `firebase_options.dart`, or platform Firebase configuration was found.
- **Phase 4, real authentication:** Not started. Current login/register/sign out are demo navigation only.
- **Phase 5, live Firebase data:** Not started. No remote device state, scan command, measurement read/write, or database security rules are present.
- **Phase 6, ESP32 firmware:** No firmware, wiring verification, sensor algorithm, LED/buzzer logic, or hardware test artifacts are present in this workspace.

## Known gaps and implementation details to watch

- **Demo credentials are not secure accounts.** The password is only validated locally. The displayed email/name are transient. Password reset is a placeholder.
- **Mock readings are fixed.** Every successful simulated scan produces the same BPM and SpO2. Do not treat seeded or new mock records as patient data.
- **No persistence or cross-device sync.** Measurements and device state reset with the demo session.
- **Context `Other` is separate from the note.** The optional custom context becomes the saved activity when entered; otherwise the activity remains `Other`. The optional note is stored independently. Confirm this contract before defining the backend schema.
- **Scan duration is a constant in the mock service.** It is 15 seconds; it is not yet externally configurable.
- **Request IDs are locally generated only.** There is no remote acknowledgment, duplicate request handling, timeout, retry, or result matching.
- **Status freshness is absent.** `lastSeen` is seeded to a fixed date and updated by the mock stage transitions. There is no heartbeat or online timeout.
- **Invalid/error/offline paths are display states only.** The happy path timer never triggers them. The device card may read as connected even though there is no real hardware, so retain clear demo labeling when refining the UI.
- **Release configuration is template level.** Review Android application ID/signing and platform setup before distribution.

## Verification and run commands

Run from the **inner** `carepulse/` directory:

```powershell
flutter pub get
flutter run
flutter test
flutter analyze
```

On September 27, 2026, `flutter test` completed with **9 passing widget tests**. These cover demo login/loading/sign out, field validation, forgot password copy, auth link behavior, a small phone login, tab navigation at phone width, wide dashboard/scan locking, a complete simulated 15-second scan through latest/history/details, and distinct custom context and note values on a 320 px phone layout. `flutter analyze` completed with **no issues found**. A debug build ran on a Pixel 9 Pro Android 17 emulator: Login, Register, Dashboard, Scan, History, Details, Device, and Profile rendered, and a 15-second mock scan updated Latest and History with separate custom context and note values visible in Details. No physical device, Firebase, ESP32, sensor, or release build was verified.

## Recommended next agent task

Next, work through Phase 2: tighten navigation and local models, and decide whether the invalid, error, offline, and empty states need demo controls or targeted widget tests. Keep the mock service available for deterministic UI development. Later Firebase work should proceed in small steps: project configuration, real authentication, device/measurement repositories, scan command and state protocol, and only then ESP32 firmware.

For Firebase integration, agree on ownership and access rules for the planned `users/{uid}/devices/...` and `users/{uid}/measurements/...` paths, a stable request/result ID contract, server timestamps, disconnect/heartbeat handling, timeout and error behavior, and scan deduplication. Do not invent credentials or publish secrets. Keep medical language neutral and distinguish demonstration data from real measurements.

## September 27, 2026 update

- `lib/screens/home.dart`: separated the optional custom context for `Other` from the optional note, constrained the context dropdown on small screens, and prevented the in-progress button label from overflowing.
- `test/widget_test.dart`: added a complete simulated scan test and a narrow-screen test that confirms custom context and note are saved independently.
- Verification: `flutter test` passed 9 tests; `flutter analyze` reported no issues; a Pixel 9 Pro Android 17 emulator ran the debug app and completed the mock scan through latest, history, and details.
- Physical device, Firebase, ESP32, sensor, and release behavior: not verified.

## Handoff checklist for future updates

When changing this document, record the date, the concrete files/features changed, which commands passed, and which real device/backend behaviors were verified. Move an item from planned to implemented only after confirming it in code or a running integration. Update `../CAREPULSE_CODEX.md` separately if a product decision changes.
