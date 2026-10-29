import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'core/app_preferences.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_session_controller.dart';
import 'services/firebase_service.dart';
import 'widgets/aqua_splash.dart';
import 'widgets/soft_ui.dart';
import 'widgets/auth_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AquaSenseApp());
}

class AquaSenseApp extends StatefulWidget {
  const AquaSenseApp({super.key, this.initializeFirebase});
  final Future<void> Function()? initializeFirebase;
  @override
  State<AquaSenseApp> createState() => _AquaSenseAppState();
}

class _AquaSenseAppState extends State<AquaSenseApp> {
  final _preferences = AppPreferences();
  final _navigator = GlobalKey<NavigatorState>();
  AuthSessionController? _session;
  bool _initializing = true;
  String? _startupError;
  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    final splashDelay = Future<void>.delayed(
      const Duration(milliseconds: 2500),
    );
    String? errorMessage;
    try {
      await (widget.initializeFirebase?.call() ?? FirebaseService.initialize())
          .timeout(const Duration(milliseconds: 2500));
    } catch (error) {
      errorMessage = authMessage(error);
    }
    await splashDelay;
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _startupError = errorMessage;
    });
    if (FirebaseService.isReady) _attachSession();
  }

  void _attachSession() {
    if (_session != null) return;
    _session = AuthSessionController(FirebaseAuth.instance);
    _session!.addListener(_sessionChanged);
    _session!.start();
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session?.user == null) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  void _authenticated(String uid) {
    if (!mounted) return;
    _attachSession();
    // accept() reads the SDK's currentUser immediately; no stream wait,
    // verification route, profile write or extra sign-in is on this path.
    AuthSessionNavigation(
      session: _session!,
      navigator: _navigator.currentState!,
    ).complete(uid);
    setState(() {
      _initializing = false;
      _startupError = null;
    });
  }

  void _retryFirebase() {
    // A signed-in user can refresh without returning to the splash/login page.
    if (_session?.user != null) {
      _session!.accept(_session!.user!.uid);
      return;
    }
    setState(() {
      _initializing = true;
      _startupError = null;
    });
    _initializeFirebase();
  }

  @override
  void dispose() {
    _session?.removeListener(_sessionChanged);
    _session?.dispose();
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PreferencesScope(
    preferences: _preferences,
    child: AnimatedBuilder(
      animation: _preferences,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        title: 'AquaSense',
        debugShowCheckedModeBanner: false,
        theme: _preferences.highContrast
            ? AppTheme.highContrast
            : AppTheme.light,
        builder: (context, child) =>
            OceanBackdrop(child: child ?? const SizedBox()),
        home: _home(),
      ),
    ),
  );
  Widget _home() {
    if (_initializing) return const AquaSplash();
    final user = _session?.user;
    if (user != null) {
      return AppShell(
        key: ValueKey(user.uid),
        userUid: user.uid,
        onRetryCloud: _retryFirebase,
      );
    }
    return LoginScreen(
      startupError:
          _startupError ??
          (!FirebaseService.isReady
              ? 'Firebase authentication requires configuration. Add your local build configuration to sign in.'
              : null),
      authError: _session?.error,
      onRetry: _retryFirebase,
      onAuthenticated: _authenticated,
    );
  }
}
