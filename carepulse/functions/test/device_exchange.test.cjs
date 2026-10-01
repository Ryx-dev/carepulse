const { test } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { createDeviceExchange, sha256 } = require('../device_exchange');
const { provisionDevice } = require('../provision_device');
const { createStartScan } = require('../scan_request');

const NOW = 1_800_000_000_000;
const TOKEN = 'a'.repeat(43);
const WRONG_TOKEN = 'b'.repeat(43);

test('one device credential can heartbeat, claim, and report only its own scan', async (t) => {
  assert.ok(process.env.FIREBASE_DATABASE_EMULATOR_HOST, 'Run through the database emulator');
  const app = initializeApp({
    projectId: 'demo-carepulse-device',
    databaseURL: 'https://demo-carepulse-device-default-rtdb.firebaseio.com',
  }, 'device-test');
  t.after(() => deleteApp(app));
  const database = getDatabase(app);
  await database.ref().set(null);
  const provisioned = await provisionDevice({
    database, uid: 'alice', deviceId: 'device_1', name: 'CarePulse', newToken: () => TOKEN,
  });
  assert.equal(provisioned.token, TOKEN);
  assert.deepEqual((await database.ref('deviceBindings/device_1').get()).val(), {
    uid: 'alice', tokenHash: sha256(TOKEN),
  });
  await assert.rejects(provisionDevice({
    database, uid: 'bob', deviceId: 'device_1', name: 'Stolen', newToken: () => WRONG_TOKEN,
  }), /already bound/);
  await database.ref('users/alice/devices/device_2').set({ name: 'Existing' });
  await assert.rejects(provisionDevice({
    database, uid: 'alice', deviceId: 'device_2', name: 'Duplicate', newToken: () => WRONG_TOKEN,
  }), /record already exists/);
  assert.equal((await database.ref('deviceBindings/device_2').get()).exists(), false);
  await database.ref('users/bob/devices/device_1').set({
    name: 'Bob device', online: false, state: 'ready', sensorStatus: 'connected',
  });
  const exchange = createDeviceExchange({ database, clock: () => NOW });
  const call = (action, fields = {}, token = TOKEN) => exchange({
    authorization: `Bearer ${token}`, body: { deviceId: 'device_1', action, ...fields },
  });

  await assert.rejects(call('heartbeat', { sensorStatus: 'connected' }, WRONG_TOKEN), { status: 401 });
  await assert.rejects(call('heartbeat', { sensorStatus: 'unknown' }), { status: 400 });
  await assert.rejects(exchange({ authorization: `Bearer ${TOKEN}`, body: {
    deviceId: '../bob', action: 'heartbeat', sensorStatus: 'connected',
  } }), { status: 400 });
  assert.equal((await database.ref('users/bob/devices/device_1/lastSeen').get()).exists(), false);

  assert.deepEqual(await call('heartbeat', { sensorStatus: 'connected' }), { ok: true });
  assert.equal((await database.ref('users/alice/devices/device_1/lastSeen').get()).val(), NOW);
  assert.deepEqual(await call('poll'), { command: null });
  const startScan = createStartScan({
    database, clock: () => NOW, newRequestId: () => 'request_1',
  });
  await startScan({ auth: { uid: 'alice' }, data: {
    deviceId: 'device_1', activity: 'Resting', note: 'Morning',
  } });
  assert.deepEqual(await call('poll'), {
    command: { action: 'start_scan', requestId: 'request_1' },
  });
  assert.deepEqual(await call('poll'), { command: null });
  assert.equal((await database.ref('users/alice/devices/device_1/command/status').get()).val(), 'acknowledged');

  await assert.rejects(call('report', {
    requestId: 'wrong_id', status: 'complete', bpm: 78, spo2: 98, scanDuration: 6,
  }), { status: 409 });
  await assert.rejects(call('report', {
    requestId: 'request_1', status: 'complete', bpm: 78, spo2: 101, scanDuration: 6,
  }), { status: 400 });
  const valid = { requestId: 'request_1', status: 'complete', bpm: 78, spo2: 98, scanDuration: 6 };
  assert.deepEqual(await call('report', valid), { ok: true });
  assert.deepEqual(await call('report', valid), { ok: true });
  const measurement = (await database.ref('users/alice/measurements/request_1').get()).val();
  assert.deepEqual(measurement, {
    requestId: 'request_1', deviceId: 'device_1', bpm: 78, spo2: 98,
    activity: 'Resting', note: 'Morning', scanDuration: 6, timestamp: NOW,
  });
  assert.equal((await database.ref('users/alice/devices/device_1/command/status').get()).val(), 'complete');
  assert.equal((await database.ref('users/alice/devices/device_1/state').get()).val(), 'ready');
  assert.equal((await database.ref('users/bob/measurements').get()).exists(), false);

  await database.ref('users/alice/devices/device_1/command').set({
    action: 'start_scan', requestId: 'request_2', activity: 'Walking', note: '',
    status: 'acknowledged', createdAt: NOW,
  });
  assert.deepEqual(await call('report', {
    requestId: 'request_2', status: 'invalid', reason: 'finger_removed',
  }), { ok: true });
  assert.equal((await database.ref('users/alice/measurements/request_2').get()).exists(), false);
  assert.deepEqual(await call('offline'), { ok: true });
  assert.equal((await database.ref('users/alice/devices/device_1/online').get()).val(), false);
  assert.equal((await database.ref('users/alice/devices/device_1/state').get()).val(), 'offline');
});
