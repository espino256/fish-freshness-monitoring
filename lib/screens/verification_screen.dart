import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../widgets/auth_layout.dart';
import '../widgets/soft_ui.dart';
import '../widgets/auth_feedback.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _run(bool resend) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final user = FirebaseService.currentUser;
      if (user == null) throw StateError('Sign in first.');
      if (resend) {
        await user.sendEmailVerification();
        if (mounted) {
          setState(() => _message = 'Verification email sent.');
          showAuthFeedback(context, _message!);
        }
      } else {
        await user.reload();
        await FirebaseService.currentUser?.getIdToken(true);
        if (mounted && FirebaseService.currentUser?.emailVerified != true) {
          setState(
            () => _message =
                'Open the verification link in your inbox, then check again.',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = authMessage(error));
        showAuthFeedback(context, _message!);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Verify your email',
    subtitle:
        'Open the link sent to ${FirebaseService.currentUser?.email ?? 'your inbox'}.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_unread_outlined, size: 56),
        const SizedBox(height: 24),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_message!),
          ),
        SoftButton(
          label: 'I verified my email',
          primary: true,
          busy: _busy,
          onPressed: () => _run(false),
        ),
        const SizedBox(height: 16),
        SoftButton(
          label: 'Resend verification email',
          busy: _busy,
          onPressed: () => _run(true),
        ),
        TextButton(
          onPressed: () async {
            if (_busy) return;
            try {
              await FirebaseService.signOut();
            } catch (e) {
              if (mounted) {
                setState(() => _message = authMessage(e));
                showAuthFeedback(this.context, _message!);
              }
            }
          },
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
}
