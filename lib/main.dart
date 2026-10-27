import 'dart:async';

import 'package:firebase_core/firebase_core.dart'
    show Firebase, FirebaseException;
import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'services/firebase_service.dart';
import 'widgets/aqua_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AquaSenseApp());
}

class AquaSenseApp extends StatefulWidget {
  const AquaSenseApp({super.key});

  @override
  State<AquaSenseApp> createState() => _AquaSenseAppState();
}

class _AquaSenseAppState extends State<AquaSenseApp> {
  bool _initializing = true;
  bool _authTimedOut = false;
  int _authAttempt = 0;
  Timer? _authTimeoutTimer;
  String? _firebaseStartupError;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    if (FirebaseService.isConfigured && Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp(
          options: FirebaseService.options,
        ).timeout(const Duration(seconds: 12));
      } on FirebaseException catch (error) {
        _firebaseStartupError =
            error.message ?? 'Firebase could not be initialized.';
      } on Exception catch (error) {
        _firebaseStartupError = 'Firebase could not be initialized: $error';
      }
    }
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _authTimedOut = false;
    });
    _startAuthTimeout();
  }

  void _startAuthTimeout() {
    _authTimeoutTimer?.cancel();
    if (!FirebaseService.isReady) return;
    _authTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _authTimedOut = true);
    });
  }

  void _retryAuth() {
    setState(() {
      _authTimedOut = false;
      _authAttempt++;
    });
    _startAuthTimeout();
  }

  @override
  void dispose() {
    _authTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AquaSense',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: _home(),
  );

  Widget _home() {
    if (_initializing) return const AquaSplash();
    if (!FirebaseService.isConfigured) return const AppShell();

    final startupError = _firebaseStartupError;
    if (startupError != null) {
      return LoginScreen(
        startupError: startupError,
        onRetry: () {
          setState(() {
            _firebaseStartupError = null;
            _initializing = true;
          });
          _initializeFirebase();
        },
      );
    }

    return StreamBuilder(
      key: ValueKey(_authAttempt),
      stream: FirebaseService.authChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_authTimedOut) {
            return LoginScreen(
              authError:
                  'The sign-in session could not be confirmed. You can retry '
                  'or sign in again.',
              onRetry: _retryAuth,
            );
          }
          return const AquaSplash();
        }
        _authTimeoutTimer?.cancel();
        if (snapshot.hasError) {
          return LoginScreen(
            authError: 'Could not check the sign-in session: ${snapshot.error}',
            onRetry: _retryAuth,
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return const AppShell();
      },
    );
  }
}
