const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

test('Phase 5 candidate allows only owner reads and no client writes', async (t) => {
  const rules = fs.readFileSync(
    path.resolve(__dirname, '../../database.phase5-candidate.rules.json'),
    'utf8',
  );
  const env = await initializeTestEnvironment({
    projectId: 'demo-carepulse-rules',
    database: { host: '127.0.0.1', port: 9000, rules },
  });
  t.after(() => env.cleanup());

  await env.withSecurityRulesDisabled(async (context) => {
    await context.database().ref('deviceBindings/device_1').set({
      uid: 'alice', tokenHash: 'emulator-only-hash',
    });
    await context.database().ref('users/alice').set({
      profile: { name: 'Alice' },
      devices: { carepulse_001: { name: 'CarePulse Device', state: 'ready' } },
      measurements: { scan_1: { bpm: 78, spo2: 98 } },
      private: { pairingSecret: 'emulator-only' },
    });
    await context.database().ref('users/bob/profile').set({ name: 'Bob' });
  });

  const alice = env.authenticatedContext('alice').database();
  const bob = env.authenticatedContext('bob').database();
  const guest = env.unauthenticatedContext().database();

  const ownProfile = await assertSucceeds(alice.ref('users/alice/profile').once('value'));
  assert.equal(ownProfile.child('name').val(), 'Alice');
  await assertSucceeds(alice.ref('users/alice/devices/carepulse_001').once('value'));
  await assertSucceeds(alice.ref('users/alice/measurements').once('value'));
  await assertSucceeds(bob.ref('users/bob/profile').once('value'));

  await assertFails(alice.ref('users/bob/profile').once('value'));
  await assertFails(bob.ref('users/alice/measurements').once('value'));
  await assertFails(guest.ref('users/alice/profile').once('value'));
  await assertFails(alice.ref('users/alice').once('value'));
  await assertFails(alice.ref('users/alice/private').once('value'));
  await assertFails(alice.ref('users').once('value'));
  await assertFails(alice.ref('deviceBindings/device_1').once('value'));
  await assertFails(guest.ref('deviceBindings/device_1').once('value'));

  await assertFails(alice.ref('users/alice/profile/name').set('Changed'));
  await assertFails(alice.ref('users/alice/measurements/scan_2').set({ bpm: 99 }));
  await assertFails(alice.ref('users/alice/devices/carepulse_001/command').set({ action: 'start_scan' }));
  await assertFails(alice.ref('users/alice').set({ profile: { name: 'Changed' } }));
  await assertFails(alice.ref('users/bob/profile/name').set('Changed'));
  await assertFails(guest.ref('users/alice/profile/name').set('Changed'));
});
