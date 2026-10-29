import 'package:aqua_sense/main.dart';
import 'package:aqua_sense/models/telemetry.dart';
import 'package:aqua_sense/screens/camera_screen.dart';
import 'package:aqua_sense/screens/dashboard_screen.dart';
import 'package:aqua_sense/screens/history_screen.dart';
import 'package:aqua_sense/screens/login_screen.dart';
import 'package:aqua_sense/screens/register_screen.dart';
import 'package:aqua_sense/widgets/aqua_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'splash lasts 2.5 seconds and missing config fails closed at login',
    (tester) async {
      await tester.pumpWidget(const AquaSenseApp());
      expect(find.byType(AquaSplash), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2499));
      expect(find.byType(AquaSplash), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
      expect(
        find.textContaining('Firebase authentication requires configuration'),
        findsOneWidget,
      );
    },
  );

  testWidgets('login validates inputs and toggles visibility', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.ensureVisible(find.text('Sign in securely'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('auth-message'))).data,
      'Enter a valid email address.',
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
  });

  testWidgets(
    'registration has four fields without roles and validates confirmation',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Requested role'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'some-password',
      );
      await tester.ensureVisible(find.text('Register'));
      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(find.text('Enter your name.'), findsOneWidget);
    },
  );

  testWidgets(
    'dashboard has empty and error states without fabricated readings',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(readings: Stream.value([]))),
      );
      await tester.pump();
      expect(find.textContaining('No telemetry yet'), findsOneWidget);
      expect(find.textContaining('pH 0.00'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(readings: Stream.error(StateError('denied'))),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Unable to read telemetry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stale telemetry never shows LIVE status', (tester) async {
    final stale = Telemetry(
      id: 'old',
      deviceId: 'sensor',
      ph: 7.2,
      adcRaw: 2048,
      measuredVoltage: 1.65,
      timestamp: DateTime.utc(2020),
    );
    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(readings: Stream.value([stale]))),
    );
    await tester.pump();
    expect(find.textContaining('STALE'), findsOneWidget);
    expect(find.textContaining('LIVE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all feature screens fit compact and wide layouts', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [320.0, 768.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      for (final page in <Widget>[
        const LoginScreen(),
        const RegisterScreen(),
        const CameraScreen(canSave: false),
        HistoryScreen(readings: Stream.value([])),
        DashboardScreen(readings: Stream.value([])),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$page at $width');
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
