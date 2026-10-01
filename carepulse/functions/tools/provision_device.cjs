const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { provisionDevice } = require('../provision_device');

async function main() {
  const [uid, deviceId, ...nameParts] = process.argv.slice(2);
  const databaseURL = process.env.CAREPULSE_DATABASE_URL;
  if (!databaseURL || !uid || !deviceId || !nameParts.length) {
    throw new Error('Usage: CAREPULSE_DATABASE_URL=<url> node tools/provision_device.cjs <uid> <deviceId> <device name>');
  }
  const app = initializeApp({ databaseURL });
  try {
    const result = await provisionDevice({
      database: getDatabase(app), uid, deviceId, name: nameParts.join(' '),
    });
    process.stdout.write(`Device ${result.deviceId} bound to UID ${result.uid}.\n`);
    process.stdout.write(`DEVICE_TOKEN=${result.token}\n`);
    process.stdout.write('Save the token securely now; only its hash is stored in the database.\n');
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
