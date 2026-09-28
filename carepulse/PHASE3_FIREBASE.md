# Phase 3 Firebase setup

This document records the setup boundary and the proposed data contract before
the app or ESP32 exchanges live data. The Flutter app remains a mock-data demo
until the later authentication and live-data phases are implemented.

## Scope

- Configure one Firebase project for Android and web with FlutterFire.
- Add `firebase_core`, `firebase_auth`, and `firebase_database` and initialize
  Firebase from the generated platform options.
- Keep demo sign-in and `MockDataService` working while Firebase is introduced.
- Verify app startup, widget tests, `flutter analyze`, and Android/web builds.

Phase 4 will replace demo account actions with Firebase Authentication. Phase 5
will read and write device state, commands, and measurements. The ESP32 sketch
still uses USB Serial; its Firebase connection belongs to later integration.

## Proposed Realtime Database contract

The starting tree follows `CAREPULSE_CODEX.md`:

```text
users/{uid}/profile/{name,email}
users/{uid}/devices/{deviceId}/{name,online,state,sensorStatus,lastSeen}
users/{uid}/devices/{deviceId}/command/{action,requestId,activity,note,createdAt}
users/{uid}/measurements/{requestId}/{requestId,deviceId,bpm,spo2,activity,note,scanDuration,timestamp}
```

- `uid` is the Firebase Authentication user ID, not the email address.
- Each scan gets a unique `requestId`. The same ID matches its command and
  measurement; the device must ignore IDs it has already processed.
- `activity` holds the selected or custom context. `note` remains independent.
- Timestamps should come from a trusted server operation where possible. A
  stale `lastSeen` must not be treated as proof that the device is online.
- A failed or invalid scan must report its state and reason without creating a
  successful measurement record.

## Access before live data

Keep Realtime Database access locked while the app has demo authentication.
For live data, a signed-in person should access only their own `users/{uid}`
tree. The app should write its profile and scan command; the device should write
its status and validated result. Device identity and its narrow write permission
must be designed before enabling firmware writes. Do not embed a person's
password or an unrestricted database credential in the ESP32 firmware.

## Configuration status

- Firebase project: `carepulse-joryx-dev` (development project).
- Flutter Firebase packages: added to `pubspec.yaml`.
- Android app: registered as `com.joryx.carepulse`; web app: registered.
- FlutterFire generated `lib/firebase_options.dart` and Android
  `android/app/google-services.json`. `main.dart` initializes Firebase.
- Email/Password Authentication provider: enabled in the project.
- Default Realtime Database: `asia-southeast1` (Singapore). Its current
  `database.rules.json` denies all reads and writes, including signed-in users.
- Real login, live scans, and device communication: outside Phase 3.

All 16 widget tests pass with `flutter test`; `flutter analyze`, the web build,
and the Android debug build also pass. The first plugin setup run hit a Windows
symlink check, but the standard test command passed after the builds. The web
build visibly reached Sign in after Firebase initialization. Android runtime
verification is still pending.
