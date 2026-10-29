import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import 'auth_feedback.dart';
import 'soft_ui.dart';

/// Optional setup lives inside the dashboard; it never blocks authentication.
class AccountSetupNotice extends StatefulWidget {
  const AccountSetupNotice({super.key, required this.onVerified});
  final VoidCallback onVerified;
  @override
  State<AccountSetupNotice> createState() => _AccountSetupNoticeState();
}

class _AccountSetupNoticeState extends State<AccountSetupNotice> {
  bool _busy = false;
  String? _shownWarning;
  @override
  void initState() {
    super.initState();
    FirebaseService.registrationSetup.addListener(_setupChanged);
    _setupChanged();
  }

  void _setupChanged() {
    final state = FirebaseService.registrationSetup.value;
    if (state?.pending == true) _shownWarning = null;
    final warning = state?.warning;
    if (warning == null ||
        state?.uid != FirebaseService.currentUser?.uid ||
        warning == _shownWarning) {
      return;
    }
    _shownWarning = warning;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state?.uid == FirebaseService.currentUser?.uid) {
        showAuthFeedback(context, warning);
      }
    });
  }

  @override
  void dispose() {
    FirebaseService.registrationSetup.removeListener(_setupChanged);
    super.dispose();
  }

  Future<void> _verify({bool resend = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = FirebaseService.currentUser;
      if (user == null) throw StateError('Sign in again to verify your email.');
      if (resend) {
        await user.sendEmailVerification();
        if (mounted) showAuthFeedback(context, 'Verification email sent.');
      } else {
        await user.reload();
        await FirebaseService.currentUser?.getIdToken(true);
        if (!mounted) return;
        if (FirebaseService.currentUser?.emailVerified == true) {
          widget.onVerified();
          showAuthFeedback(
            context,
            'Email verified. Cloud subscriptions refreshed.',
          );
        } else {
          showAuthFeedback(
            context,
            'Open the link in your verification email, then check again.',
          );
        }
      }
    } catch (error) {
      if (mounted) showAuthFeedback(context, authMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<RegistrationSetupState?>(
    valueListenable: FirebaseService.registrationSetup,
    builder: (context, setup, _) {
      final user = FirebaseService.currentUser;
      if (user == null) return const SizedBox.shrink();
      final state = setup?.uid == user.uid ? setup : null;
      if (user.emailVerified &&
          state?.pending != true &&
          state?.warning == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: SoftPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state?.pending == true)
                const Text(
                  'Finishing your profile and sending verification in the background…',
                ),
              if (state?.warning != null) ...[
                Text(state!.warning!),
                TextButton(
                  onPressed: () async {
                    await FirebaseService.retryPendingRegistrationSetup();
                  },
                  child: const Text('Retry account setup'),
                ),
              ],
              if (!user.emailVerified) ...[
                const Text(
                  'Welcome! Verify your email to unlock cloud data. You can stay in the dashboard while you finish setup.',
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => _verify(),
                      child: Text(_busy ? 'Checking…' : 'I verified my email'),
                    ),
                    TextButton(
                      onPressed: () => _verify(resend: true),
                      child: const Text('Resend verification email'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
