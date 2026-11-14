// Independent Node/OpenSSL reference for the Dart and ESP32 protocol tests.
// Every key and nonce here is a public test fixture, never a device credential.
const { createHmac, createCipheriv } = require('node:crypto');
const key = Buffer.from(Array.from({ length: 16 }, (_, i) => i));
const clientNonce = Buffer.from(Array.from({ length: 16 }, (_, i) => i + 16));
const deviceNonce = Buffer.from(Array.from({ length: 16 }, (_, i) => i + 32));
function packet(direction, text, counter) {
  const label = Buffer.from(`CarePulse/v2/${direction}`);
  const sessionKey = createHmac('sha256', key)
    .update(Buffer.concat([label, clientNonce, deviceNonce])).digest().subarray(0, 16);
  const nonce = Buffer.alloc(12);
  nonce.writeUInt32BE(counter, 8);
  const cipher = createCipheriv('aes-128-gcm', sessionKey, nonce);
  cipher.setAAD(label);
  const ciphertext = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  const prefix = Buffer.alloc(4);
  prefix.writeUInt32BE(counter);
  return Buffer.concat([prefix, ciphertext, cipher.getAuthTag()]).toString('hex').toUpperCase();
}
process.stdout.write(JSON.stringify({
  pairingCode: key.toString('hex').toUpperCase(),
  clientNonce: clientNonce.toString('hex').toUpperCase(),
  deviceNonce: deviceNonce.toString('hex').toUpperCase(),
  clientProof: packet('c2d', 'P', 0),
  deviceProof: packet('d2c', 'T', 0),
  scan: packet('c2d', 'S|A1B2C3D4', 1),
  complete: packet('d2c', 'C|A1B2C3D4|78|98', 1),
}, null, 2) + '\n');
