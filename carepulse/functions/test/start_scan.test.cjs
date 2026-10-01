const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { createStartScan, ScanRequestError } = require('../scan_request');

const NOW = 1_800_000_000_000;

function readyDevice(overrides = {}) {
  return {
    name: 'CarePulse', online: true, state: 'ready',
    sensorStatus: 'ok', lastSeen: NOW - 1000, ...overrides,
  };
}

test('startScan authorizes an owner and atomically creates one command', async (t) => {
  assert.ok(process.env.FIREBASE_DATABASE_EMULATOR_HOST, 'Run through the database emulator');
  const app = initializeApp({
    projectId: 'demo-carepulse-functions',
    databaseURL: 'https://demo-carepulse-functions-default-rtdb.firebaseio.com',
  }, 'scan-test');
  t.after(() => deleteApp(app));
  const database = getDatabase(app);
  await database.ref().set(null);
  await database.ref('users/alice/devices/device_1').set(readyDevice());
  await database.ref('users/bob/devices/device_1').set(readyDevice({ online: false }));
  assert.deepEqual((await database.ref('users/alice/devices/device_1').get()).val(), readyDevice());

  let sequence = 0;
  const startScan = createStartScan({
    database, clock: () => NOW, newRequestId: () => `request_${++sequence}`,
  });
  const alice = { auth: { uid: 'alice' }, data: { deviceId: 'device_1', activity: 'Resting', note: 'Morning' } };
  const [first, second] = await Promise.allSettled([startScan(alice), startScan(alice)]);
  const outcomes = [first, second];
  assert.equal(outcomes.filter((outcome) => outcome.status === 'fulfilled').length, 1,
    outcomes.map((outcome) => outcome.status === 'rejected' ? String(outcome.reason?.stack) : outcome.value).join('\n'));
  assert.equal(outcomes.filter((outcome) => outcome.status === 'rejected').length, 1);
  const result = outcomes.find((outcome) => outcome.status === 'fulfilled').value;
  const refusal = outcomes.find((outcome) => outcome.status === 'rejected').reason;
  assert.equal(refusal.code, 'failed-precondition');
  const saved = (await database.ref('users/alice/devices/device_1').get()).val();
  assert.deepEqual(saved.command, {
    action: 'start_scan', requestId: result.requestId,
    activity: 'Resting', note: 'Morning', createdAt: NOW, status: 'pending',
  });
  assert.equal(saved.name, 'CarePulse');

  await assert.rejects(startScan({ ...alice, auth: { uid: 'bob' } }), { code: 'failed-precondition' });
  assert.equal((await database.ref('users/bob/devices/device_1/command').get()).exists(), false);
  await assert.rejects(startScan({ ...alice, auth: null }), { code: 'unauthenticated' });
  await assert.rejects(startScan({ ...alice, data: { ...alice.data, deviceId: '../bob' } }), { code: 'invalid-argument' });
  await assert.rejects(startScan({ ...alice, data: { ...alice.data, note: 'x'.repeat(101) } }), { code: 'invalid-argument' });

  await database.ref('users/alice/devices/device_1').set(readyDevice({ lastSeen: NOW - 60_001 }));
  await assert.rejects(startScan(alice), { code: 'failed-precondition' });
  await database.ref('users/alice/devices/device_1').set(readyDevice({ lastSeen: NOW + 5001 }));
  await assert.rejects(startScan(alice), { code: 'failed-precondition' });
  await database.ref('users/alice/devices/device_1').set(readyDevice({ state: 'scanning' }));
  await assert.rejects(startScan(alice), { code: 'failed-precondition' });
  await database.ref('users/alice/devices/device_1').set(readyDevice({
    command: { status: 'complete', requestId: result.requestId },
  }));
  const next = await startScan(alice);
  assert.notEqual(next.requestId, result.requestId);
  assert.equal((await database.ref('users/alice/devices/device_1/command/status').get()).val(), 'pending');
});
