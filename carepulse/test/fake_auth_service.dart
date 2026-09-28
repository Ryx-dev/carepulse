import 'dart:async';

import 'package:carepulse/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FakeAuthService implements AuthService {
  final _changes = StreamController<Account?>.broadcast();
  Account? _account;
  bool failSignIn = false;

  @override
  Account? get currentAccount => _account;

  @override
  Stream<Account?> get accountChanges => _changes.stream;

  void emit(Account? account) {
    _account = account;
    _changes.add(account);
  }

  @override
  Future<void> signIn(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (failSignIn) throw FirebaseAuthException(code: 'invalid-credential');
    emit(Account(uid: 'test-user', email: email, name: 'Demo User'));
  }

  @override
  Future<void> register(String name, String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    emit(Account(uid: 'test-user', email: email, name: name));
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> signOut() async => emit(null);
}
