import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/device.dart';
import '../models/measurement.dart';
import '../services/mock_data_service.dart';
import '../services/firebase_data_repository.dart';
import '../services/ble_measurement_sync.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label;
  final String value;
  final String unit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: slate)),
      const SizedBox(height: 6),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 4,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: slate,
              fontWeight: FontWeight.bold,
            ),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(unit)),
        ],
      ),
    ],
  );
}

class MeasurementRow extends StatelessWidget {
  const MeasurementRow({
    super.key,
    required this.measurement,
    required this.onTap,
  });
  final Measurement measurement;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      hoverColor: mutedGray.withValues(alpha: 0.35),
      splashColor: coral.withValues(alpha: 0.12),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        measurement.activity,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${shortDateLabel(measurement.timestamp)} · ${timeLabel(measurement.timestamp)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${measurement.bpm} BPM',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: deepSlate,
                ),
              ),
              Text(
                '${measurement.spo2}% SpO₂',
                style: const TextStyle(fontSize: 12, color: slate),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 18, color: slate),
        ],
      ),
    ),
  );
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.data});
  final MockDataService data;
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    widget.data.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.data.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.data.stage;
    final title = switch (stage) {
      ScanStage.ready => 'Device ready',
      ScanStage.requestingScan => 'Requesting scan...',
      ScanStage.waitingForFinger => 'Waiting for finger...',
      ScanStage.scanning => 'Scanning...',
      ScanStage.processing => 'Processing measurement...',
      ScanStage.uploading => 'Saving demo result...',
      ScanStage.complete => 'Scan complete',
      ScanStage.invalidScan => 'Measurement could not be completed',
      ScanStage.error => 'Scan error',
      ScanStage.offline => 'Device offline',
    };
    final instruction = switch (stage) {
      ScanStage.waitingForFinger =>
        'Place your fingertip firmly on the MAX30102.',
      ScanStage.scanning => 'Keep your finger still.',
      ScanStage.invalidScan =>
        'Keep your finger on the sensor for the full scan and try again.',
      ScanStage.offline =>
        'Connect the device to Wi-Fi before starting a scan.',
      ScanStage.complete =>
        'This is a fixed demo result, not a sensor reading.',
      _ => 'This scan is simulated in demo mode.',
    };
    final scanning = stage == ScanStage.scanning;
    final complete = stage == ScanStage.complete;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      size: 66,
                      color: primaryRed,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(instruction, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (scanning) ...[
                      LinearProgressIndicator(
                        value:
                            (MockDataService.scanDurationSeconds -
                                widget.data.secondsRemaining) /
                            MockDataService.scanDurationSeconds,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${widget.data.secondsRemaining} seconds remaining',
                        textAlign: TextAlign.center,
                      ),
                    ] else if (!complete &&
                        stage != ScanStage.invalidScan &&
                        stage != ScanStage.error &&
                        stage != ScanStage.offline)
                      const Center(child: CircularProgressIndicator())
                    else if (complete && widget.data.latest != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: MetricTile(
                              label: 'Heart rate',
                              value: widget.data.latest!.bpm.toString(),
                              unit: 'BPM',
                            ),
                          ),
                          Expanded(
                            child: MetricTile(
                              label: 'Blood oxygen',
                              value: widget.data.latest!.spo2.toString(),
                              unit: '% SpO₂',
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (complete ||
                        stage == ScanStage.invalidScan ||
                        stage == ScanStage.error)
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back to home'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.data, required this.onDetails});
  final MockDataService data;
  final ValueChanged<Measurement> onDetails;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Measurement history',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      const Text(
        'Saved demo scans, newest first',
        style: TextStyle(color: slate),
      ),
      const SizedBox(height: 18),
      if (data.measurements.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('No measurements yet. Start a scan from Home.'),
          ),
        )
      else
        ...data.measurements.map(
          (measurement) => MeasurementRow(
            measurement: measurement,
            onTap: () => onDetails(measurement),
          ),
        ),
    ],
  );
}

class LiveHistoryScreen extends StatefulWidget {
  const LiveHistoryScreen({
    super.key,
    required this.uid,
    required this.sync,
    required this.onDetails,
  });
  final String uid;
  final BleMeasurementSync sync;
  final ValueChanged<Measurement> onDetails;

  @override
  State<LiveHistoryScreen> createState() => _LiveHistoryScreenState();
}

class _LiveHistoryScreenState extends State<LiveHistoryScreen> {
  late Stream<List<Measurement>> measurements;

  @override
  void initState() {
    super.initState();
    measurements = FirebaseDataRepository().watchCachedMeasurements(widget.uid);
  }

  @override
  void didUpdateWidget(LiveHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      measurements = FirebaseDataRepository().watchCachedMeasurements(
        widget.uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.sync,
    builder: (context, _) => StreamBuilder<List<Measurement>>(
      stream: measurements,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Measurement history',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Live scans saved to your account',
            style: TextStyle(color: slate),
          ),
          const SizedBox(height: 18),
          if (widget.sync.pending.isNotEmpty) ...[
            Text(
              'Saved on this phone · waiting to upload',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...widget.sync.pending.map(
              (measurement) => MeasurementRow(
                measurement: measurement,
                onTap: () => widget.onDetails(measurement),
              ),
            ),
            TextButton.icon(
              onPressed: widget.sync.isSyncing
                  ? null
                  : () => widget.sync.retry(),
              icon: const Icon(Icons.sync),
              label: const Text('Retry upload'),
            ),
            const SizedBox(height: 12),
          ],
          if (snapshot.hasError)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Could not load history. Check your connection and try again.',
                ),
              ),
            )
          else if (!snapshot.hasData)
            const Center(child: CircularProgressIndicator())
          else if (snapshot.data!
              .where((item) => !widget.sync.contains(item.requestId))
              .isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No live scans saved yet.'),
              ),
            )
          else
            ...snapshot.data!
                .where((item) => !widget.sync.contains(item.requestId))
                .map(
                  (measurement) => MeasurementRow(
                    measurement: measurement,
                    onTap: () => widget.onDetails(measurement),
                  ),
                ),
        ],
      ),
    ),
  );
}

class MeasurementDetailsScreen extends StatelessWidget {
  const MeasurementDetailsScreen({
    super.key,
    required this.measurement,
    this.demo = true,
  });
  final Measurement measurement;
  final bool demo;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Measurement details')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          demo ? 'DEMO DATA' : 'LIVE DEVICE RESULT',
          style: const TextStyle(
            color: primaryRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Average heart rate',
                    value: measurement.bpm.toString(),
                    unit: 'BPM',
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    label: 'Blood oxygen',
                    value: measurement.spo2.toString(),
                    unit: '% SpO₂',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              detail('Activity', measurement.activity),
              detail(
                'Note',
                measurement.note.isEmpty ? 'No note' : measurement.note,
              ),
              detail('Date', dateLabel(measurement.timestamp)),
              detail('Time', timeLabel(measurement.timestamp)),
              detail(
                'Scan duration',
                '${measurement.scanDurationSeconds} seconds',
              ),
              detail('Device', measurement.deviceId),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'For personal monitoring and logging only. Not a medical diagnosis.',
          style: TextStyle(color: slate),
        ),
      ],
    ),
  );
}

Widget detail(String label, String value) => ListTile(
  title: Text(label, style: const TextStyle(color: slate)),
  trailing: SizedBox(
    width: 170,
    child: Text(
      value,
      textAlign: TextAlign.end,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),
);

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.device});
  final CarePulseDevice device;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Device',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      const Text('Demo device status', style: TextStyle(color: slate)),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sensors, size: 40, color: primaryRed),
              const SizedBox(height: 10),
              Text(
                device.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(device.id, style: const TextStyle(color: slate)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            detail('Status', device.online ? 'Online' : 'Offline'),
            detail('State', device.state),
            detail('Sensor', device.sensorStatus),
            detail(
              'Last seen',
              device.lastSeen == null
                  ? 'Unavailable'
                  : '${dateLabel(device.lastSeen!)} · ${timeLabel(device.lastSeen!)}',
            ),
            detail('Connection', 'Simulated'),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Status is simulated. No ESP32 or Firebase connection is active.',
        style: TextStyle(color: slate),
      ),
    ],
  );
}

class LiveDeviceScreen extends StatelessWidget {
  const LiveDeviceScreen({super.key, required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'CarePulse device',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'The app connects to your nearby ESP32 over Bluetooth for each scan.',
        style: TextStyle(color: slate),
      ),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.bluetooth_rounded, size: 42, color: primaryRed),
              const SizedBox(height: 14),
              const Text('Keep CarePulse powered on and close to your phone.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onConnect,
                child: const Text('Connect and scan'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
