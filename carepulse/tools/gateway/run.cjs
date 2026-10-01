const { SerialGateway } = require('./gateway.cjs');

const endpoint = process.env.CAREPULSE_DEVICE_URL;
const deviceId = process.env.CAREPULSE_DEVICE_ID;
const token = process.env.CAREPULSE_DEVICE_TOKEN;
const portPath = process.env.CAREPULSE_SERIAL_PORT;

if (!endpoint || !deviceId || !token || !portPath) {
  throw new Error('Set CAREPULSE_DEVICE_URL, CAREPULSE_DEVICE_ID, CAREPULSE_DEVICE_TOKEN, and CAREPULSE_SERIAL_PORT.');
}
const url = new URL(endpoint);
if (url.protocol !== 'https:' &&
    !(url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname))) {
  throw new Error('Device exchange requires HTTPS outside localhost.');
}

const { SerialPort, ReadlineParser } = require('serialport');
const port = new SerialPort({ path: portPath, baudRate: 115200 });
const lines = port.pipe(new ReadlineParser({ delimiter: '\n' }));

async function exchange(action, fields = {}) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ deviceId, action, ...fields }),
    signal: AbortSignal.timeout(10_000),
  });
  const result = await response.json();
  if (!response.ok) throw new Error(`Device exchange ${action}: ${result.error || response.status}`);
  return result;
}

const gateway = new SerialGateway({
  exchange,
  sendScan: (requestId) => new Promise((resolve, reject) =>
    port.write(`SCAN ${requestId}\n`, (error) => error ? reject(error) : resolve())),
});

lines.on('data', (line) => gateway.onLine(line.trim()));
port.on('error', (error) => console.error('Serial port:', error.message));
port.on('close', () => {
  gateway.disconnected();
  exchange('offline').catch((error) => console.error('Offline update:', error.message));
  console.error('Serial port closed.');
});
setInterval(() => gateway.tick().catch((error) =>
  console.error('Gateway:', error.message)), 2000);
console.log(`CarePulse serial gateway listening on ${portPath} for ${deviceId}.`);
