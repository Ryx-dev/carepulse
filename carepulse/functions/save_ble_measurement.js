class SaveBleMeasurementError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function reject(status, message) {
  throw new SaveBleMeasurementError(status, message);
}

function validBody(body, now = Date.now()) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    reject(400, 'Invalid measurement.');
  }
  const allowed = ['requestId', 'deviceId', 'bpm', 'spo2', 'activity', 'note', 'scanDuration', 'timestamp'];
  if (Object.keys(body).some((key) => !allowed.includes(key))) {
    reject(400, 'Unexpected measurement field.');
  }
  const { requestId, deviceId, bpm, spo2, activity, note, scanDuration, timestamp } = body;
  if (typeof requestId !== 'string' || !/^[0-9A-F]{8}$/.test(requestId) ||
      typeof deviceId !== 'string' || !/^[A-Za-z0-9:_-]{1,128}$/.test(deviceId) ||
      !Number.isInteger(bpm) || bpm < 1 || bpm > 250 ||
      !Number.isInteger(spo2) || spo2 < 0 || spo2 > 100 ||
      typeof activity !== 'string' || activity.trim().length < 1 || activity.length > 40 ||
      typeof note !== 'string' || note.length > 100 ||
      !Number.isInteger(scanDuration) || scanDuration < 1 || scanDuration > 20 ||
      !Number.isSafeInteger(timestamp) || timestamp < 1577836800000 ||
      timestamp > now + 300000) {
    reject(400, 'Invalid measurement.');
  }
  return { requestId, deviceId, bpm, spo2, activity: activity.trim(), note,
    scanDuration, timestamp };
}

function sameMeasurement(existing, measurement) {
  return existing && typeof existing === 'object' &&
    Object.entries(measurement).every(([key, value]) => existing[key] === value);
}

function createSaveBleMeasurement({ database, verifyToken, clock = Date.now }) {
  return async ({ authorization, body }) => {
    const match = typeof authorization === 'string' &&
      /^Bearer (\S+)$/.exec(authorization);
    if (!match) reject(401, 'Sign in to save a measurement.');
    let decoded;
    try {
      decoded = await verifyToken(match[1]);
    } catch (_) {
      reject(401, 'Sign in again to save a measurement.');
    }
    if (typeof decoded?.uid !== 'string' || !decoded.uid) {
      reject(401, 'Sign in again to save a measurement.');
    }
    const measurement = validBody(body, clock());
    const ref = database.ref(`users/${decoded.uid}/measurements/${measurement.requestId}`);
    const record = { ...measurement, uploadedAt: clock() };
    const result = await ref.transaction((current) =>
      current === null ? record : undefined, undefined, false);
    if (result.committed) {
      return { requestId: measurement.requestId, timestamp: record.timestamp };
    }
    const existing = result.snapshot.val();
    if (sameMeasurement(existing, measurement)) {
      return { requestId: measurement.requestId, timestamp: existing.timestamp };
    }
    reject(409, 'This scan ID already belongs to a different measurement.');
  };
}

module.exports = { createSaveBleMeasurement, SaveBleMeasurementError, validBody };
