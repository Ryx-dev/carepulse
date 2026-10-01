const { createHash, timingSafeEqual } = require('node:crypto');

const DEVICE_ID = /^[A-Za-z0-9_-]{1,64}$/;
const DEVICE_TOKEN = /^[A-Za-z0-9_-]{43}$/;
const UID = /^[A-Za-z0-9_-]{1,128}$/;
const FAILURE_REASONS = new Set([
  'no_finger', 'finger_removed', 'too_few_samples', 'algorithm_rejected',
  'sensor_timeout', 'max30102_not_found', 'i2c_setup_failed',
]);

class DeviceExchangeError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function sha256(token) {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

function sameHash(a, b) {
  if (typeof a !== 'string' || !/^[a-f0-9]{64}$/.test(a)) return false;
  return timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

function fail(status, message) {
  throw new DeviceExchangeError(status, message);
}

function requireObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(400, 'A JSON object is required.');
  }
  return value;
}

function checkedId(value, label) {
  if (typeof value !== 'string' || !DEVICE_ID.test(value)) fail(400, `Invalid ${label}.`);
  return value;
}

function isCommand(device, requestId, statuses) {
  return device && typeof device === 'object' &&
    device.command?.requestId === requestId &&
    statuses.includes(device.command.status);
}

async function updateDevice(ref, update) {
  const before = (await ref.get()).val();
  if (!before || typeof before !== 'object') fail(409, 'Device is not provisioned.');
  const result = await ref.transaction((device) => {
    if (device === null) return null; // SDK's first local value can be null.
    return update(device);
  }, undefined, false);
  if (!result.committed || !result.snapshot.val()) fail(409, 'Device state changed.');
  return result.snapshot.val();
}

function validResult(body) {
  const { status, bpm, spo2, scanDuration, reason } = body;
  if (status === 'complete') {
    if (!Number.isInteger(bpm) || bpm < 1 || bpm > 250 ||
        !Number.isInteger(spo2) || spo2 < 0 || spo2 > 100 ||
        !Number.isInteger(scanDuration) || scanDuration < 1 ||
        scanDuration > 10 || reason !== undefined) {
      fail(400, 'Invalid scan result.');
    }
    return { status, bpm, spo2, scanDuration };
  }
  if ((status !== 'invalid' && status !== 'error') || !FAILURE_REASONS.has(reason) ||
      bpm !== undefined || spo2 !== undefined || scanDuration !== undefined) {
    fail(400, 'Invalid scan failure.');
  }
  return { status, reason };
}

function sameResult(command, report) {
  if (report.status === 'complete') {
    return command.result?.bpm === report.bpm &&
      command.result?.spo2 === report.spo2 &&
      command.result?.scanDuration === report.scanDuration;
  }
  return command.status === report.status && command.reason === report.reason;
}

function sameMeasurement(actual, expected) {
  return actual && typeof actual === 'object' &&
    Object.keys(expected).every((key) => actual[key] === expected[key]) &&
    Object.keys(actual).length === Object.keys(expected).length;
}

function createDeviceExchange({ database, clock = Date.now }) {
  return async ({ authorization, body }) => {
    const data = requireObject(body);
    const deviceId = checkedId(data.deviceId, 'device ID');
    const match = typeof authorization === 'string' &&
      /^Bearer ([A-Za-z0-9_-]{43})$/.exec(authorization);
    if (!match || !DEVICE_TOKEN.test(match[1])) fail(401, 'Invalid device credential.');
    const binding = (await database.ref(`deviceBindings/${deviceId}`).get()).val();
    if (!binding || !UID.test(binding.uid) ||
        !sameHash(binding.tokenHash, sha256(match[1]))) {
      fail(401, 'Invalid device credential.');
    }
    const uid = binding.uid;
    const ref = database.ref(`users/${uid}/devices/${deviceId}`);
    const now = clock();

    if (data.action === 'heartbeat') {
      if (data.sensorStatus !== 'connected' && data.sensorStatus !== 'error') {
        fail(400, 'Invalid sensor status.');
      }
      await updateDevice(ref, (device) => ({
        ...device, online: true, lastSeen: now, sensorStatus: data.sensorStatus,
        state: data.sensorStatus === 'error' && device.command?.status !== 'pending'
          ? 'error'
          : data.sensorStatus === 'connected' && device.state === 'error' &&
              (!device.command || ['complete', 'invalid', 'error', 'timed_out'].includes(device.command.status))
            ? 'ready' : device.state,
      }));
      return { ok: true };
    }

    if (data.action === 'offline') {
      await updateDevice(ref, (device) => ({
        ...device, online: false, state: 'offline',
      }));
      return { ok: true };
    }

    if (data.action === 'poll') {
      const initial = (await ref.get()).val();
      if (!initial || typeof initial !== 'object') fail(409, 'Device is not provisioned.');
      if (initial.command?.status !== 'pending') return { command: null };
      const requestId = initial.command.requestId;
      const after = await updateDevice(ref, (device) => {
        if (!isCommand(device, requestId, ['pending']) || device.state !== 'ready') return;
        return {
          ...device, state: 'waiting_for_finger',
          command: { ...device.command, status: 'acknowledged', acknowledgedAt: now },
        };
      });
      return { command: { action: 'start_scan', requestId: after.command.requestId } };
    }

    if (data.action === 'report') {
      const requestId = checkedId(data.requestId, 'request ID');
      const report = validResult(data);
      const after = await updateDevice(ref, (device) => {
        if (!isCommand(device, requestId,
            ['acknowledged', 'scanning', 'processing', 'uploading', 'complete', 'invalid', 'error'])) {
          return;
        }
        const command = device.command;
        if (['uploading', 'complete', 'invalid', 'error'].includes(command.status)) {
          return sameResult(command, report) ? device : undefined;
        }
        if (report.status === 'complete') {
          return {
            ...device, state: 'uploading',
            command: {
              ...command, status: 'uploading',
              result: { bpm: report.bpm, spo2: report.spo2,
                scanDuration: report.scanDuration },
              completedAt: now,
            },
          };
        }
        return {
          ...device, state: report.status === 'error' ? 'error' : 'ready',
          command: { ...command, status: report.status, reason: report.reason,
            completedAt: now },
        };
      });
      if (report.status !== 'complete') return { ok: true };
      const command = after.command;
      const measurement = {
        requestId, deviceId, bpm: report.bpm, spo2: report.spo2,
        activity: command.activity, note: command.note,
        scanDuration: report.scanDuration, timestamp: command.completedAt,
      };
      const measurementRef = database.ref(`users/${uid}/measurements/${requestId}`);
      const written = await measurementRef.transaction((current) =>
        current === null ? measurement : undefined, undefined, false);
      if (!written.committed && !sameMeasurement(written.snapshot.val(), measurement)) {
        fail(409, 'Measurement ID already exists.');
      }
      await updateDevice(ref, (device) => {
        if (!isCommand(device, requestId, ['uploading', 'complete']) ||
            !sameResult(device.command, report)) return;
        if (device.command.status === 'complete') return device;
        return {
          ...device, state: 'ready',
          command: { ...device.command, status: 'complete' },
        };
      });
      return { ok: true };
    }
    fail(400, 'Unknown device action.');
  };
}

module.exports = { createDeviceExchange, DeviceExchangeError, sha256 };
