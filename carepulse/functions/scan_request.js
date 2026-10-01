const { randomUUID } = require('node:crypto');

const HEARTBEAT_MAX_AGE_MS = 60_000;
const CLOCK_SKEW_ALLOWANCE_MS = 5_000;
const TERMINAL_STATUSES = new Set(['complete', 'invalid', 'error', 'timed_out']);

class ScanRequestError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function scanInput(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new ScanRequestError('invalid-argument', 'A scan request is required.');
  }
  const { deviceId, activity, note = '' } = data;
  if (typeof deviceId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(deviceId)) {
    throw new ScanRequestError('invalid-argument', 'Choose a valid device.');
  }
  if (typeof activity !== 'string' || !activity.trim() || activity.trim().length > 40) {
    throw new ScanRequestError('invalid-argument', 'Activity must be 1–40 characters.');
  }
  if (typeof note !== 'string' || note.length > 100) {
    throw new ScanRequestError('invalid-argument', 'Note must be at most 100 characters.');
  }
  return { deviceId, activity: activity.trim(), note };
}

function isReady(device, now) {
  if (!device || typeof device !== 'object' || Array.isArray(device)) return false;
  if (device.online !== true || device.state !== 'ready') return false;
  const lastSeen = device.lastSeen;
  return Number.isSafeInteger(lastSeen) &&
    lastSeen > 0 &&
    lastSeen <= now + CLOCK_SKEW_ALLOWANCE_MS &&
    now - lastSeen <= HEARTBEAT_MAX_AGE_MS;
}

function hasActiveCommand(command) {
  if (command == null) return false;
  if (!command || typeof command !== 'object' || Array.isArray(command)) return true;
  return !TERMINAL_STATUSES.has(command.status);
}

function createStartScan({ database, clock = Date.now, newRequestId = randomUUID }) {
  return async ({ auth, data }) => {
    if (!auth?.uid) {
      throw new ScanRequestError('unauthenticated', 'Sign in to start a scan.');
    }
    const input = scanInput(data);
    const now = clock();
    const requestId = newRequestId();
    const ref = database.ref(`users/${auth.uid}/devices/${input.deviceId}`);
    const initial = (await ref.get()).val();
    if (!isReady(initial, now) || hasActiveCommand(initial.command)) {
      throw new ScanRequestError('failed-precondition', 'Device is unavailable or already scanning.');
    }
    const result = await ref.transaction((device) => {
      // The SDK may initially call this with null before loading server data.
      // Returning null lets it retry against the actual value without creating
      // a command. A missing/deleted device is rejected after the transaction.
      if (device === null) return null;
      if (!isReady(device, now) || hasActiveCommand(device.command)) return;
      return {
        ...device,
        command: {
          action: 'start_scan',
          requestId,
          activity: input.activity,
          note: input.note,
          createdAt: now,
          status: 'pending',
        },
      };
    }, undefined, false);
    if (!result.committed || result.snapshot.val()?.command?.requestId !== requestId) {
      throw new ScanRequestError('failed-precondition', 'Device is unavailable or already scanning.');
    }
    return { requestId };
  };
}

module.exports = { createStartScan, ScanRequestError, HEARTBEAT_MAX_AGE_MS };
