# CarePulse connection decision — September 30, 2026

The user chose **BLE between the Flutter mobile app and ESP32 for scan control and results**. The phone uses its own Wi-Fi or mobile-data connection to save measurements in Firebase. The ESP32 does not need Wi-Fi setup, Firebase credentials, or a USB gateway during normal use.

## Intended scan flow

1. The signed-in mobile app discovers and connects to the user's nearby ESP32 over BLE.
2. The app sends a scan request with a unique request ID, context, and optional note.
3. The ESP32 allows up to 10 seconds from the scan request to collect 100 samples and returns status and a result tagged with that request ID.
4. The app validates and displays the result, then uploads it to the signed-in user's Firebase history through an authorized write path.
5. If the phone has no internet, it stores the completed result in encrypted, account-scoped local storage and retries the upload when connectivity returns. The same request ID prevents duplicates.

The phone must stay in BLE range for a scan. A dropped connection needs a clear failure or reconnection state. Device pairing and ownership, BLE message format, result validation, local persistence, and Firebase write authorization must be designed and tested before live use. The sensor result is personal measurement data, not a diagnosis.

## Effect on existing Phase 5 work

The `startScan` callable, device exchange endpoint, token provisioner, USB gateway, and pending-command flow implement the earlier Firebase-to-device architecture. They remain local prototypes and are not the deployment path for BLE. The development project is on the Firebase Spark plan, so the HTTP upload function could not be deployed. The mobile app now writes directly to Realtime Database using Firebase Authentication; deployed rules limit writes to validated measurements under the owner's UID.

The original firmware accepted scan commands over USB Serial. The BLE scan flow has been physically tested through the Flutter debug APK. The app now saves completed results locally first, displays pending uploads in History, and retries the authenticated database write on connectivity changes, app resume, and a one-minute timer. The owner-scoped rules are deployed; an end-to-end phone/cloud test remains. A successful cloud response removes the local pending copy. Uploaded records retain the time of the original scan.

## Next implementation steps

1. Define the BLE service/characteristics, request/result frames, request ID handling, and pairing/ownership flow.
2. Add ESP32 BLE command and result transport around the existing sensor routine; verify it on a physical board.
3. Add mobile BLE discovery, connection, scan state, reconnect/error handling, and platform permissions.
4. Add durable local result storage and authenticated, owner-scoped Firebase writes with request ID deduplication.
5. Connect the live flow to the UI, then test complete scans, connection loss, offline uploads, retries, and cross-account access on hardware.

The existing web build can continue as an account/history view, but direct BLE scans require a supported mobile platform implementation.

## BLE prototype protocol (in progress)

The firmware and Dart parser now share one 128-bit service UUID with a write
command characteristic and a notification characteristic, defined in
`lib/services/ble_protocol.dart`. Frames use ASCII and fit the default 20-byte
notification payload. A mobile scan command is `S|A1B2C3D4`, where the ID is
eight uppercase hexadecimal characters. Notifications for that ID are `W`
(waiting for finger), `S` (scanning), `P` (processing), `C|ID|BPM|SPO2`
(complete), `I|ID|CODE` (invalid), or `E|ID|CODE` (error). The scan ends after
100 collected samples or a 10-second deadline. The app must ignore notifications for other IDs.

This is a transport prototype, not secure pairing. The firmware advertises a
CarePulse BLE service and currently accepts a nearby write without device
ownership verification. Do not use it with personal measurements until pairing,
authorization, and physical tests are complete. An Android/iOS BLE transport
adapter is now in `lib/services/ble_device_transport.dart`; it discovers the
service, connects, subscribes to notifications, sends scan commands, and
matches events to the active request ID. The mobile home screen opens a live
BLE scan flow that discovers, connects, sends a scan, and displays the result.
Firebase upload code, encrypted offline storage, and live account history are implemented. Database rules are deployed to the development project; phone/cloud verification remains. Ownership pairing remains pending. Live results are separate from demo history.
