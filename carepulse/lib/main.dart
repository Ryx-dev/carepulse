import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/splash.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CarePulseApp());
}

class CarePulseApp extends StatelessWidget {
  const CarePulseApp({super.key, this.auth});

  final AuthService? auth;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CarePulse',
    debugShowCheckedModeBanner: false,
    theme: appTheme,
    home: SplashScreen(next: AuthGate(auth: auth ?? FirebaseAuthService())),
  );
}
