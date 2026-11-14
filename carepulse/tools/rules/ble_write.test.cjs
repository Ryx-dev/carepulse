const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

test('BLE measurement writes are owner scoped and validated', async (t) => {
  const rules = fs.readFileSync(
    path.resolve(__dirname, '../../database.rules.json'),
    'utf8',
  );
  const env = await initializeTestEnvironment({
    projectId: 'demo-carepulse-ble',
    database: {
      host: '127.0.0.1',
      port: 19000,
      rules,
    },
  });
  t.after(() => env.cleanup());

  const alice = env.authenticatedContext('alice').database();
  const bob = env.authenticatedContext('bob').database();
  const guest = env.unauthenticatedContext().database();
  const ref = alice.ref('users/alice/measurements/A1B2C3D4');
  const result = {
    requestId: 'A1B2C3D4', deviceId: 'carepulse_1', bpm: 78, spo2: 98,
    activity: 'Resting', note: '', scanDuration: 150,
    timestamp: Date.now() - 1000,
  };

  await assertSucceeds(ref.set(result));
  const saved = await assertSucceeds(ref.once('value'));
  assert.equal(saved.child('bpm').val(), 78);
  await assertSucceeds(ref.set(result)); // Retry after an uncertain acknowledgment.
  await assertFails(ref.set({ ...result, bpm: 79 }));
  await assertFails(ref.update({ note: 'Changed after upload' }));
  await assertFails(bob.ref('users/alice/measurements/A1B2C3D4').set(result));
  await assertFails(guest.ref('users/alice/measurements/BBBBBBBB').set({
    ...result, requestId: 'BBBBBBBB',
  }));
  await assertFails(alice.ref('users/bob/measurements/A1B2C3D4').set(result));
  await assertFails(alice.ref('users/alice/measurements/AAAAAAAA').set({
    ...result, requestId: 'A1B2C3D4',
  }));
  await assertFails(alice.ref('users/alice/measurements/BBBBBBBB').set({
    ...result, requestId: 'BBBBBBBB', bpm: 300,
  }));
  await assertFails(alice.ref('users/alice/measurements/CCCCCCCC').set({
    ...result, requestId: 'CCCCCCCC', extra: 'unexpected',
  }));
  await assertFails(ref.remove());
});
