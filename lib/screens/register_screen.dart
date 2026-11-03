import 'dart:async';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/auth_layout.dart';
import '../widgets/soft_ui.dart';
import '../widgets/auth_feedback.dart';
import '../widgets/auth_navigation.dart';

/// Clean, simple Flutter registration screen using Firebase Authentication & Cloud Database.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.onAuthenticated});
  final ValueChanged<String>? onAuthenticated;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(),
      _emailController = TextEditingController(),
      _passwordController = TextEditingController(),
      _confirmController = TextEditingController();

  String? _errorMessage;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
    showAuthFeedback(context, message);
  }

  Future<void> _handleRegister() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      // 1. Create account via FirebaseAuth & save user details in users/$uid
      final user = await FirebaseService.register(
        email: email,
        password: password,
        name: name,
      );

      if (!mounted) return;

      // 2. Open dashboard cleanly upon successful account creation
      openAuthenticatedDashboard(
        context,
        uid: user.uid,
        onAuthenticated: widget.onAuthenticated,
      );
    } on StateError catch (error) {
      if (mounted) _showError(error.message.toString());
    } on TimeoutException {
      if (mounted) {
        _showError(
          'Firebase did not respond in time. Check your network connection and retry.',
        );
      }
    } catch (error) {
      if (mounted) _showError(authMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildField(Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: SoftField(child: child),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AuthLayout(
        back: true,
        title: 'Create an account',
        subtitle:
            'Register with your name and email to access live telemetry.',
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Name Field
              _buildField(
                TextFormField(
                  controller: _nameController,
                  readOnly: _busy,
                  maxLength: 100,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    counterText: '',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter your name.' : null,
                ),
              ),

              // 2. Email Field
              _buildField(
                TextFormField(
                  controller: _emailController,
                  readOnly: _busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) => RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Enter a valid email address.',
                ),
              ),

              // 3. Password Field
              _buildField(
                TextFormField(
                  controller: _passwordController,
                  readOnly: _busy,
                  obscureText: _hidePassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: 'Toggle password visibility',
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) => (v?.length ?? 0) < 8
                      ? 'Use at least 8 characters.'
                      : null,
                ),
              ),

              // 4. Confirm Password Field
              _buildField(
                TextFormField(
                  controller: _confirmController,
                  readOnly: _busy,
                  obscureText: _hideConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleRegister(),
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Toggle confirmation visibility',
                      onPressed: () =>
                          setState(() => _hideConfirm = !_hideConfirm),
                      icon: Icon(
                        _hideConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) => v != _passwordController.text
                      ? 'Passwords do not match.'
                      : null,
                ),
              ),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    key: const Key('registration-error'),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // 5. Register Action Button with Loading State
              SoftButton(
                label: _busy ? 'Creating account…' : 'Register',
                icon: Icons.person_add_alt,
                primary: true,
                busy: _busy,
                onPressed: _handleRegister,
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () {
                  if (!_busy) Navigator.of(context).pop();
                },
                child: const Text('Already registered? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
