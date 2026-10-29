import 'package:aqua_sense/services/registration_service.dart';
import 'package:aqua_sense/screens/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class TestUser extends Fake implements User {
  @override
  String get uid => 'created-user';
  @override
  String get email => 'person@example.com';
  String? savedName;
  bool rejectVerification = false;
  int verificationAttempts = 0;
  @override
  Future<void> updateDisplayName(String? displayName) async {
    savedName = displayName;
  }

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    verificationAttempts++;
    if (rejectVerification) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
  }
}

class TestCredential extends Fake implements UserCredential {
  TestCredential(this.user);
  @override
  final User user;
}

class TestAuth extends Fake implements FirebaseAuth {
  final user = TestUser();
  int creates = 0;
  String? submittedEmail, submittedPassword;
  String? rejectCode;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creates++;
    submittedEmail = email;
    submittedPassword = password;
    if (rejectCode != null) throw FirebaseAuthException(code: rejectCode!);
    return TestCredential(user);
  }
}

class TestProfiles implements RegistrationProfileStore {
  bool reject = false;
  int writes = 0;
  Map<String, String>? profile;
  @override
  Future<void> saveIfAbsent({
    required String uid,
    required String name,
    required String email,
  }) async {
    if (reject) throw StateError('Database unreachable');
    if (profile == null) {
      writes++;
      profile = {'uid': uid, 'displayName': name, 'email': email};
    }
  }
}

void main() {
  test(
    'account creation returns its signed-in UID without waiting for profile or verification work',
    () async {
      final auth = TestAuth(), profiles = TestProfiles()..reject = true;
      final service = FirebaseRegistrationService(
        auth: auth,
        profiles: profiles,
      );
      final user = await service.createAccount(
        email: 'person@example.com',
        password: 'Password123!',
      );
      expect(user.uid, 'created-user');
      expect(auth.creates, 1);
      expect(profiles.profile, isNull);
      expect(auth.user.verificationAttempts, 0);
    },
  );
  test(
    'registration calls Firebase Auth and persists canonical user details with no role',
    () async {
      final auth = TestAuth(), profiles = TestProfiles();
      final service = FirebaseRegistrationService(
        auth: auth,
        profiles: profiles,
      );
      await service.register(
        email: ' person@example.com ',
        password: 'Password123!',
        name: ' Full Name ',
      );
      expect(auth.creates, 1);
      expect(auth.submittedEmail, 'person@example.com');
      expect(auth.submittedPassword, 'Password123!');
      expect(auth.user.savedName, 'Full Name');
      expect(profiles.profile, {
        'uid': 'created-user',
        'displayName': 'Full Name',
        'email': 'person@example.com',
      });
      expect(auth.user.verificationAttempts, 1);
    },
  );
  for (final code in ['weak-password', 'email-already-in-use']) {
    test(
      '$code preserves Firebase error and creates no profile or simulated identity',
      () async {
        final auth = TestAuth()..rejectCode = code;
        final profiles = TestProfiles();
        await expectLater(
          FirebaseRegistrationService(auth: auth, profiles: profiles).register(
            email: 'person@example.com',
            password: 'password',
            name: 'Person',
          ),
          throwsA(
            isA<FirebaseAuthException>().having((e) => e.code, 'code', code),
          ),
        );
        expect(profiles.profile, isNull);
        expect(auth.user.verificationAttempts, 0);
        expect(
          authMessage(FirebaseAuthException(code: code)),
          contains(
            code == 'weak-password'
                ? 'stronger password'
                : 'already has an account',
          ),
        );
      },
    );
  }
  test(
    'failed profile setup explicitly reports existing account and retries without duplicate creation',
    () async {
      final auth = TestAuth(), profiles = TestProfiles()..reject = true;
      final service = FirebaseRegistrationService(
        auth: auth,
        profiles: profiles,
      );
      await expectLater(
        service.register(
          email: 'person@example.com',
          password: 'Password123!',
          name: 'Person',
        ),
        throwsA(
          isA<RegistrationIncompleteException>()
              .having((e) => e.uid, 'uid', 'created-user')
              .having(
                (e) => e.message,
                'message',
                contains('account was created'),
              ),
        ),
      );
      expect(auth.creates, 1);
      profiles.reject = false;
      await service.complete(user: auth.user, name: 'Person');
      expect(auth.creates, 1);
      expect(profiles.writes, 1);
      expect(auth.user.verificationAttempts, 1);
    },
  );
  test(
    'verification retry retains persisted profile and does not create another Auth user',
    () async {
      final auth = TestAuth(), profiles = TestProfiles();
      auth.user.rejectVerification = true;
      final service = FirebaseRegistrationService(
        auth: auth,
        profiles: profiles,
      );
      await expectLater(
        service.register(
          email: 'person@example.com',
          password: 'Password123!',
          name: 'Person',
        ),
        throwsA(
          isA<RegistrationIncompleteException>().having(
            (e) => e.message,
            'message',
            contains('account and profile were saved'),
          ),
        ),
      );
      auth.user.rejectVerification = false;
      await service.complete(user: auth.user, name: 'Person');
      expect(auth.creates, 1);
      expect(profiles.writes, 1);
      expect(auth.user.verificationAttempts, 2);
    },
  );
}
