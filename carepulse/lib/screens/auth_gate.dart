import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth.dart';
import 'demo_session.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) => StreamBuilder<Account?>(
    key: ObjectKey(auth),
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
      return _AccountNavigator(
        key: ValueKey(account?.uid),
        child: account == null
            ? LoginScreen(auth: auth)
            : DemoSession(
                name: account.displayName,
                email: account.email,
                uid: auth is FirebaseAuthService ? account.uid : null,
                onSignOut: auth.signOut,
              ),
      );
    },
  );
}

/// Keeps every pushed screen inside the account that owns its data.
/// Replacing this scope disposes the whole stack without a route transition.
class _AccountNavigator extends StatefulWidget {
  const _AccountNavigator({super.key, required this.child});

  final Widget child;

  @override
  State<_AccountNavigator> createState() => _AccountNavigatorState();
}

class _AccountNavigatorState extends State<_AccountNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (result) => _navigatorKey.currentState?.pop(result),
    child: Navigator(
      key: _navigatorKey,
      pages: [MaterialPage<void>(child: widget.child)],
      onDidRemovePage: (_) {},
    ),
  );
}
