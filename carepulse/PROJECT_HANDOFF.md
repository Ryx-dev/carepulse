# CarePulse project handoff

**Status checked:** September 28, 2026
**Application root:** `carepulse/` (the directory containing `pubspec.yaml`)  
**Planning document:** `../CAREPULSE_CODEX.md`

## Read this first

CarePulse is currently a **Flutter UI demo with local mock data**. The intended product is an app controlled ESP32/MAX30102 heart rate and SpO2 measurement and logging system. The Flutter app now initializes Firebase for Android and web, and a standalone ESP32 prototype sketch exists in `firmware/`. The app does not yet authenticate users, read or write live database data, communicate with the ESP32, or read a sensor. The values displayed in the UI are fixed examples. Do not describe the current app as a working IoT or medical device.

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
| Flutter shell, splash, and theme | Implemented | `lib/main.dart`, `lib/screens/splash.dart`, `lib/core/theme.dart`, bundled Nunito font and logo mark |
| Login and registration | Demo UI implemented | `lib/screens/auth.dart`; valid form submission navigates locally after a 500 ms delay |
| Account persistence/authentication | Not implemented | Firebase Auth package and Email/Password provider are configured, but any valid demo credentials still enter the app |
| Main navigation | Implemented | `lib/screens/home.dart`; Home, History, Device, Profile tabs |
| Dashboard | Implemented with sample readings | Device card, latest measurement, context/custom context/note fields, scan button, recent measurements |
| Scan | Simulated | `lib/services/mock_data_service.dart`; timer driven states and fixed 78 BPM / 98% SpO2 result |
| History and details | Implemented for in-memory sample data | `lib/screens/pages.dart`; newest item first and tappable detail page |
| Device status | Simulated | `lib/screens/pages.dart`; seeded online/ready/MAX30102 status, no live connection |
| Profile/sign out | Demo UI implemented | `lib/screens/profile.dart`, `lib/screens/home.dart`; local name/email and navigation to login |
| Firebase setup | Configured for Android and web | `lib/firebase_options.dart`, `firebase.json`, `database.rules.json`; Singapore Realtime Database denies all reads/writes |
| ESP32 / sensor | Standalone prototype; app integration absent | `firmware/carepulse_esp32/carepulse_esp32.ino`; no Wi-Fi/Firebase connection |
| Automated tests | Sixteen widget tests pass | `flutter test` and `flutter analyze` passed on September 28, 2026 |

## How the app currently works

1. `main.dart` initializes Firebase using the generated Android/web options, then launches `CarePulseApp`, a Material 3 app that shows a 900 ms branded Flutter splash and then replaces it with `LoginScreen`. Android and iOS also have matching native launch resources.
2. Login validates email and a nonempty password. Registration validates name, email, password length, and confirmation. Both only simulate an account transition; no account is created or checked. Forgot password shows a demo placeholder message.
3. `DemoSession` creates and owns one `MockDataService` for that signed in demo session, then passes it to `HomeShell`. The service initially has one mock online device and four dated sample measurements. Its data lives only in memory and resets when the session is recreated or the app restarts.
4. Home shows the latest item, device state, two recent rows, a context dropdown, an optional note with a 100 character limit, and **Start measurement**. Selecting `Other` reveals a separate optional custom context field with a 40 character limit; leaving it blank saves the activity as `Other`. A demo label appears in the UI.
5. Pressing Start generates a timestamp based request ID and moves the mock service through requesting scan, waiting for finger, scanning, processing, uploading, and complete. The scanning stage counts down from 15 seconds. The new measurement always uses 78 BPM and 98% SpO2, then appears first in the dashboard and history.
6. The scan button is disabled while the simulated scan is active. A scan continues if the scan page is closed because the service belongs to `DemoSession`.
7. History lists the in-memory measurements in current list order. Tapping one opens details with BPM, SpO2, context, note, date/time, scan duration, and device ID.
8. Device and Profile show demo information. Sign out navigates to login and discards the session's mock data.

The `ScanStage` enum also defines invalid, error, and offline states and the scan page has text for them, but the current timer flow does **not** produce those states. The mock device begins online and ready; there is no UI control to simulate a disconnected device or invalid scan.

## Code map

| Path | Responsibility |
| --- | --- |
| `lib/main.dart`, `lib/firebase_options.dart` | Firebase initialization and root `MaterialApp` |
| `lib/core/theme.dart` | Material theme, colors, input/button/navigation styles |
| `lib/screens/splash.dart` | Brief branded opening screen and transition to sign-in |
| `lib/core/formatters.dart` | Simple date and time labels |
| `lib/models/measurement.dart` | Immutable measurement fields: IDs, BPM, SpO2, activity, note, duration, timestamp |
| `lib/models/device.dart` | Immutable device fields: ID, name, online flag, state, sensor status, last seen |
| `lib/services/mock_data_service.dart` | Seed data, `ChangeNotifier`, scan timer, scan gating, in-memory results |
| `lib/screens/auth.dart` | Login/register UI, validation, local demo transitions |
| `lib/screens/demo_session.dart` | Owns and disposes the mock service for a demo session |
| `lib/screens/home.dart` | Tab shell receiving mock data, dashboard, scan launch, details routing, sign out |
| `lib/screens/pages.dart` | Shared metric/row widgets; Scan, History, Details, Device screens |
| `lib/screens/profile.dart` | Demo profile and sign out UI |
| `test/widget_test.dart` | Widget tests for auth flow, validation, navigation, layouts, and full mock scan |
| `test/phase2_states_test.dart` | Widget tests for empty, offline, invalid, and error display states |
| `firebase.json`, `database.rules.json`, `PHASE3_FIREBASE.md` | Firebase project setup, locked database rules, and proposed live-data contract |
| `pubspec.yaml` | Flutter and Firebase packages, test/lint packages, Nunito assets |

The repository contains standard Flutter generated platform scaffolding for Android, iOS, web, Windows, Linux, and macOS. This does not establish that release builds on each platform have been tested. Firebase is configured only for Android and web. Android now uses `com.joryx.carepulse`; the release build still uses debug signing.

## Progress against the planned phases

- **Phase 1, Flutter UI with mock data:** Complete as a UI demo. Login, registration, dashboard, scan progress, history, details, device, and profile screens were opened on an Android emulator. The demo data is labeled in key screens. A widget test and an emulator run verified the complete simulated scan through its result, latest measurement, history, and details. Empty history/latest views are coded, though no normal UI path empties the seeded history.
- **Phase 2, navigation and local models:** Complete for the planned local UI scope. Measurement and device models, a mock service, reusable theme/formatting/widgets, and working routes/tabs exist. `DemoSession` owns the service while `HomeShell` receives it, allowing isolated UI state tests. Routes remain direct `MaterialPageRoute` or tab switching. There is no repository interface or persistent local store; those are still decisions for live data integration.
- **Phase 3, Firebase setup:** Configured for Android and web in `carepulse-joryx-dev`. Firebase Core initializes at startup. Email/Password Authentication is enabled, and the default Realtime Database is in Singapore with deny-all rules. The UI still uses mock data.
- **Phase 4, real authentication:** Not started. Current login/register/sign out are demo navigation only.
- **Phase 5, live Firebase data:** Not started. No remote device state, scan command, or measurement read/write is implemented. The database rules currently deny all client access pending a secure ownership/device contract.
- **Phase 6, ESP32 firmware:** A standalone Serial-triggered ESP32/MAX30102 prototype sketch and wiring guide are in `firmware/`. No compile, wiring, sensor, Firebase, or physical board verification has been performed.

## Known gaps and implementation details to watch

- **Demo credentials are not secure accounts.** The password is only validated locally. The displayed email/name are transient. Password reset is a placeholder.
- **Mock readings are fixed.** Every successful simulated scan produces the same BPM and SpO2. Do not treat seeded or new mock records as patient data.
- **No persistence or cross-device sync.** Measurements and device state reset with the demo session.
- **Context `Other` is separate from the note.** The optional custom context becomes the saved activity when entered; otherwise the activity remains `Other`. The optional note is stored independently. Confirm this contract before defining the backend schema.
- **Scan duration is a constant in the mock service.** It is 15 seconds; it is not yet externally configurable.
- **Request IDs are locally generated only.** There is no remote acknowledgment, duplicate request handling, timeout, retry, or result matching.
- **Status freshness is absent.** `lastSeen` is seeded to a fixed date and updated by the mock stage transitions. There is no heartbeat or online timeout.
- **Invalid/error/offline paths are display states only.** The happy path timer never triggers them. The device card may read as connected even though there is no real hardware, so retain clear demo labeling when refining the UI.
- **Release signing remains template level.** Android has a stable application ID, but release still uses debug signing; review signing and platform setup before distribution.

## Verification and run commands

Run from the **inner** `carepulse/` directory:

```powershell
flutter pub get
flutter run
flutter test
flutter analyze
```

On September 28, 2026, `flutter test` passed **16 widget tests**, `flutter analyze` found no issues, `flutter build web --no-pub` succeeded, and `flutter build apk --debug --no-pub` produced an APK. The built web app visibly reached Sign in after Firebase initialization. An initial plugin setup run hit a Windows symlink check, but the standard test command passed after the builds. No Android runtime, physical device, Apple build, ESP32/sensor, live auth/data, or release build was verified after Phase 3.

On September 27, 2026, `flutter test` completed with **14 passing widget tests** before the logo asset tests were added. `flutter analyze` found no issues and the earlier Android debug APK built. An emulator opened the updated app; the logo was visible on Sign in, but Android System UI/Pixel Launcher dialogs prevented a clean splash capture. Earlier that day, the emulator completed the mock scan through Latest, History, and Details.

## Recommended next agent task

Next, implement Phase 4 Firebase Authentication while preserving isolated UI tests. The login, registration, password reset, sign-out, and auth-state routing still use demo behavior. Keep the mock service available until Phase 5 live data is proven. The ESP32 sketch is a local hardware prototype only.

For Firebase integration, agree on ownership and access rules for the planned `users/{uid}/devices/...` and `users/{uid}/measurements/...` paths, a stable request/result ID contract, server timestamps, disconnect/heartbeat handling, timeout and error behavior, and scan deduplication. Do not invent credentials or publish secrets. Keep medical language neutral and distinguish demonstration data from real measurements.

## September 27, 2026 update

- `lib/screens/home.dart`: separated the optional custom context for `Other` from the optional note, constrained the context dropdown on small screens, and prevented the in-progress button label from overflowing.
- `test/widget_test.dart`: added a complete simulated scan test and a narrow-screen test that confirms custom context and note are saved independently.
- Verification: `flutter test` passed 9 tests; `flutter analyze` reported no issues; a Pixel 9 Pro Android 17 emulator ran the debug app and completed the mock scan through latest, history, and details.
- Physical device, Firebase, ESP32, sensor, and release behavior: not verified.

## September 27, 2026 Phase 2 update

- `lib/screens/demo_session.dart`, `lib/screens/auth.dart`, and `lib/screens/home.dart`: moved mock service creation/disposal to a demo session owner and injected the service into `HomeShell`; sign-out still discards the session.
- `test/widget_test.dart`: uses the same demo session owner as the app for direct dashboard tests.
- `test/phase2_states_test.dart`: added four widget tests covering empty dashboard/history, offline scan gating/device status, and offline/invalid/error scan guidance.
- Verification: `flutter test` passed 13 tests and `flutter analyze` reported no issues. No new emulator, physical device, backend, or sensor behavior was verified after this refactor.

## September 27, 2026 branding update

- The supplied `lib/careplus_logo.png` is a wide **CarePlus** wordmark. The app still uses the **CarePulse** name; only the source image's C/plus emblem was used, without changing product copy.
- `assets/branding/app-mark.png` and `app-icon.png` hold the transparent mark and white square launcher master. `pubspec.yaml` registers the in-app mark. Sign in, registration, and the dashboard header now use it in place of the Material heart.
- `lib/screens/splash.dart` and `lib/main.dart` add a 900 ms opening screen before sign-in. Android and iOS native launch resources and Android, iOS, web, macOS, and Windows launcher icons now use the mark. Display names on those platforms read CarePulse.
- `test/widget_test.dart` covers the splash-to-sign-in transition and advances past the splash in existing auth tests.
- Verification: 14 widget tests passed; `flutter analyze` found no issues; the Android debug APK built and installed. The emulator showed the updated sign-in logo, but its System UI/Pixel Launcher dialogs prevented a clean splash capture. Apple builds and physical device behavior remain unverified.

## Handoff checklist for future updates

When changing this document, record the date, the concrete files/features changed, which commands passed, and which real device/backend behaviors were verified. Move an item from planned to implemented only after confirming it in code or a running integration. Update `../CAREPULSE_CODEX.md` separately if a product decision changes.

## September 27, 2026 ESP32 prototype update

- Added `firmware/carepulse_esp32/carepulse_esp32.ino` for a Serial-triggered 15 second MAX30102 scan with finger detection, BPM/SpO2 algorithm validation, status LEDs, and buzzer feedback.
- Added `firmware/README.md` with the intended ESP32 wiring and upload instructions.
- Verification: source and library API documentation were inspected. Arduino CLI/IDE is not installed in this environment, so the sketch was not compiled or uploaded. No physical wiring, sensor, or app-to-device flow was verified.

## September 27, 2026 beginner firmware guide update

- Simplified `firmware/carepulse_esp32/carepulse_esp32.ino` so `setup()`, `loop()`, and `startScan()` show the main flow directly, with shorter helper functions and clearer comments. The 15 second scan, latest 100 sample calculation, serial trigger, and LED/buzzer feedback remain.
- Added `output/pdf/CarePulse_Arduino_Beginner_Guide.pdf`, a five-page explanation of wiring, code flow, samples, validation, Serial output, and troubleshooting. `firmware/README.md` now links to it.
- Verification: PDF generated and visually reviewed page by page. Arduino toolchain and physical ESP32 remain unavailable, so firmware compilation and hardware behavior are unverified.

## September 28, 2026 Phase 3 Firebase setup

- Created Firebase project `carepulse-joryx-dev`, registered Android (`com.joryx.carepulse`) and web, and generated FlutterFire options and Android configuration. `lib/main.dart` now initializes Firebase before opening the existing demo app.
- Added `firebase_core`, `firebase_auth`, and `firebase_database`. Enabled Email/Password Authentication in the Firebase project.
- Created the default Realtime Database in Singapore (`asia-southeast1`). Its current rules deny all client reads and writes. The proposed account/device/measurement contract is in `PHASE3_FIREBASE.md`; live rules and device identity remain for later phases.
- Preserved demo login, mock scans, and in-memory history. No real account or measurement data was created or fetched.
- Verification: 16 widget tests passed with `flutter test`; `flutter analyze` found no issues; web and Android debug builds succeeded. A local browser opened the web build and showed Sign in after Firebase initialization. Android runtime, physical hardware, Apple platforms, and release behavior remain unverified. Flutter reported a future Kotlin plugin compatibility warning during the Android build.
