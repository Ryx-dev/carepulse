const { randomBytes } = require('node:crypto');
const { sha256 } = require('./device_exchange');

function provisionInput({ uid, deviceId, name }) {
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new Error('A valid Firebase Auth UID is required.');
  }
  if (typeof deviceId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(deviceId)) {
    throw new Error('A valid device ID is required.');
  }
  if (typeof name !== 'string' || !name.trim() || name.trim().length > 64) {
    throw new Error('A device name of 1–64 characters is required.');
  }
  return { uid, deviceId, name: name.trim() };
}

async function provisionDevice({ database, uid, deviceId, name,
  newToken = () => randomBytes(32).toString('base64url') }) {
  const input = provisionInput({ uid, deviceId, name });
  const token = newToken();
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new Error('Invalid generated token.');
  const tokenHash = sha256(token);
  const bindingRef = database.ref(`deviceBindings/${deviceId}`);
  const binding = await bindingRef.transaction((current) =>
    current === null ? { uid, tokenHash } : undefined, undefined, false);
  if (!binding.committed) throw new Error('Device ID is already bound.');
  const deviceRef = database.ref(`users/${uid}/devices/${deviceId}`);
  try {
    const device = await deviceRef.transaction((current) =>
      current === null ? {
        name: input.name, online: false, state: 'ready', sensorStatus: 'offline',
      } : undefined, undefined, false);
    if (!device.committed) throw new Error('Device record already exists.');
  } catch (error) {
    await bindingRef.transaction((current) =>
      current === null ||
      (current?.tokenHash === tokenHash && current?.uid === uid) ? null : undefined,
    undefined, false);
    throw error;
  }
  return { token, uid, deviceId };
}

module.exports = { provisionDevice };
