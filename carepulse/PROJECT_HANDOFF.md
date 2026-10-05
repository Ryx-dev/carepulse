# CarePulse project handoff

**Status checked:** October 4, 2026
**Application root:** `carepulse/` (the directory containing `pubspec.yaml`)  
**Planning document:** `../CAREPULSE_CODEX.md`

**Architecture update (September 30, 2026):** The user chose BLE for mobile app-to-ESP32 scan control and results, with the phone uploading measurements to Firebase over its own internet connection. The ESP32 does not need Wi-Fi credentials. See `ARCHITECTURE_DECISION_BLE.md`. This decision supersedes the earlier Firebase-to-device scan plan below. BLE scans are connected to the Android Flutter UI and have produced phone-side readings; device ownership, secure pairing, and sensor accuracy remain unverified.

## Read this first

CarePulse has a **live Android BLE scan and Firebase history flow** alongside a local UI demo. A signed-in Samsung SM-A135F completed scans over BLE, stored a pending result through a period without internet, uploaded it when connectivity returned, and displayed it in account History. Firebase Authentication and owner-scoped measurement rules are active in `carepulse-joryx-dev`. The firmware has not been independently validated for sensor accuracy or secure device ownership. Do not describe CarePulse as a medical device.

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
| Login and registration | Firebase Auth calls implemented | `lib/screens/auth.dart`, `lib/services/auth_service.dart`; live web sign-in and backend registration verified, UI registration pending |
| Account persistence/authentication | Firebase Auth state routing implemented | `lib/screens/auth_gate.dart`; a live web session survived reload and sign-out returned to Sign in |
| Main navigation | Implemented | `lib/screens/home.dart`; Home, History, Device, Profile tabs |
| Dashboard | Live account readings on signed-in Android; sample readings in demo flow | `lib/screens/home.dart`, `lib/services/mock_data_service.dart` |
| Scan | BLE device scan in signed-in Android flow; simulated demo scan remains | `lib/screens/live_ble_scan.dart`, `lib/services/ble_device_transport.dart` |
| History and details | Account history, cached offline history, and pending local scans | `lib/screens/pages.dart`, `lib/services/measurement_history_cache.dart` |
| Device status | BLE connection during a live scan; demo state remains simulated | `lib/screens/live_ble_scan.dart`, `lib/screens/pages.dart` |
| Profile/sign out | Firebase account and sign-out implemented | `lib/screens/profile.dart`, `lib/screens/home.dart` |
| Firebase setup | Android/web Auth and deployed owner-scoped Realtime Database rules | `lib/firebase_options.dart`, `firebase.json`, `database.rules.json` |
| Live data | Authenticated phone upload and history read verified once on Samsung SM-A135F | `lib/services/ble_measurement_upload.dart`, `lib/services/firebase_data_repository.dart` |
| ESP32 / sensor | BLE firmware used for phone scans; accuracy and pairing security unverified | `firmware/carepulse_esp32/carepulse_esp32.ino` |
| Automated tests | Flutter suite, parser, sync, and Firebase rules tests | `test/`, `tools/rules/ble_write.test.cjs` |

## How the app currently works

The numbered steps below describe the legacy mock/demo path. Signed-in Android users now have a separate BLE scan, secure pending queue, Firebase upload, cached account History, and live dashboard path described above and in the dated updates below.

1. `main.dart` initializes Firebase using the generated Android/web options, then launches `CarePulseApp`. Android uses its native launch splash and opens `AuthGate` immediately; web and other platforms still show the 900 ms branded Flutter splash. The gate observes Firebase user changes and shows Sign in or the signed-in session.
2. Login and registration validate inputs and call Firebase Email/Password Authentication. Registration saves the name on the Firebase user profile. Forgot password requests a reset email. Firebase errors display readable messages. Sign-out calls Firebase Auth; the gate returns to Sign in when the auth state changes.
3. `DemoSession` creates and owns one `MockDataService` for that signed-in account, then passes it to `HomeShell`. The service initially has one mock online device and four dated sample measurements. Its data lives only in memory and resets when the session is recreated or the app restarts.
4. Home shows the latest item, device state, two recent rows, a context dropdown, an optional note with a 100 character limit, and **Start measurement**. Selecting `Other` reveals a separate optional custom context field with a 40 character limit; leaving it blank saves the activity as `Other`. A demo label appears in the UI.
5. Pressing Start generates a timestamp based request ID and moves the mock service through requesting scan, waiting for finger, scanning, processing, uploading, and complete. The scanning stage counts down from 15 seconds. The new measurement always uses 78 BPM and 98% SpO2, then appears first in the dashboard and history.
6. The scan button is disabled while the simulated scan is active. A scan continues if the scan page is closed because the service belongs to `DemoSession`.
7. History lists the in-memory measurements in current list order. Tapping one opens details with BPM, SpO2, context, note, date/time, scan duration, and device ID.
8. Device shows demo information. Profile shows the Firebase account name/email and labels measurement/device data as a demonstration. Sign-out discards the session's mock data.

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
| `lib/screens/auth.dart` | Login/register UI, validation, Firebase auth calls and errors |
| `lib/services/auth_service.dart`, `lib/screens/auth_gate.dart` | Firebase Auth adapter, account stream, and signed-in routing |
| `lib/services/firebase_data_repository.dart`, `lib/services/live_data_parser.dart` | Read-only live snapshot listeners and model parsing, not yet used by the UI |
| `lib/screens/demo_session.dart` | Owns and disposes the mock service for a demo session |
| `lib/screens/home.dart` | Tab shell receiving mock data, dashboard, scan launch, details routing, sign out |
| `lib/screens/pages.dart` | Shared metric/row widgets; Scan, History, Details, Device screens |
| `lib/screens/profile.dart` | Demo profile and sign out UI |
| `test/widget_test.dart` | Widget tests for auth flow, validation, navigation, layouts, and full mock scan |
| `test/phase2_states_test.dart` | Widget tests for empty, offline, invalid, and error display states |
| `test/live_data_parser_test.dart` | Valid and malformed Realtime Database snapshot parsing |
| `firebase.json`, `database.rules.json`, `PHASE3_FIREBASE.md` | Firebase project setup, locked database rules, and proposed live-data contract |
| `database.phase5-candidate.rules.json`, `tools/rules/`, `PHASE5_ACCESS.md` | Undeployed owner-read rules, emulator tests, and proposed trusted scan flow |
| `pubspec.yaml` | Flutter and Firebase packages, test/lint packages, Nunito assets |

The repository contains standard Flutter generated platform scaffolding for Android, iOS, web, Windows, Linux, and macOS. This does not establish that release builds on each platform have been tested. Firebase is configured only for Android and web. Android now uses `com.joryx.carepulse`; the release build still uses debug signing.

## Progress against the planned phases

- **Phase 1, Flutter UI with mock data:** Complete as a UI demo. Login, registration, dashboard, scan progress, history, details, device, and profile screens were opened on an Android emulator. The demo data is labeled in key screens. A widget test and an emulator run verified the complete simulated scan through its result, latest measurement, history, and details. Empty history/latest views are coded, though no normal UI path empties the seeded history.
- **Phase 2, navigation and local models:** Complete for the planned local UI scope. Measurement and device models, a mock service, reusable theme/formatting/widgets, and working routes/tabs exist. `DemoSession` owns the service while `HomeShell` receives it, allowing isolated UI state tests. Routes remain direct `MaterialPageRoute` or tab switching. There is no repository interface or persistent local store; those are still decisions for live data integration.
- **Phase 3, Firebase setup:** Configured for Android and web in `carepulse-joryx-dev`. Firebase Core initializes at startup. Email/Password Authentication is enabled, and the default Realtime Database is in Singapore with deny-all rules. The UI still uses mock data.
- **Phase 4, real authentication:** Implemented in code for email/password registration, sign-in, password reset, sign-out, and returning-user routing. Widget tests use a fake auth service. The development Firebase backend accepted a temporary account registration, sign-in, and password-reset request. The Flutter web app signed into that account, restored it after reload, and signed out. The account was deleted. UI registration, reset email delivery, and Android runtime remain unverified.
- **Phase 5, live Firebase data:** Read-only UID-scoped listeners, strict parsing, owner-read rules candidate, callable scan request, device credential exchange, provisioning, and an interim USB Serial gateway are implemented and tested locally. All client writes remain denied. Nothing has been deployed or wired to the Flutter UI; no live device or measurement data has been verified.
- **Phase 6, ESP32 firmware:** The Serial-triggered ESP32/MAX30102 prototype now carries request IDs for the USB gateway. There is no on-device Wi-Fi. No compile, wiring, sensor, Firebase, or physical board verification has been performed.

## Known gaps and implementation details to watch

- **Authentication coverage remains partial.** Live web sign-in, reload persistence, and sign-out passed. Flutter UI registration, password reset delivery, error cases against the backend, and Android runtime were not checked.
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

Next, define and implement the BLE request/result protocol, mobile pairing and connection flow, and ESP32 transport; then test a physical ESP32/MAX30102. Add durable phone-side storage and a secure, deduplicated Firebase upload path before connecting live scans to the UI. Keep the mock service available until live data is proven. The USB gateway and Firebase-to-device endpoints are earlier undeployed prototypes. Finish Phase 4 coverage with Flutter UI registration, password reset delivery, and Android runtime testing.

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

## September 28, 2026 Phase 4 authentication implementation

- Added an injectable Firebase Authentication service, auth-state gate, and account-based session routing. Login, registration, password reset, and sign-out now call Firebase Auth. Registration stores the name in the Firebase user profile. Errors appear in the relevant UI.
- The signed-in account's session still owns local mock device state and measurements. Firebase Realtime Database rules still deny all reads and writes; no live data integration was added.
- Updated profile copy and auth widget tests. Nineteen widget tests pass with `flutter test --no-pub`; the final `flutter analyze --no-pub` rerun found no issues.
- At implementation time, live registration, sign-in, reset email delivery, session persistence, and sign-out against the development Firebase project remained unverified. See the follow-up below for the backend smoke check.

## September 28, 2026 Phase 4 backend smoke check

- Used the [Firebase Auth REST API](https://firebase.google.com/docs/reference/rest/auth) with a temporary QA account in `carepulse-joryx-dev`. Registration returned an account, sign-in returned the same UID, and a password-reset request was accepted. The temporary account was deleted successfully. Credentials and tokens were not saved in the repository.
- `flutter build web --no-pub` succeeded. A local browser opened the current build, reached Sign in after Firebase initialization, and displayed validation for an invalid email.
- This did not yet prove a Flutter UI account flow or persisted session at the time of the backend check. See the later web UI check below. Reset email delivery, Android runtime, database access, hardware, and sensor behavior remain unverified.

## September 28, 2026 live web auth and Phase 5 parsing

- With an approved disposable QA account, the current Flutter web build signed in against `carepulse-joryx-dev`, showed the account profile, restored the signed-in dashboard after a browser reload, and returned to Sign in on sign-out. The QA account and temporary credential file were deleted afterward.
- Added `lib/services/live_data_parser.dart` and `lib/services/firebase_data_repository.dart`. The parser rejects incomplete or malformed successful measurements and sorts valid history newest first. The repository has read-only listeners scoped to `users/{uid}`. Neither is wired to the UI, and current database rules still deny access.
- `flutter build web --no-pub`, `flutter test --no-pub` (22 tests), and `flutter analyze --no-pub` passed. No Android runtime, device, sensor, database read/write, UI registration, or reset email delivery was verified.

## September 28, 2026 Phase 5 owner-read candidate

- Added `database.phase5-candidate.rules.json` separately from the deployed `database.rules.json`. It grants authenticated users read access only to their own profile, devices, and measurements. It denies client writes everywhere. `firebase.json` still deploys the original deny-all rules.
- Added `tools/rules/` with locked Firebase emulator test dependencies and a local rules test. `npm test` passed against `demo-carepulse-rules`: owner reads succeeded; guest, cross-user, parent-path, and unspecified-path reads failed; profile, measurement, command, and parent writes failed.
- Added `PHASE5_ACCESS.md` describing the candidate boundary and trusted scan request flow. The emulator test did not contact or change the live database.

## September 28, 2026 Phase 5 local scan endpoint

- Added `functions/startScan` as a Firebase callable in `asia-southeast1`, with `CAREPULSE_DATABASE_URL` configuration documented in `PHASE5_ACCESS.md`. It uses the authenticated UID, validates scan input, checks a 60-second device heartbeat and `ready` state, and atomically writes one pending command with a unique request ID. It rejects a concurrent request and leaves client database writes denied.
- Added a separate emulator integration test in `functions/test/start_scan.test.cjs`. `npm run test:scan` from `tools/rules` passed, including concurrent requests, cross-owner device access, missing authentication, malformed input, stale/future heartbeats, non-ready state, and command completion. The callable module loaded with Firebase SDK dependencies.
- At this checkpoint, no endpoint or candidate rules were deployed and no device identity or command consumer existed. The next checkpoint below adds a local implementation. A timeout worker, live UI wiring, and real sensor scan are still absent. The function needs `CAREPULSE_DATABASE_URL` at runtime; see `PHASE5_ACCESS.md`.

## September 28, 2026 Phase 5 device exchange and USB bridge

- Added a device-specific token provisioner. A private `deviceBindings/{deviceId}` record holds the owner UID and token hash; the device exchange accepts only that token and derives its user path from the binding. Provisioning was tested in the emulator and was not run against the live project.
- Added `deviceExchange` HTTP actions for heartbeat, one-time command pickup, and result or failure reporting. It validates request IDs and 15-second result bounds, writes successful measurements under the matching request ID, and handles identical retries. The emulator test passed for credential rejection, owner isolation, command claim, valid results, invalid results, and duplicate reports.
- Added `tools/gateway/` as an interim Node USB Serial bridge for the current sketch. The sketch now accepts `SCAN <requestId>`, echoes that ID on scan lines, and rejects a repeated ID within one boot. Two simulated gateway tests passed, and the SerialPort binding loaded on this Windows host. Arduino compilation and a physical ESP32/MAX30102 remain unverified.
- The endpoint, rules candidate, and gateway have not been deployed or run with a real device. The app still uses mock data. A server timeout/offline worker and on-device Wi-Fi transport remain future work; see `PHASE5_ACCESS.md`.

## September 29, 2026 password reset delivery follow-up

- A user reported that an existing account could sign in but its password reset email did not arrive. The app calls Firebase Auth's `sendPasswordResetEmail`; the response confirms request acceptance, not inbox delivery. After the user signed into Firebase Console manually, Authentication > Sign-in method showed Email/Password disabled in `carepulse-joryx-dev`, while Authentication > Templates > SMTP settings showed custom SMTP disabled. The user enabled Email/Password in the console; a refreshed provider page showed its status as Enabled. Custom SMTP remained off.
- The sign-in screen now shows a persistent confirmation with the exact requested address and inbox/spam guidance, instead of a short snackbar claiming the link was sent. A disabled-provider error also has a specific message. The widget tests passed and `flutter analyze --no-pub` found no issues before the final error-message addition.
- The user received a reset email, but its action page displayed "The selected page mode is invalid." The link had `mode=resetPassword` but the user reported an empty `apiKey` value. Firebase generates the action link's API key, so the app's current `sendPasswordResetEmail` call cannot fill it. A new reset email after enabling the provider is being checked; the completed password change remains unverified. If a new link still lacks the API key, inspect Firebase Hosting configuration and contact Firebase Support about the backend key mapping.

## October 2, 2026 BLE upload account guard

- `BleMeasurementUpload.save` now requires the UID that owns the local queue and checks it against the current Firebase user before writing. A retry after an account switch therefore leaves the prior account's result pending instead of writing it under the new account.
- Added `tools/rules/ble_write.test.cjs` to exercise the active BLE measurement rules, including valid owner writes, retry, rejected cross-account writes, malformed records, and deletion.
- `flutter test --no-pub test/ble_measurement_sync_test.dart` passed (4 tests). The Firebase emulator test could not start in this sandbox because port 9000 could not be opened; it remains unverified. Flutter analysis did not finish in this environment.
- The next real-world checkpoint remains an authenticated phone-to-Firebase upload and history read, plus physical BLE ownership/pairing validation. No live cloud write or hardware scan was performed in this checkpoint.

## October 2, 2026 offline history display

- Added `MeasurementHistoryCache` using account-scoped secure storage. Dashboard and History show the last fetched cloud measurements after restart without internet, and refresh that copy when Firebase emits a new snapshot.
- Pending offline scans continue to be stored separately and now appear immediately as the latest dashboard measurement as well as in History. The existing sync service retries uploads on connectivity changes, app resume, and its one-minute timer.
- The BLE sync and parser tests passed (7 tests). A physical offline/reconnect test and full Flutter analysis remain to be completed.

## October 2, 2026 measurement retry integrity

- Tightened `database.rules.json` so a completed measurement can be written again only with the same field values. This preserves idempotent retries while rejecting changes to an existing scan ID. Added changed BPM and note cases to `tools/rules/ble_write.test.cjs`.
- `flutter test --no-pub` passed (30 tests). The Firebase emulator could not bind port 9000, so the BLE rules test now uses a separate local emulator configuration on port 19000. It passed, including identical retry, changed BPM and note, cross-account access, malformed records, and deletion. `flutter analyze --no-pub` produced no output and was stopped.
- With user approval, `firebase deploy --only database --project carepulse-joryx-dev --config firebase.json` succeeded on October 2, 2026. Firebase reported valid syntax and a successful release to `carepulse-joryx-dev-default-rtdb`. No live client write/read was performed after deployment.
- A connected Samsung SM-A135F has CarePulse 1.0.0 installed, but the phone was on its lock/dream screen during this check. No sign-in state, BLE device, authenticated upload, or history read was verified. Next, perform an authenticated phone upload and history read. Physical BLE pairing and a real sensor scan still need hardware verification.

## October 2, 2026 connected phone upload follow-up

- The unlocked Samsung SM-A135F opened CarePulse in a signed-in session. The dashboard showed one real BLE scan saved locally and still pending upload. It remained pending after a retry cycle; the app did not expose its upload error. An authenticated cloud read or write was not confirmed.
- Added a short, non-sensitive upload failure message to the dashboard and live history for timeout, Firebase permission, account mismatch, and other failures. `flutter test --no-pub test/ble_measurement_sync_test.dart` passed, Dart analysis of changed files found no issues, and a debug APK built successfully.
- Installed the updated debug APK with `adb install -r`, preserving app data. The phone screen returned to its lock/dream display before the new diagnostic could be read. The pending scan should remain in secure storage; recheck its message and retry when the phone is unlocked.
- On the next unlocked check, the app showed `Upload timed out`. The phone could not resolve either `google.com` or the Firebase database host, while Android confirmed CarePulse had internet permission. After the user enabled internet, both names resolved and were reachable. The pending card disappeared automatically, and the same scan appeared at the top of live History alongside four earlier readings. This verifies one real phone-to-Firebase upload and account history read on the Samsung SM-A135F. It does not verify BLE ownership, pairing security, sensor accuracy, or offline/reconnect behavior across a fresh scan.
- After the phone check, `flutter test --no-pub` passed all 30 tests. The revised top-level handoff and README now reflect the verified live flow.

## October 2, 2026 BLE pairing prototype

- Added a generated, NVS-stored 128-bit pairing code to the ESP32 sketch and a mutual HMAC challenge-response over four short BLE frames. The firmware gates scan writes and notifications on successful pairing for each connection. The app prompts for the code once, verifies the device, and keeps it in encrypted account-scoped phone storage.
- Added deterministic protocol tests covering code parsing, HMAC vectors, wrong proofs, repeated challenges, and premature completion. `flutter test --no-pub` passed 33 tests; Dart analysis of the changed pairing files found no issues. The installed ESP32 BLE header confirms the binary characteristic API used by the sketch.
- The Android debug APK and ESP32 sketch both compiled successfully. The firmware was flashed to the connected ESP32-D0WD-V3 on COM9, and the matching debug APK was installed on the Samsung SM-A135F without clearing app data. USB Serial confirmed a private pairing code was generated, but startup reported `max30102_not_found`; the sensor scan is blocked. Pairing itself remains unverified. This handshake authenticates a shared physical pairing code but does not itself encrypt BLE payloads or prevent active relays.
- A follow-up phone interaction was stopped by automatic approval review because this session hit its usage limit. No further phone input was attempted. When access resumes, verify the pairing prompt and handshake, then inspect MAX30102 power and SDA/SCL wiring (firmware pins 18/19) before testing a scan.

## October 2, 2026 tap-to-connect revision

- At the user's request, the code-entry pairing prototype was replaced with a tap-to-connect BLE session. The app waits for a `P` / `T` readiness exchange and offers Disconnect. The ESP32 advertises only while free and releases the session on disconnect.
- This is temporary connection access without a persistent device owner or an authenticated Bluetooth bond. Any nearby phone can connect when the ESP32 is free; a dropped connection also makes it available. Firebase measurements still upload under the signed-in phone account.
- The revised APK was installed on the Samsung SM-A135F and the user uploaded the firmware. The phone discovered the ESP32, connected without a code, disconnected, and reconnected successfully. The earlier ESP32 flash reported `max30102_not_found`; a complete sensor scan remains unverified.

## October 4, 2026 sensor calibration and reading quality

- After the sensor was mounted in its housing, the user reported an app reading of 187 BPM without a simultaneous reference pulse or Serial log. This value has not been verified.
- Added `CAL EMPTY`, `CAL FINGER`, and `CAL RESET` Serial commands. The mounted sensor's empty and finger IR ranges produce a saved contact threshold; weak separation is rejected. See `firmware/README.md` for the procedure.
- A scan now collects 125 pairs at an expected 25 Hz, rejects flat or saturated IR and timing errors, and compares BPM from two overlapping 100-sample windows before sending a result. The app explains the new signal-quality failure.
- The BLE screen tests passed. Flutter/Dart analysis did not return in this environment and was stopped. The ESP32 sketch could not be compiled or flashed here because an Arduino CLI was not available; housing calibration and result accuracy still require physical verification with a reference pulse measurement.

## October 4, 2026 app and Firebase queue progress

- The user asked to defer physical calibration and continue the app/Firebase flow. `BleMeasurementSync` now attempts each queued scan once per retry pass. A record that fails upload remains encrypted on the phone while later records can still upload. The first failure stays visible; it clears after a fully successful retry.
- A second guard rejects a different scan that reuses a pending request ID instead of silently dropping its result. Regression tests cover both behaviors. All six BLE sync tests and the full 39-test Flutter suite passed. A debug APK build gave no output for 90 seconds and was stopped; ADB could not launch in this sandbox (`Access is denied`). These are local tests; no new live Firebase write or offline phone scan was performed in this checkpoint.
