import 'dart:async';
import 'package:aqua_sense/services/auth_session_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_sense/widgets/auth_navigation.dart';

class SessionUser extends Fake implements User {
  SessionUser(this.uid, {this.emailVerified = false});
  @override
  final String uid;
  @override
  final bool emailVerified;
}

class SessionAuth extends Fake implements FirebaseAuth {
  User? active;
  final events = StreamController<User?>.broadcast(sync: true);
  @override
  User? get currentUser => active;
  @override
  Stream<User?> userChanges() => events.stream;
}

void main() {
  for (final flow in ['sign-in', 'registration']) {
    testWidgets('$flow success immediately clears the auth route stack', (
      tester,
    ) async {
      final auth = SessionAuth();
      final session = AuthSessionController(auth);
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(session.dispose);
      addTearDown(auth.events.close);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: AnimatedBuilder(
            animation: session,
            builder: (_, _) => Scaffold(
              body: Text(
                session.user == null
                    ? 'Login root'
                    : 'Dashboard ${session.user!.uid}',
              ),
            ),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TextButton(
              onPressed: () {
                auth.active = SessionUser('$flow-uid');
                AuthSessionNavigation(
                  session: session,
                  navigator: navigator.currentState!,
                ).complete(auth.active!.uid);
              },
              child: const Text('Complete authentication'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete authentication'));
      // No Firebase stream event is emitted to release this navigation.
      await tester.pumpAndSettle();
      expect(find.text('Dashboard $flow-uid'), findsOneWidget);
      expect(find.text('Complete authentication'), findsNothing);
      expect(navigator.currentState!.canPop(), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test(
    'SDK success is accepted synchronously before any auth stream event',
    () {
      final auth = SessionAuth();
      final session = AuthSessionController(auth)..start();
      addTearDown(session.dispose);
      addTearDown(auth.events.close);
      final user = SessionUser('new-account');
      auth.active = user;
      var notified = false;
      session.addListener(() => notified = true);
      session.accept(user.uid);
      expect(session.user, same(user));
      expect(notified, isTrue);
      // Email verification is a data-access policy, not a dashboard route gate.
      expect(session.user!.emailVerified, isFalse);
    },
  );
  test(
    'queued signed-out and old-user events cannot undo a successful login',
    () {
      final auth = SessionAuth();
      final session = AuthSessionController(auth)..start();
      addTearDown(session.dispose);
      addTearDown(auth.events.close);
      final user = SessionUser('current');
      auth.active = user;
      session.accept(user.uid);
      auth.events.add(null);
      auth.events.add(SessionUser('previous'));
      expect(session.user, same(user));
      auth.events.add(user);
      expect(session.user, same(user));
    },
  );
  test('sign-out immediately clears the dashboard session', () {
    final auth = SessionAuth()..active = SessionUser('current');
    final session = AuthSessionController(auth)..start();
    addTearDown(session.dispose);
    addTearDown(auth.events.close);
    auth.active = null;
    auth.events.add(null);
    expect(session.user, isNull);
  });
  test('a UID without a matching SDK session is never accepted', () {
    final auth = SessionAuth();
    final session = AuthSessionController(auth);
    addTearDown(session.dispose);
    addTearDown(auth.events.close);
    expect(() => session.accept('not-signed-in'), throwsStateError);
    auth.active = SessionUser('real');
    expect(() => session.accept('different'), throwsStateError);
    expect(session.user, isNull);
  });
  test('an existing SDK user restores before the first stream event', () {
    final auth = SessionAuth()..active = SessionUser('restored');
    final session = AuthSessionController(auth)..start();
    addTearDown(session.dispose);
    addTearDown(auth.events.close);
    expect(session.user!.uid, 'restored');
  });
}
