import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'auth.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const displayDuration = Duration(milliseconds: 900);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.displayDuration, _openLogin);
  }

  void _openLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage(appMarkAsset),
              width: 112,
              height: 112,
              fit: BoxFit.contain,
              semanticLabel: 'CarePulse logo',
            ),
            SizedBox(height: 18),
            Text(
              'CarePulse',
              style: TextStyle(
                color: deepSlate,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
