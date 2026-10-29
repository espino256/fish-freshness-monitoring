import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/app_shell.dart';
import '../screens/login_screen.dart';
import '../services/auth_session_controller.dart';
import '../services/firebase_service.dart';

class AuthSessionNavigation {
  const AuthSessionNavigation({required this.session, required this.navigator});
  final AuthSessionController session;
  final NavigatorState navigator;
  void complete(String uid) {
    session.accept(uid);
    navigator.popUntil((route) => route.isFirst);
  }
}

void openAuthenticatedDashboard(
  BuildContext context, {
  required String uid,
  ValueChanged<String>? onAuthenticated,
}) {
  if (FirebaseService.currentUser?.uid != uid) {
    throw StateError(
      'Your Firebase session could not be confirmed. Sign in again.',
    );
  }
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  if (onAuthenticated != null) {
    // The app owner updates its session synchronously and clears auth routes.
    onAuthenticated(uid);
    return;
  }
  // Login/Register can also be used independently of AquaSenseApp. Keep a real
  // session listener on the replacement route so sign-out returns to login.
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
    PageRouteBuilder<void>(
      settings: RouteSettings(name: '/dashboard', arguments: uid),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => _DashboardSession(uid: uid),
    ),
    (_) => false,
  );
}

class _DashboardSession extends StatefulWidget {
  const _DashboardSession({required this.uid});
  final String uid;
  @override
  State<_DashboardSession> createState() => _DashboardSessionState();
}

class _DashboardSessionState extends State<_DashboardSession> {
  late final AuthSessionController _session;
  @override
  void initState() {
    super.initState();
    _session = AuthSessionController(FirebaseAuth.instance)..accept(widget.uid);
    _session.addListener(_changed);
    _session.start();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_session.user == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _session.user;
    if (user == null) {
      return LoginScreen(
        onAuthenticated: (uid) {
          _session.accept(uid);
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      );
    }
    return AppShell(key: ValueKey(user.uid), userUid: user.uid);
  }
}
