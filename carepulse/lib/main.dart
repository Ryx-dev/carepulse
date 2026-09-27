import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'screens/splash.dart';

void main() => runApp(const CarePulseApp());

class CarePulseApp extends StatelessWidget {
  const CarePulseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CarePulse',
    debugShowCheckedModeBanner: false,
    theme: appTheme,
    home: const SplashScreen(),
  );
}
