import 'package:firebase_auth/firebase_auth.dart';

class Account {
  const Account({required this.uid, required this.email, this.name});

  final String uid;
  final String email;
  final String? name;

  String get displayName =>
      name?.trim().isNotEmpty == true ? name!.trim() : email.split('@').first;
}

abstract class AuthService {
  Account? get currentAccount;
  Stream<Account?> get accountChanges;
  Future<void> signIn(String email, String password);
  Future<void> register(String name, String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Account? _account(User? user) => user == null
      ? null
      : Account(uid: user.uid, email: user.email ?? '', name: user.displayName);

  @override
  Account? get currentAccount => _account(_auth.currentUser);

  @override
  Stream<Account?> get accountChanges => _auth.userChanges().map(_account);

  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> register(String name, String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(name);
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() => _auth.signOut();
}

String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'email-already-in-use' => 'An account with this email already exists.',
      'weak-password' => 'Choose a stronger password.',
      'user-disabled' => 'This account is disabled.',
      'wrong-password' ||
      'user-not-found' ||
      'invalid-credential' => 'Email or password is incorrect.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      'network-request-failed' => 'Check your connection and try again.',
      _ => 'Authentication failed. Please try again.',
    };
  }
  return 'Something went wrong. Please try again.';
}
