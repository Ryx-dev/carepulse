import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/measurement.dart';
import '../services/mock_data_service.dart';
import 'auth.dart';
import 'pages.dart';
import 'profile.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.name, required this.email});
  final String name;
  final String email;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final data = MockDataService();
  final note = TextEditingController();
  String contextName = 'Resting';
  int tab = 0;

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
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    data.removeListener(refresh);
    data.dispose();
    note.dispose();
    super.dispose();
  }

  void openScan() {
    if (!data.canScan) return;
    final activity = contextName == 'Other' && note.text.trim().isNotEmpty
        ? note.text.trim()
        : contextName;
    data.startScan(activity: activity, note: note.text);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ScanScreen(data: data)));
  }

  void openDetails(Measurement measurement) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MeasurementDetailsScreen(measurement: measurement),
      ),
    );
  }

  void signOut() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 64,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded, color: primaryRed, size: 24),
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
          child: const Text(
            'DEMO DATA',
            style: TextStyle(
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
      0 => homePage(context),
      1 => HistoryScreen(data: data, onDetails: openDetails),
      2 => DeviceScreen(device: data.device),
      _ => ProfileScreen(
        name: widget.name,
        email: widget.email,
        onSignOut: signOut,
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

  Widget homePage(BuildContext context) {
    final latest = data.latest;
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
              const Text(
                'Personal readings at a glance',
                style: TextStyle(fontSize: 14, color: slate),
              ),
              const SizedBox(height: 24),
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
                'Latest measurement',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: deepSlate,
                ),
              ),
              const SizedBox(height: 10),
              if (latest == null)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No scans yet. Start a measurement to add one.',
                    ),
                  ),
                )
              else
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openDetails(latest),
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
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: contextName,
                        decoration: const InputDecoration(
                          labelText: 'Measurement context',
                          labelStyle: TextStyle(color: slate),
                          floatingLabelStyle: TextStyle(color: slate),
                        ),
                        items: MockDataService.contexts
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: data.canScan
                            ? (value) => setState(() => contextName = value!)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: note,
                        maxLength: 100,
                        decoration: InputDecoration(
                          labelText: contextName == 'Other'
                              ? 'Custom context or note'
                              : 'Optional note',
                          labelStyle: const TextStyle(color: slate),
                          floatingLabelStyle: const TextStyle(color: slate),
                          counterStyle: const TextStyle(
                            color: slate,
                            fontSize: 11,
                          ),
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
                                  Text(
                                    'In progress...',
                                    style: TextStyle(fontSize: 14),
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
              ...data.measurements
                  .take(2)
                  .map(
                    (measurement) => MeasurementRow(
                      measurement: measurement,
                      onTap: () => openDetails(measurement),
                    ),
                  ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'CarePulse is for personal monitoring and logging only. It is not a medical diagnostic device.',
                  style: TextStyle(fontSize: 11, color: slate, height: 1.4),
                ),
              ),
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
