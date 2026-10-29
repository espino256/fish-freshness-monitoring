import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Routing state comes from the SDK's active user, never a local identity.
/// accept() handles an SDK operation's success without waiting for its stream.
class AuthSessionController extends ChangeNotifier {
  AuthSessionController(this.auth) : _user = auth.currentUser;
  final FirebaseAuth auth;
  User? _user;
  User? get user => _user;
  StreamSubscription<User?>? _subscription;
  String? error;

  void start() {
    _subscription ??= auth.userChanges().listen(
      (event) {
        final active = auth.currentUser;
        // Ignore a queued signed-out/old-user event after a successful sign-in.
        if (event?.uid != active?.uid) return;
        _user = active;
        error = null;
        notifyListeners();
      },
      onError: (Object _) {
        error =
            'Could not observe the Firebase session. Check your connection.';
        _user = auth.currentUser;
        notifyListeners();
      },
    );
  }

  void accept(String uid) {
    final active = auth.currentUser;
    if (active == null || active.uid != uid) {
      throw StateError(
        'Firebase has no active session for this account. Sign in again.',
      );
    }
    _user = active;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
