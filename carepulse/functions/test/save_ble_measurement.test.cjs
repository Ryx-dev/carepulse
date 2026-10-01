const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createSaveBleMeasurement } = require('../save_ble_measurement');

test('authenticated BLE result is saved once under its owner and retries are idempotent', async () => {
  const records = new Map();
  const paths = [];
  const database = { ref(path) {
    paths.push(path);
    return { async transaction(update) {
      const current = records.get(path) ?? null;
      const next = update(current);
      if (next !== undefined) records.set(path, next);
      return { committed: next !== undefined,
        snapshot: { val: () => records.get(path) ?? null } };
    } };
  } };
  const save = createSaveBleMeasurement({
    database, verifyToken: async (token) => token === 'alice-token'
      ? { uid: 'alice' } : Promise.reject(new Error('bad token')),
    clock: () => 1_800_000_000_000,
  });
  const request = { authorization: 'Bearer alice-token', body: {
    requestId: 'A1B2C3D4', deviceId: 'AA:BB:CC:DD:EE:FF', bpm: 78,
    spo2: 98, activity: 'Resting', note: 'Morning', scanDuration: 6,
    timestamp: 1_790_000_000_000,
  } };
  const expected = { requestId: 'A1B2C3D4', timestamp: 1_790_000_000_000 };
  assert.deepEqual(await save(request), expected);
  assert.deepEqual(await save(request), expected);
  assert.deepEqual(paths, Array(2).fill('users/alice/measurements/A1B2C3D4'));
  assert.deepEqual(records.get(paths[0]), { ...request.body, uploadedAt: 1_800_000_000_000 });
  await assert.rejects(save({ ...request, authorization: 'Bearer wrong' }), { status: 401 });
  await assert.rejects(save({ ...request, body: { ...request.body, spo2: 101 } }), { status: 400 });
  await assert.rejects(save({ ...request, body: { ...request.body, bpm: 79 } }), { status: 409 });
  assert.equal(records.size, 1);
});
