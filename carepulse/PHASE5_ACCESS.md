# Phase 5 access and scan contract

> **Historical prototype:** The September 30, 2026 decision in
> [ARCHITECTURE_DECISION_BLE.md](ARCHITECTURE_DECISION_BLE.md) selects app-to-ESP32
> BLE scans with phone-to-Firebase uploads. The scan callable, device exchange,
> and USB gateway below describe the earlier, undeployed architecture. Do not
> deploy them as the chosen scan path.

This is the development bridge from authenticated accounts to live ESP32 scans. It is
not deployed or connected to the Flutter UI. `firebase.json` still points to
`database.rules.json`, which denies every client read and write.

## Owner-only read candidate

`database.phase5-candidate.rules.json` allows a Firebase Authentication user to
read only these paths under their own UID:

```text
users/{uid}/profile
users/{uid}/devices
users/{uid}/measurements
```

Reading `users`, `users/{uid}`, another user's paths, or any unspecified child
remains denied. All client writes remain denied, including profile edits, scan
commands, device status, and measurements. The Flutter app's current
`FirebaseDataRepository` is read-only and is not used by the UI yet.
Do not store device credentials or pairing secrets inside the owner-readable
`profile`, `devices`, or `measurements` subtrees.

The candidate is tested against the local Realtime Database emulator in
`tools/rules/rules.test.cjs`. It has **not** been deployed to the development
Firebase project. Do not change `firebase.json` to point to it until the
remaining Phase 5 access and device work is ready for review.

## Scan request endpoint

`functions/index.js` exports a Firebase callable `startScan` in
`asia-southeast1`. `functions/scan_request.js` requires Firebase Authentication,
validates `deviceId`, `activity` (1–40 characters), and `note` (at most 100
characters), then uses the authenticated UID to select the device path. The
device must be online, `ready`, and have a numeric `lastSeen` no older than 60
seconds. Up to 5 seconds of positive clock skew is tolerated. A transaction on
the complete device node rechecks those conditions and refuses an active
command. On success it writes a UUID `requestId`,
`start_scan` action, activity, note, server-function `createdAt` milliseconds,
and `pending` status. It returns only the request ID to the app.

An earlier command is considered finished only with `complete`, `invalid`,
`error`, or `timed_out` status. The device exchange sets terminal status and
restores the device to `ready` after a successful or invalid scan. The app
cannot do either.
If the device disappears during the transaction, the endpoint rejects the
request. There is no automatic server timeout worker yet, so a command left
pending by a crashed gateway will block new scans until a trusted service
resolves it.

The function requires this runtime environment variable:

```text
CAREPULSE_DATABASE_URL=https://<project-database-host>
```

Set `CAREPULSE_DATABASE_URL` for the Functions runtime before deployment. The
value must identify the same project's Realtime Database as the app. No `.env`
file or production URL is committed, and the function has not been deployed.
`firebase.json` lists `functions/` as a source but still deploys the deny-all
rules file. No function or rules candidate has been deployed.

## Device credential and exchange

`functions/deviceExchange` is an HTTP POST endpoint for one provisioned device.
The body contains `deviceId` and one action: `heartbeat`, `poll`, `report`, or
`offline`.
The request uses `Authorization: Bearer <device token>` over HTTPS. The token
is 32 random bytes encoded as base64url. Only its SHA-256 hash and owner UID are
stored under `deviceBindings/{deviceId}`, outside the owner-readable paths.
The endpoint compares hashes with a constant-time operation and derives the
database path from the binding, not a caller-supplied UID. A token is scoped to
one device; it is not a Firebase Admin credential.

An administrator can run `functions/tools/provision_device.cjs` with an existing
Firebase Auth UID, a unique device ID, and a name after setting
`CAREPULSE_DATABASE_URL` and Application Default Credentials. It creates the
private binding and an offline device record, then prints the token **once**.
Store the token outside the repository. Provisioning has not been run against
the live project and no live device binding exists from this work.

`heartbeat` sets the server-side `lastSeen`, `online`, and sensor status.
`offline` marks the device disconnected when the USB port closes.
`poll` atomically changes a pending command to `acknowledged` and returns its
`requestId` once. `report` accepts either a bounded 15-second result or a
recognized failure reason for that request. A successful result is stored at
`users/{uid}/measurements/{requestId}`; retries with the same result are
idempotent. Invalid or error reports create no successful measurement. This
validates the message shape and request match; it cannot prove that a physical
sensor produced the readings.

## USB Serial gateway

`tools/gateway/run.cjs` is an interim bridge to the existing USB Serial sketch.
It uses a provisioned device token, polls the exchange endpoint, sends
`SCAN <requestId>` at 115200 baud, and forwards only Serial lines containing
that same request ID. The ESP32 sketch still has no Wi-Fi or Firebase library.
It rejects a repeated request ID within one boot. The gateway retries a failed
report and reports a sensor timeout after 45 seconds without a terminal line.
It requires a computer with the ESP32 connected by USB and Node 22 or newer.

Set `CAREPULSE_DEVICE_URL`, `CAREPULSE_DEVICE_ID`,
`CAREPULSE_DEVICE_TOKEN`, and `CAREPULSE_SERIAL_PORT` in the gateway process
environment, then run `node run.cjs` from `tools/gateway`. The URL must use
HTTPS outside localhost. Do not put the token in firmware, source control, or
an app bundle. Neither this gateway nor the endpoint has been exercised with a
physical ESP32.

## Remaining end-to-end work

1. The signed-in app calls `startScan` with `deviceId`, selected `activity`, and
   optional `note`. The app does not write the database command path directly.
2. Provision a real device and exercise the Serial gateway with the physical
   ESP32/MAX30102. Later, replace the USB bridge with an on-device network
   transport if standalone Wi-Fi operation is required.
3. Add a server timeout and offline worker so a crashed gateway cannot leave a
   command pending forever and a stale device does not appear connected.
4. Wire the Flutter app to the live callable and read-only repository, with
   retry and error states. Review the rules candidate and deploy the complete
   system only after the device and app paths have been verified.

The `command` node in `PHASE3_FIREBASE.md` is server-written only, never an
enabled client write.

## Verification

Run `npm ci` in both `tools/rules` and `functions`. From `tools/rules`, `npm test`
starts a local Realtime Database emulator under `demo-carepulse-rules`, loads
the candidate rules, seeds test data without rules, and checks owner,
cross-user, guest, parent-path, unspecified-path, and client-write behavior.
`npm run test:scan` starts a separate emulator under `demo-carepulse-functions`
and checks authorization, inputs, heartbeat and state gating, UID-scoped paths,
successful command contents, and concurrent requests. Neither demo project
touches the live Firebase database.
`npm run test:device` uses `demo-carepulse-device` to verify provisioning,
credential isolation, heartbeat, command claim, valid and invalid reports, and
idempotent result storage. In `tools/gateway`, `npm ci` followed by `npm test`
checks Serial request matching and report forwarding with simulated lines.

Flutter verification remains `flutter test --no-pub` and
`flutter analyze --no-pub` from the app root. These do not prove live database
access because the deployed rules intentionally remain deny-all.
