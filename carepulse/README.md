# CarePulse

CarePulse is a Flutter prototype for an app-controlled ESP32/MAX30102 heart-rate and SpO₂ logger. Android and web are configured for Firebase. The app uses Firebase Authentication for accounts, while all displayed measurements, device status, and scans remain local demonstration data.

## Run

From this directory:

```powershell
flutter pub get
flutter run
flutter test
flutter analyze
```

Firebase configuration currently supports Android and web. The Realtime Database rules deny all client access until the device and ownership model is implemented.

See [PROJECT_HANDOFF.md](PROJECT_HANDOFF.md) for phase status and [PHASE3_FIREBASE.md](PHASE3_FIREBASE.md) for the proposed data contract. The standalone USB Serial firmware prototype is documented in [firmware/README.md](firmware/README.md).
