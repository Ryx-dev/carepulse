import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final passwordFocus = FocusNode();
  bool hidden = true;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (loading) return;
    FocusScope.of(context).unfocus();
    if (!formKey.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      await widget.auth.signIn(email.text.trim(), password.text);
    } catch (failure) {
      if (mounted) setState(() => error = authErrorMessage(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    if (loading) return;
    final address = email.text.trim();
    final validation = emailValidator(address);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.auth.sendPasswordReset(address);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'If this email has an account, a reset link has been sent.',
            ),
          ),
        );
      }
    } catch (failure) {
      if (mounted) setState(() => error = authErrorMessage(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Sign in',
    subtitle: 'View your CarePulse measurements and scan history.',
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: email,
            enabled: !loading,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline_rounded, size: 22),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => passwordFocus.requestFocus(),
            validator: emailValidator,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: password,
            focusNode: passwordFocus,
            enabled: !loading,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            obscureText: hidden,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22),
              suffixIcon: IconButton(
                tooltip: hidden ? 'Show password' : 'Hide password',
                onPressed: loading
                    ? null
                    : () => setState(() => hidden = !hidden),
                icon: Icon(
                  hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) =>
                (value == null || value.isEmpty) ? 'Enter your password' : null,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: loading ? null : resetPassword,
              child: const Text(
                'Forgot password?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: primaryRed)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: loading ? null : submit,
            child: loading
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
                      SizedBox(width: 10),
                      Text('Signing in...'),
                    ],
                  )
                : const Text('Sign in'),
          ),
          const SizedBox(height: 18),
          AuthNavigationLink(
            prompt: "Don't have an account? ",
            action: 'Create account',
            onPressed: loading
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RegisterScreen(auth: widget.auth),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.auth});

  final AuthService auth;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool hidden = true;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (loading) return;
    if (!formKey.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.auth.register(
        name.text.trim(),
        email.text.trim(),
        password.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (failure) {
      if (mounted) setState(() => error = authErrorMessage(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Create your account',
    subtitle: 'Create an account to explore CarePulse.',
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: name,
            enabled: !loading,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Enter your name'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: email,
            enabled: !loading,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: emailValidator,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: password,
            enabled: !loading,
            obscureText: hidden,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: hidden ? 'Show password' : 'Hide password',
                onPressed: loading
                    ? null
                    : () => setState(() => hidden = !hidden),
                icon: Icon(
                  hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) => (value == null || value.length < 6)
                ? 'Use at least 6 characters'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: confirm,
            enabled: !loading,
            obscureText: hidden,
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            validator: (value) =>
                value != password.text ? 'Passwords do not match' : null,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: primaryRed)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: loading ? null : submit,
            child: Text(loading ? 'Creating account...' : 'Create account'),
          ),
          const SizedBox(height: 16),
          AuthNavigationLink(
            prompt: 'Already have an account? ',
            action: 'Sign in',
            onPressed: loading ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}

String? emailValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'Enter your email address';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
    return 'Enter a valid email address';
  }
  return null;
}

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 428),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: coral.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Image(
                      image: AssetImage(appMarkAsset),
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                      semanticLabel: 'CarePulse logo',
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 28,
                    color: slate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: slate,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),
                child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthNavigationLink extends StatelessWidget {
  const AuthNavigationLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  final String prompt;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(prompt, style: const TextStyle(color: slate)),
      TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.pressed) ? slate : primaryRed,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontWeight: FontWeight.w600,
              decoration: states.contains(WidgetState.hovered)
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
        ),
        child: Text(action),
      ),
    ],
  );
}
