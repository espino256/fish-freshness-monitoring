import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/firebase_service.dart';
import 'auth_feedback.dart';
import 'soft_ui.dart';

/// Welcome & Verification popup dialog and banner for unverified accounts.
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

  Future<void> _verify({bool resend = false, BuildContext? dialogContext}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = FirebaseService.currentUser;
      if (user == null) throw StateError('Sign in again to verify your email.');
      if (resend) {
        await user.sendEmailVerification();
        if (mounted) showAuthFeedback(context, 'Verification email sent to ${user.email}.');
      } else {
        await user.reload();
        await FirebaseService.currentUser?.getIdToken(true);
        if (!mounted) return;
        if (FirebaseService.currentUser?.emailVerified == true) {
          widget.onVerified();
          if (dialogContext != null && dialogContext.mounted) {
            final nav = Navigator.of(dialogContext);
            if (nav.canPop()) nav.pop();
          }
          showAuthFeedback(
            context,
            'Email verified! Cloud workspace unlocked.',
          );
        } else {
          showAuthFeedback(
            context,
            'Verification link not opened yet. Check your inbox or spam folder.',
          );
        }
      }
    } catch (error) {
      if (mounted) showAuthFeedback(context, authMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openVerificationDialog(BuildContext parentContext) {
    showDialog<void>(
      context: parentContext,
      barrierDismissible: true,
      builder: (dialogCtx) => _WelcomeVerificationDialog(
        userEmail: FirebaseService.currentUser?.email ?? '',
        busy: _busy,
        onCheckVerification: () => _verify(dialogContext: dialogCtx),
        onResendEmail: () => _verify(resend: true, dialogContext: dialogCtx),
        onDismiss: () {
          if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RegistrationSetupState?>(
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.aqua, width: 1.5),
              boxShadow: softShadows,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.aqua.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_rounded,
                    color: AppColors.teal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Welcome to AquaSense!',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                      Text(
                        state?.pending == true
                            ? 'Saving profile & sending verification…'
                            : state?.warning ?? 'Verify ${user.email} to sync cloud data.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _openVerificationDialog(context),
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text(
                    'Verify',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// High-brightness Welcome & Verification Modal Pop-Up Dialog
class _WelcomeVerificationDialog extends StatelessWidget {
  const _WelcomeVerificationDialog({
    required this.userEmail,
    required this.busy,
    required this.onCheckVerification,
    required this.onResendEmail,
    required this.onDismiss,
  });

  final String userEmail;
  final bool busy;
  final VoidCallback onCheckVerification;
  final VoidCallback onResendEmail;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bright Icon Badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_unread_rounded,
                size: 32,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Welcome to AquaSense!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'A verification email was sent to:',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.muted.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                userEmail,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Please open the verification link in your email inbox to unlock live cloud telemetry and sync.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Primary High-Brightness Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                onPressed: busy ? null : onCheckVerification,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  busy ? 'Checking verification…' : 'I verified my email',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Resend & Dismiss Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.teal,
                      side: const BorderSide(color: AppColors.teal),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: busy ? null : onResendEmail,
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: const Text(
                      'Resend',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.muted,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onDismiss,
                    child: const Text(
                      'Later',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
