import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_measurement_sync.dart';
import '../services/mock_data_service.dart';
import 'home.dart';

/// Owns the in-memory mock data for one signed-in account.
class DemoSession extends StatefulWidget {
  const DemoSession({
    super.key,
    required this.name,
    required this.email,
    this.uid,
    this.onSignOut,
  });

  final String name;
  final String email;
  final String? uid;
  final Future<void> Function()? onSignOut;

  @override
  State<DemoSession> createState() => _DemoSessionState();
}

class _DemoSessionState extends State<DemoSession> {
  final MockDataService data = MockDataService();
  BleMeasurementSync? sync;

  @override
  void initState() {
    super.initState();
    final uid = widget.uid;
    if (uid != null) {
      sync = BleMeasurementSync(uid: uid);
      unawaited(sync!.initialize().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    sync?.dispose();
    data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HomeShell(
    name: widget.name,
    email: widget.email,
    uid: widget.uid,
    sync: sync,
    data: data,
    onSignOut: widget.onSignOut,
  );
}
