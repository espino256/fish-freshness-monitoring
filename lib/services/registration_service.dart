import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// An Auth account already exists; retry setup without creating another user.
class RegistrationIncompleteException implements Exception {
  const RegistrationIncompleteException(this.uid, this.message);
  final String uid;
  final String message;
}

abstract interface class RegistrationProfileStore {
  Future<void> saveIfAbsent({
    required String uid,
    required String name,
    required String email,
  });
}

class RealtimeRegistrationProfiles implements RegistrationProfileStore {
  RealtimeRegistrationProfiles(this.database);
  final FirebaseDatabase database;

  @override
  Future<void> saveIfAbsent({
    required String uid,
    required String name,
    required String email,
  }) async {
    final reference = database.ref('users/$uid');
    // Profiles are immutable to clients. A retry after verification delivery
    // failed must not overwrite an already persisted profile/timestamp.
    if ((await reference.get()).exists) return;
    await reference.set({
      'displayName': name,
      'email': email,
      'createdAt': ServerValue.timestamp,
    });
  }
}

class FirebaseRegistrationService {
  FirebaseRegistrationService({required this.auth, required this.profiles});
  final FirebaseAuth auth;
  final RegistrationProfileStore profiles;

  Future<User> createAccount({
    required String email,
    required String password,
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user!;
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    // This is always the real Firebase Auth operation in the app. The demo
    // session is deliberately not a dependency of registration.
    final user = await createAccount(email: email, password: password);
    await complete(user: user, name: name.trim());
  }

  Future<void> complete({required User user, required String name}) async {
    try {
      await user.updateDisplayName(name);
    } on Object {
      throw RegistrationIncompleteException(
        user.uid,
        'Your Firebase account was created, but your name could not be saved. Retry account setup or sign in to continue.',
      );
    }
    try {
      await profiles.saveIfAbsent(
        uid: user.uid,
        name: name,
        email: user.email!,
      );
    } on Object {
      throw RegistrationIncompleteException(
        user.uid,
        'Your Firebase account was created, but your profile could not be saved. Check the connection and database rules, then retry account setup.',
      );
    }
    try {
      await user.sendEmailVerification();
    } on Object {
      throw RegistrationIncompleteException(
        user.uid,
        'Your account and profile were saved, but the verification email could not be sent. Retry account setup or sign in to resend verification.',
      );
    }
  }
}
