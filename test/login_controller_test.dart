import 'package:aqua_sense/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapSignIn(WidgetTester tester) async {
  final button = find.text('Sign in securely');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'controller email containing @ reaches live auth without a strict domain regex',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        '  inspector@localhost  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '  password-123  ',
      );
      await tapSignIn(tester);
      // No project is injected in widget tests. Reaching the Firebase readiness
      // error proves the Sign In button dispatched the real authentication path.
      expect(
        tester.widget<Text>(find.byKey(const Key('auth-message'))).data,
        contains('Firebase authentication requires configuration'),
      );
      expect(find.text('Enter a valid email address.'), findsNothing);
      expect(find.text('Enter a valid email address first.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a previous reset/form error cannot block updated controller credentials',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address first.'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'invalid',
      );
      await tapSignIn(tester);
      expect(find.text('Enter a valid email address.'), findsWidgets);
      expect(find.text('Enter a valid email address first.'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        '  person@example.com  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '  password-123  ',
      );
      await tapSignIn(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('auth-message'))).data,
        contains('Firebase authentication requires configuration'),
      );
      expect(find.text('Enter a valid email address.'), findsNothing);
      expect(find.text('Enter a valid email address first.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('trimmed empty passwords are rejected before authentication', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'person@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      '   ',
    );
    await tapSignIn(tester);
    expect(find.text('Enter your password.'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const Key('auth-message'))).data,
      'Enter your password.',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
