# CarePulse

CarePulse is a Flutter prototype for an app-controlled ESP32/MAX30102 heart-rate and SpO₂ logger. Android and web are configured for Firebase. The app uses Firebase Authentication for accounts, while all displayed measurements, device status, and scans remain local demonstration data.

The live architecture is **mobile app ↔ ESP32 over BLE** for scans, with the **phone uploading results to Firebase Realtime Database** over its own internet connection. BLE scanning has been verified in a debug APK. Completed scans are saved in encrypted local storage until the authenticated upload succeeds. Previously fetched history is cached for offline viewing, and new offline scans appear as pending measurements. Owner-scoped database rules are deployed to `carepulse-joryx-dev`; phone-to-cloud verification is next. See [ARCHITECTURE_DECISION_BLE.md](ARCHITECTURE_DECISION_BLE.md). Earlier Firebase-to-device and USB gateway code remains an undeployed prototype.

## Run

From this directory:

```powershell
flutter pub get
flutter run
flutter test
flutter analyze
```

Firebase configuration currently supports Android and web. Realtime Database rules allow signed-in users to read their own history and write validated measurements under their own account.

See [PROJECT_HANDOFF.md](PROJECT_HANDOFF.md) for phase status, [PHASE3_FIREBASE.md](PHASE3_FIREBASE.md) for the initial data proposal, and [PHASE5_ACCESS.md](PHASE5_ACCESS.md) for the tested owner-read rules candidate, local scan endpoints, and USB gateway. These are not deployed or connected to the UI. The ESP32 Serial firmware prototype is documented in [firmware/README.md](firmware/README.md).
