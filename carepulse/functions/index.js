const { initializeApp, getApps } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { getAuth } = require('firebase-admin/auth');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { createStartScan, ScanRequestError } = require('./scan_request');
const { createDeviceExchange, DeviceExchangeError } = require('./device_exchange');
const { createSaveBleMeasurement, SaveBleMeasurementError } = require('./save_ble_measurement');

function database() {
  const databaseURL = process.env.CAREPULSE_DATABASE_URL;
  if (!databaseURL) throw new Error('CAREPULSE_DATABASE_URL is required.');
  if (!getApps().length) initializeApp({ databaseURL });
  return getDatabase();
}

exports.startScan = onCall({ region: 'asia-southeast1' }, async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in to start a scan.');
  }
  try {
    return await createStartScan({ database: database() })(request);
  } catch (error) {
    if (error instanceof ScanRequestError) {
      throw new HttpsError(error.code, error.message);
    }
    throw error;
  }
});

exports.deviceExchange = onRequest({ region: 'asia-southeast1', cors: false }, async (req, res) => {
  res.set('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST required.' });
  try {
    const result = await createDeviceExchange({ database: database() })({
      authorization: req.headers.authorization, body: req.body,
    });
    return res.status(200).json(result);
  } catch (error) {
    if (error instanceof DeviceExchangeError) {
      return res.status(error.status).json({ error: error.message });
    }
    console.error('Device exchange failed:', error);
    return res.status(500).json({ error: 'Device exchange failed.' });
  }
});

exports.saveBleMeasurement = onRequest({ region: 'asia-southeast1', cors: false }, async (req, res) => {
  res.set('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST required.' });
  try {
    const result = await createSaveBleMeasurement({
      database: database(),
      verifyToken: (token) => getAuth().verifyIdToken(token),
    })({ authorization: req.headers.authorization, body: req.body });
    return res.status(200).json(result);
  } catch (error) {
    if (error instanceof SaveBleMeasurementError) {
      return res.status(error.status).json({ error: error.message });
    }
    console.error('BLE measurement save failed:', error);
    return res.status(500).json({ error: 'Could not save measurement.' });
  }
});
