import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth.dart';
import 'demo_session.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) => StreamBuilder<Account?>(
    stream: auth.accountChanges,
    initialData: auth.currentAccount,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text('Could not load your account. Restart the app.'),
          ),
        );
      }
      final account = snapshot.data;
      if (account == null) return LoginScreen(auth: auth);
      return DemoSession(
        key: ValueKey(account.uid),
        name: account.displayName,
        email: account.email,
        uid: auth is FirebaseAuthService ? account.uid : null,
        onSignOut: auth.signOut,
      );
    },
  );
}
