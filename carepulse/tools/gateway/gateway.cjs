const TERMINAL = new Set(['complete', 'invalid_scan', 'error']);

function serialFields(line) {
  if (typeof line !== 'string' || line.length > 256) return null;
  const fields = {};
  for (const part of line.trim().split(/\s+/)) {
    const match = /^([A-Za-z][A-Za-z0-9_]*)=([A-Za-z0-9_.-]+)$/.exec(part);
    if (!match) return null;
    fields[match[1]] = match[2];
  }
  return fields.state ? fields : null;
}

class SerialGateway {
  constructor({ exchange, sendScan, clock = Date.now }) {
    this.exchange = exchange;
    this.sendScan = sendScan;
    this.clock = clock;
    this.ready = false;
    this.sensorStatus = 'error';
    this.lastHeartbeat = 0;
    this.activeRequestId = null;
    this.startedAt = 0;
    this.pendingReport = null;
    this.busy = false;
  }

  onLine(line) {
    const fields = serialFields(line);
    if (!fields) return;
    if (fields.state === 'ready') {
      this.ready = true;
      this.sensorStatus = 'connected';
    } else if (fields.state === 'error') {
      this.ready = false;
      this.sensorStatus = 'error';
    }
    if (!this.activeRequestId || this.pendingReport || !TERMINAL.has(fields.state) ||
        fields.requestId !== this.activeRequestId) return;
    const requestId = this.activeRequestId;
    if (fields.state === 'complete') {
      const bpm = Number(fields.bpm);
      const spo2 = Number(fields.spo2);
      const scanDuration = Number(fields.durationSeconds);
      if (Number.isInteger(bpm) && bpm >= 1 && bpm <= 250 &&
          Number.isInteger(spo2) && spo2 >= 0 && spo2 <= 100 &&
          Number.isInteger(scanDuration) && scanDuration >= 1 && scanDuration <= 10) {
        this.pendingReport = { requestId, status: 'complete', bpm, spo2, scanDuration };
      }
    } else if (fields.state === 'invalid_scan') {
      this.pendingReport = { requestId, status: 'invalid', reason: fields.reason };
    } else if (fields.state === 'error') {
      this.pendingReport = { requestId, status: 'error', reason: fields.reason };
    }
  }

  disconnected() {
    this.ready = false;
    this.sensorStatus = 'error';
  }

  async tick() {
    if (this.busy) return;
    this.busy = true;
    try {
      if (this.ready && this.clock() - this.lastHeartbeat >= 20_000) {
        await this.exchange('heartbeat', { sensorStatus: this.sensorStatus });
        this.lastHeartbeat = this.clock();
      }
      if (this.activeRequestId && !this.pendingReport &&
          this.clock() - this.startedAt > 45_000) {
        this.pendingReport = {
          requestId: this.activeRequestId, status: 'error', reason: 'sensor_timeout',
        };
      }
      if (this.pendingReport) {
        await this.exchange('report', this.pendingReport);
        this.pendingReport = null;
        this.activeRequestId = null;
        return;
      }
      if (!this.ready || this.activeRequestId) return;
      const response = await this.exchange('poll');
      if (response.command?.action !== 'start_scan') return;
      this.activeRequestId = response.command.requestId;
      this.startedAt = this.clock();
      try {
        await this.sendScan(this.activeRequestId);
      } catch (_) {
        this.pendingReport = {
          requestId: this.activeRequestId, status: 'error', reason: 'sensor_timeout',
        };
      }
    } finally {
      this.busy = false;
    }
  }
}

module.exports = { SerialGateway, serialFields };
