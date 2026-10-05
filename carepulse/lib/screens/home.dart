import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/measurement.dart';
import '../services/mock_data_service.dart';
import '../services/auth_service.dart';
import '../services/firebase_data_repository.dart';
import '../services/ble_measurement_sync.dart';
import 'pages.dart';
import 'profile.dart';
import 'live_ble_scan.dart';

/// Displays one demo session using data owned by its parent.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.name,
    required this.email,
    this.uid,
    this.sync,
    required this.data,
    this.onSignOut,
  });
  final String name;
  final String email;
  final String? uid;
  final BleMeasurementSync? sync;
  final MockDataService data;
  final Future<void> Function()? onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final customContext = TextEditingController();
  final note = TextEditingController();
  String contextName = 'Resting';
  int tab = 0;
  bool signingOut = false;
  StreamSubscription<List<Measurement>>? _liveSubscription;
  List<Measurement> _liveMeasurements = const [];
  bool _historyError = false;
  MockDataService get data => widget.data;
  bool get supportsLiveScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get scanInProgress => switch (data.stage) {
    ScanStage.requestingScan ||
    ScanStage.waitingForFinger ||
    ScanStage.scanning ||
    ScanStage.processing ||
    ScanStage.uploading => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    data.addListener(refresh);
    widget.sync?.addListener(refresh);
    _listenToHistory();
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != data) {
      oldWidget.data.removeListener(refresh);
      data.addListener(refresh);
    }
    if (oldWidget.sync != widget.sync) {
      oldWidget.sync?.removeListener(refresh);
      widget.sync?.addListener(refresh);
    }
    if (oldWidget.uid != widget.uid) {
      unawaited(_liveSubscription?.cancel());
      _liveSubscription = null;
      _liveMeasurements = const [];
      _historyError = false;
      _listenToHistory();
    }
  }

  void _listenToHistory() {
    final uid = widget.uid;
    if (uid == null) return;
    _liveSubscription = FirebaseDataRepository()
        .watchCachedMeasurements(uid)
        .listen(
          (measurements) {
            if (!mounted || widget.uid != uid) return;
            setState(() {
              _liveMeasurements = measurements;
              _historyError = false;
            });
          },
          onError: (Object _) {
            if (!mounted || widget.uid != uid) return;
            setState(() => _historyError = true);
          },
        );
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    data.removeListener(refresh);
    widget.sync?.removeListener(refresh);
    unawaited(_liveSubscription?.cancel());
    customContext.dispose();
    note.dispose();
    super.dispose();
  }

  void openScan() {
    if (!data.canScan) return;
    final activity =
        contextName == 'Other' && customContext.text.trim().isNotEmpty
        ? customContext.text.trim()
        : contextName;
    data.startScan(activity: activity, note: note.text);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ScanScreen(data: data)));
  }

  void openDetails(Measurement measurement, {bool demo = true}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MeasurementDetailsScreen(measurement: measurement, demo: demo),
      ),
    );
  }

  void openLiveScan() {
    final activity =
        contextName == 'Other' && customContext.text.trim().isNotEmpty
        ? customContext.text.trim()
        : contextName;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveBleScanScreen(
          activity: activity,
          note: note.text.trim(),
          sync: widget.sync!,
        ),
      ),
    );
  }

  Future<void> signOut() async {
    if (signingOut || widget.onSignOut == null) return;
    setState(() => signingOut = true);
    try {
      await widget.onSignOut!();
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(failure))));
      }
    } finally {
      if (mounted) setState(() => signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 64,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image(
            image: AssetImage(appMarkAsset),
            width: 28,
            height: 28,
            fit: BoxFit.contain,
            semanticLabel: 'CarePulse logo',
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'CarePulse',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: primaryRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: primaryRed.withValues(alpha: 0.12)),
          ),
          child: Text(
            widget.uid == null ? 'DEMO DATA' : 'LIVE SCAN',
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 0.4,
              color: slate,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Profile',
          onPressed: () => setState(() => tab = 3),
          icon: const Icon(Icons.person_outline_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: switch (tab) {
      0 =>
        widget.uid == null
            ? homePage(context)
            : homePage(
                context,
                measurements: _liveMeasurements,
                historyError: _historyError,
              ),
      1 =>
        widget.uid == null
            ? HistoryScreen(data: data, onDetails: openDetails)
            : LiveHistoryScreen(
                uid: widget.uid!,
                sync: widget.sync!,
                onDetails: (measurement) =>
                    openDetails(measurement, demo: false),
              ),
      2 =>
        widget.uid == null
            ? DeviceScreen(device: data.device)
            : LiveDeviceScreen(
                onConnect: openLiveScan,
                scanningAvailable: supportsLiveScan,
              ),
      _ => ProfileScreen(
        name: widget.name,
        email: widget.email,
        onSignOut: signOut,
        signingOut: signingOut,
      ),
    },
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (value) => setState(() => tab = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        NavigationDestination(
          icon: Icon(Icons.sensors_outlined),
          label: 'Device',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    ),
  );

  Widget homePage(
    BuildContext context, {
    List<Measurement>? measurements,
    bool historyError = false,
  }) {
    final visibleMeasurements = widget.uid == null
        ? data.measurements
        : (<Measurement>[
            ...widget.sync!.pending,
            ...(measurements ?? const <Measurement>[]).where(
              (item) => !widget.sync!.contains(item.requestId),
            ),
          ]..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
    final latest = visibleMeasurements.isEmpty
        ? null
        : visibleMeasurements.first;
    final latestDate = latest == null ? '' : dateLabel(latest.timestamp);
    final latestTime = latest == null ? '' : timeLabel(latest.timestamp);
    final state = data.device.state.replaceAll('_', ' ');
    final stateLabel = state.isEmpty
        ? 'Unknown'
        : state.replaceRange(0, 1, state[0].toUpperCase());

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          key: const ValueKey('dashboard_content'),
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            children: [
              Text(
                'Your overview',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: deepSlate,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.uid == null
                    ? 'Demo readings at a glance'
                    : 'Your saved CarePulse readings',
                style: const TextStyle(fontSize: 14, color: slate),
              ),
              const SizedBox(height: 24),
              if (widget.uid != null && widget.sync!.pendingCount > 0) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_upload_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${widget.sync!.pendingCount} scan(s) saved on this phone, waiting to upload',
                              ),
                            ),
                            TextButton(
                              onPressed: widget.sync!.isSyncing
                                  ? null
                                  : () => unawaited(widget.sync!.retry()),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                        if (widget.sync!.failureMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(widget.sync!.failureMessage!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.uid == null)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: data.device.online ? deviceReady : mutedGray,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Device',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: slate,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                data.device.online
                                    ? 'Connected · $stateLabel'
                                    : 'Disconnected',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: deepSlate,
                                ),
                              ),
                              Text(
                                data.device.sensorStatus,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: slate,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () => setState(() => tab = 2),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(72, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: const Text(
                            'View device',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              Text(
                widget.uid == null
                    ? 'Latest demo measurement'
                    : 'Latest measurement',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: deepSlate,
                ),
              ),
              const SizedBox(height: 10),
              if (historyError)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Could not load saved measurements. Check your connection.',
                    ),
                  ),
                )
              else if (latest == null)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      widget.uid == null
                          ? 'No scans yet. Start a measurement to add one.'
                          : 'No saved scans yet. Start a live measurement.',
                    ),
                  ),
                )
              else
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openDetails(latest, demo: widget.uid == null),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _DashboardMetric(
                                  label: 'Heart rate',
                                  value: latest.bpm.toString(),
                                  unit: 'BPM',
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _DashboardMetric(
                                  label: 'Blood oxygen',
                                  value: latest.spo2.toString(),
                                  unit: '% SpO₂',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            latest.activity,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: deepSlate,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$latestDate · $latestTime',
                            style: const TextStyle(fontSize: 12, color: slate),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              Text(
                'Start measurement',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: deepSlate,
                ),
              ),
              const SizedBox(height: 10),
              if (widget.uid != null && supportsLiveScan) ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Use your CarePulse device',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Connect over Bluetooth and see the sensor result on this phone.',
                          style: TextStyle(color: slate),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: contextName,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Measurement context',
                          ),
                          items: MockDataService.contexts
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => contextName = value!),
                        ),
                        if (contextName == 'Other') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: customContext,
                            maxLength: 40,
                            decoration: const InputDecoration(
                              labelText: 'Custom context',
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: note,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Optional note',
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: openLiveScan,
                          icon: const Icon(Icons.bluetooth_rounded),
                          label: const Text('Start measurement'),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Completed scans are saved on this phone, then uploaded when online.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: slate),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (widget.uid != null && !supportsLiveScan)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'To start a measurement, open the CarePulse mobile app on your phone and connect to your device over Bluetooth.',
                      style: TextStyle(color: slate),
                    ),
                  ),
                ),
              if (widget.uid == null)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: contextName,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Measurement context',
                            labelStyle: TextStyle(color: slate),
                            floatingLabelStyle: TextStyle(color: slate),
                          ),
                          items: MockDataService.contexts
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: data.canScan
                              ? (value) => setState(() => contextName = value!)
                              : null,
                        ),
                        if (contextName == 'Other') ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: customContext,
                            enabled: data.canScan,
                            maxLength: 40,
                            decoration: const InputDecoration(
                              labelText: 'Custom context (optional)',
                              labelStyle: TextStyle(color: slate),
                              floatingLabelStyle: TextStyle(color: slate),
                              hintText: 'After a walk',
                              counterStyle: TextStyle(
                                color: slate,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: note,
                          enabled: data.canScan,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Optional note',
                            labelStyle: TextStyle(color: slate),
                            floatingLabelStyle: TextStyle(color: slate),
                            counterStyle: TextStyle(color: slate, fontSize: 11),
                            hintText: 'Morning measurement',
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Place your finger on the MAX30102 sensor and keep it still during the measurement.',
                          style: TextStyle(
                            color: slate,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: data.canScan ? openScan : null,
                          child: scanInProgress
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'In progress...',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                )
                              : const Text('Start measurement'),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Demo mode · Fixed sample data',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: slate),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent measurements',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: deepSlate,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => tab = 1),
                    style: TextButton.styleFrom(foregroundColor: slate),
                    child: const Text(
                      'See all',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...visibleMeasurements
                  .take(2)
                  .map(
                    (measurement) => MeasurementRow(
                      measurement: measurement,
                      onTap: () =>
                          openDetails(measurement, demo: widget.uid == null),
                    ),
                  ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
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
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: slate,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 4,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 35,
              height: 1,
              fontWeight: FontWeight.w800,
              color: deepSlate,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              unit,
              style: const TextStyle(fontSize: 12, color: slate),
            ),
          ),
        ],
      ),
    ],
  );
}
