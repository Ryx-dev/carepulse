const { test } = require('node:test');
const assert = require('node:assert/strict');
const { SerialGateway, serialFields } = require('./gateway.cjs');

test('serial gateway claims once and reports an early sketch result', async () => {
  const requests = [];
  const sent = [];
  let now = 1_800_000_000_000;
  let command = { action: 'start_scan', requestId: 'request_1' };
  const gateway = new SerialGateway({
    clock: () => now,
    sendScan: async (requestId) => sent.push(`SCAN ${requestId}\n`),
    exchange: async (action, fields) => {
      requests.push({ action, ...fields });
      if (action === 'poll') {
        const result = { command };
        command = null;
        return result;
      }
      return { ok: true };
    },
  });
  gateway.onLine('state=ready command=SCAN');
  await gateway.tick();
  assert.deepEqual(sent, ['SCAN request_1\n']);
  assert.deepEqual(requests.map((request) => request.action), ['heartbeat', 'poll']);
  await gateway.tick();
  assert.equal(requests.filter((request) => request.action === 'poll').length, 1);
  gateway.onLine('state=complete requestId=old_scan bpm=78 spo2=98 durationSeconds=6 sample_rate=25.00');
  assert.equal(gateway.pendingReport, null);
  gateway.onLine('state=complete requestId=request_1 bpm=78 spo2=98 durationSeconds=6 sample_rate=25.00');
  gateway.onLine('state=ready command=SCAN');
  await gateway.tick();
  assert.deepEqual(requests.at(-1), {
    action: 'report', requestId: 'request_1', status: 'complete',
    bpm: 78, spo2: 98, scanDuration: 6,
  });
  now += 20_000;
  await gateway.tick();
  assert.equal(requests.at(-2).action, 'heartbeat');
  assert.equal(requests.at(-1).action, 'poll');
});

test('invalid and stale serial output never creates a successful measurement', async () => {
  assert.equal(serialFields('state=complete bpm=78 spo2=98 durationSeconds=6 sample_rate=25.00').bpm, '78');
  assert.equal(serialFields('state=complete bpm=78 bad value'), null);
  const requests = [];
  let now = 1_800_000_000_000;
  const gateway = new SerialGateway({
    clock: () => now,
    sendScan: async () => {},
    exchange: async (action, fields) => {
      requests.push({ action, ...fields });
      return action === 'poll'
        ? { command: { action: 'start_scan', requestId: 'request_2' } }
        : { ok: true };
    },
  });
  gateway.onLine('state=ready command=SCAN');
  await gateway.tick();
  gateway.onLine('state=invalid_scan requestId=request_2 reason=finger_removed');
  await gateway.tick();
  assert.deepEqual(requests.at(-1), {
    action: 'report', requestId: 'request_2', status: 'invalid', reason: 'finger_removed',
  });
  now += 20_000;
  await gateway.tick();
  now += 46_000;
  await gateway.tick();
  assert.deepEqual(requests.at(-1), {
    action: 'report', requestId: 'request_2', status: 'error', reason: 'sensor_timeout',
  });
});
