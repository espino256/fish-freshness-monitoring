import 'dart:async';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/auth_layout.dart';
import '../widgets/soft_ui.dart';
import '../widgets/auth_feedback.dart';
import '../widgets/auth_navigation.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.onAuthenticated});
  final ValueChanged<String>? onAuthenticated;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  String? _error;
  bool _hidden = true, _confirmHidden = true, _busy = false;
  void _feedback(String message) {
    setState(() => _error = message);
    showAuthFeedback(context, message);
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await FirebaseService.register(
        email: _email.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
      );
      if (!mounted) return;
      openAuthenticatedDashboard(
        context,
        uid: user.uid,
        onAuthenticated: widget.onAuthenticated,
      );
    } on StateError catch (error) {
      if (mounted) _feedback(error.message.toString());
    } on TimeoutException {
      if (mounted) {
        _feedback(
          'Firebase did not initialize in time. Check your connection and retry registration.',
        );
      }
    } catch (error) {
      if (mounted) _feedback(authMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: SoftField(child: child),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AuthLayout(
      back: true,
      title: 'Create your account',
      subtitle:
          'Create a real Firebase account. An internet connection is required.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              TextFormField(
                controller: _name,
                readOnly: _busy,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Enter your name.' : null,
              ),
            ),
            _field(
              TextFormField(
                controller: _email,
                readOnly: _busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (v) =>
                    RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Enter a valid email address.',
              ),
            ),
            _field(
              TextFormField(
                controller: _password,
                readOnly: _busy,
                obscureText: _hidden,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: 'Toggle password visibility',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                ),
                validator: (v) =>
                    (v?.length ?? 0) < 8 ? 'Use at least 8 characters.' : null,
              ),
            ),
            _field(
              TextFormField(
                controller: _confirm,
                readOnly: _busy,
                obscureText: _confirmHidden,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  suffixIcon: IconButton(
                    tooltip: 'Toggle confirmation visibility',
                    onPressed: () =>
                        setState(() => _confirmHidden = !_confirmHidden),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                ),
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match.' : null,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, key: const Key('registration-error')),
              ),
            SoftButton(
              label: _busy ? 'Please wait…' : 'Register',
              icon: Icons.person_add_alt,
              primary: true,
              busy: _busy,
              onPressed: _register,
            ),
            TextButton(
              onPressed: () {
                if (_busy) return;
                Navigator.of(context).pop();
              },
              child: const Text('Already registered? Sign in'),
            ),
          ],
        ),
      ),
    ),
  );
}
