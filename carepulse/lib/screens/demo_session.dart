import 'package:flutter/material.dart';

import '../services/mock_data_service.dart';
import 'home.dart';

/// Owns the in-memory data for one signed-in demo session.
class DemoSession extends StatefulWidget {
  const DemoSession({super.key, required this.name, required this.email});

  final String name;
  final String email;

  @override
  State<DemoSession> createState() => _DemoSessionState();
}

class _DemoSessionState extends State<DemoSession> {
  final MockDataService data = MockDataService();

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      HomeShell(name: widget.name, email: widget.email, data: data);
}
