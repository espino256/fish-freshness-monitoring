import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_feedback.dart';
import '../widgets/auth_navigation.dart';
import '../widgets/soft_ui.dart';
import 'register_screen.dart';
export '../widgets/auth_feedback.dart' show authMessage;

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.startupError,
    this.authError,
    this.onRetry,
    this.onAuthenticated,
  });
  final String? startupError, authError;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onAuthenticated;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _emailController = TextEditingController(),
      _passwordController = TextEditingController();
  bool _hidden = true, _busy = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _feedback(String message) {
    setState(() => _message = message);
    showAuthFeedback(context, message);
  }

  bool _hasEmail(String email) => email.isNotEmpty && email.contains('@');

  Future<void> _signIn() async {
    if (_busy) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (!_hasEmail(email) || password.isEmpty) {
      setState(() => _message = null);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!_hasEmail(email)) {
        _feedback('Enter a valid email address.');
      } else {
        _feedback('Enter your password.');
      }
      return;
    }

    FocusScope.of(context).unfocus();
    await _runAuth(
      () => FirebaseService.signIn(email, password),
      authenticates: true,
    );
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    if (!_hasEmail(email)) {
      _feedback('Enter a valid email address first.');
      return;
    }
    await _runAuth(
      () => FirebaseService.sendPasswordReset(email),
      successMessage: 'If the account exists, a password reset link was sent.',
    );
  }

  Future<void> _runAuth(
    Future<void> Function() action, {
    bool authenticates = false,
    String? successMessage,
  }) async {
    if (_busy) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) {
        if (successMessage != null) _feedback(successMessage);
        if (authenticates) {
          final user = FirebaseService.currentUser;
          if (user == null) {
            throw StateError(
              'Firebase did not return a signed-in user. Please retry.',
            );
          }
          openAuthenticatedDashboard(
            context,
            uid: user.uid,
            onAuthenticated: widget.onAuthenticated,
          );
        }
      }
    } catch (error) {
      if (mounted) _feedback(authMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in securely with your Firebase account.',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.startupError != null || widget.authError != null) ...[
                SoftPanel(
                  inset: true,
                  padding: const EdgeInsets.all(14),
                  child: Text(widget.startupError ?? widget.authError!),
                ),
                const SizedBox(height: 20),
              ],
              SoftField(
                child: TextFormField(
                  controller: _emailController,
                  readOnly: _busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SoftField(
                child: TextFormField(
                  controller: _passwordController,
                  readOnly: _busy,
                  obscureText: _hidden,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hidden ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _hidden = !_hidden),
                      icon: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_message!, key: const Key('auth-message')),
                ),
              SoftButton(
                label: _busy ? 'Please wait…' : 'Sign in securely',
                icon: Icons.login,
                primary: true,
                busy: _busy,
                onPressed: _signIn,
              ),
              const SizedBox(height: 16),
              SoftButton(
                label: 'Continue with Google',
                icon: Icons.g_mobiledata,
                busy: _busy,
                onPressed: () => _runAuth(
                  FirebaseService.signInWithGoogle,
                  authenticates: true,
                ),
              ),
              const SizedBox(height: 16),
              SoftButton(
                label: 'Create an account',
                icon: Icons.person_add_alt,
                onPressed: () {
                  if (!_busy) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RegisterScreen(
                          onAuthenticated: widget.onAuthenticated,
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
