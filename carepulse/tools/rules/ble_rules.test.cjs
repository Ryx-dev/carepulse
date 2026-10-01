const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails, assertSucceeds, initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

test('signed-in owner can upload validated scans and other access is denied', async (t) => {
  const rules = fs.readFileSync(path.resolve(__dirname, '../../database.rules.json'), 'utf8');
  const env = await initializeTestEnvironment({
    projectId: 'demo-carepulse-rules',
    database: { host: '127.0.0.1', port: 9000, rules },
  });
  t.after(() => env.cleanup());
  const alice = env.authenticatedContext('alice').database();
  const bob = env.authenticatedContext('bob').database();
  const guest = env.unauthenticatedContext().database();
  const location = 'users/alice/measurements/A1B2C3D4';
  const scan = {
    requestId: 'A1B2C3D4', deviceId: 'AA:BB:CC:DD:EE:FF',
    bpm: 78, spo2: 98, activity: 'Resting', note: '',
    scanDuration: 6, timestamp: Date.now() - 3600000,
  };

  await assertSucceeds(alice.ref(location).set(scan));
  await assertSucceeds(alice.ref(location).set(scan));
  const saved = await assertSucceeds(alice.ref(location).once('value'));
  assert.deepEqual(saved.val(), scan);
  await assertFails(bob.ref(location).set(scan));
  await assertFails(guest.ref(location).set(scan));
  await assertFails(bob.ref(location).once('value'));
  await assertFails(alice.ref(location).remove());
  await assertFails(alice.ref('users/alice/profile').set({ name: 'changed' }));
  await assertFails(alice.ref('users/alice/devices/device_1').set({ online: true }));
  await assertFails(alice.ref('users/alice/measurements/B1B2C3D4').set(scan));
  await assertFails(alice.ref('users/alice/measurements/C1B2C3D4').set({
    ...scan, requestId: 'C1B2C3D4', bpm: 400,
  }));
  await assertFails(alice.ref('users/alice/measurements/D1B2C3D4').set({
    ...scan, requestId: 'D1B2C3D4', extra: true,
  }));
});
