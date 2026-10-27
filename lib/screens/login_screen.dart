import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/app_theme.dart';
import '../services/firebase_service.dart';
import '../widgets/aqua_brand_mark.dart';
import '../widgets/neumorphic_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    this.startupError,
    this.authError,
    this.onRetry,
    super.key,
  });

  final String? startupError;
  final String? authError;
  final VoidCallback? onRetry;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _working = false;
  String? _message;
  bool _isError = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _message = null;
      _isError = true;
    });
    try {
      await FirebaseService.signIn(_email.text.trim(), _password.text);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message ?? 'Sign-in failed. Check your credentials.';
        _working = false;
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _working = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Sign-in could not be completed: $error';
        _working = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_working) return;
    if (!_validEmail(_email.text.trim())) {
      setState(() {
        _message = 'Enter your email address to receive a reset link.';
        _isError = true;
      });
      return;
    }
    setState(() {
      _working = true;
      _message = null;
      _isError = true;
    });
    try {
      await FirebaseService.sendPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _message = 'If the account exists, a password reset link was sent.';
        _isError = false;
        _working = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message ?? 'Could not send the reset email.';
        _working = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Password reset could not be completed: $error';
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Row(
          children: [
            if (wide) const Expanded(flex: 6, child: _LoginOceanPanel()),
            Expanded(
              flex: wide ? 5 : 1,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 48 : 24,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: _loginForm(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _loginForm(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AquaBrandMark(size: 56),
      const SizedBox(height: 26),
      Text(
        'Welcome back',
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          color: AppColors.navy,
          fontSize: 32,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Sign in to your monitoring workspace.',
        style: TextStyle(color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 28),
      NeumorphicCard(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                enabled: !_working,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) => !_validEmail(value?.trim() ?? '')
                    ? 'Enter a valid email address.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                enabled: !_working,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: _working
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password.'
                    : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _working ? null : _resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              if (widget.startupError != null || widget.authError != null) ...[
                _messageCard(
                  widget.startupError ?? widget.authError!,
                  isError: true,
                ),
                if (widget.onRetry != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _working ? null : widget.onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry connection'),
                  ),
                ],
              ],
              if (_message != null) ...[
                _messageCard(_message!, isError: _isError),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 5),
              FilledButton.icon(
                onPressed: _working ? null : _signIn,
                icon: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(_working ? 'Please wait...' : 'Sign in securely'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_outlined, size: 16, color: AppColors.teal),
          SizedBox(width: 7),
          Flexible(
            child: Text(
              'Access is managed by your project administrator.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _messageCard(String message, {required bool isError}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: (isError ? AppColors.spoiled : AppColors.fresh).withValues(
        alpha: 0.08,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: isError ? AppColors.spoiled : AppColors.fresh,
        fontSize: 12,
        height: 1.45,
      ),
    ),
  );
}

class _LoginOceanPanel extends StatelessWidget {
  const _LoginOceanPanel();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      SvgPicture.asset('assets/images/ocean_hero.svg', fit: BoxFit.cover),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF20A202C), Color(0x8020434D), Color(0x30167D83)],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
        ),
      ),
      const Positioned(top: -80, right: -30, child: _LoginGlow(size: 250)),
      Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                AquaBrandMark(size: 48),
                SizedBox(width: 14),
                Text(
                  'AquaSense',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'Clarity beneath\nthe surface.',
              style: TextStyle(
                color: Colors.white,
                height: 1.12,
                fontWeight: FontWeight.w800,
                fontSize: 42,
                letterSpacing: -1.1,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'A focused workspace for real pH readings, fish image analysis, '
              'and traceable research observations.',
              style: TextStyle(
                color: Color(0xFFD0E5E7),
                fontSize: 15,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            const Row(
              children: [
                _FeatureChip(icon: Icons.sensors_outlined, label: 'Live pH'),
                SizedBox(width: 10),
                _FeatureChip(
                  icon: Icons.image_search_outlined,
                  label: 'Visual analysis',
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'Fish Freshness Monitoring System',
              style: TextStyle(color: Color(0xFFB7D3D6), fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}

class _LoginGlow extends StatelessWidget {
  const _LoginGlow({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.aqua.withValues(alpha: 0.12),
    ),
  );
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.mint),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

bool _validEmail(String value) =>
    value.isNotEmpty && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
