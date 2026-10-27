import 'package:aqua_sense/main.dart';
import 'package:aqua_sense/screens/login_screen.dart';
import 'package:aqua_sense/widgets/aqua_splash.dart';
import 'package:aqua_sense/widgets/ocean_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('dashboard shows honest empty sensor state on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AquaSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('No data · sensor readings unavailable'), findsOneWidget);
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('wide dashboard renders desktop navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AquaSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('AquaSense'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Monitoring overview'), findsWidgets);
  });

  testWidgets('dashboard hero renders on compact, tablet, and desktop widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in [
      const Size(320, 760),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const AquaSenseApp());
      await tester.pumpAndSettle();

      expect(find.byType(OceanArt), findsOneWidget, reason: '$size');
      expect(
        find.text(
          size.width < 600
              ? 'Welcome to AquaSense.'
              : 'Clarity beneath the surface.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('splash screen displays AquaSense branding and loading state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AquaSplash()));

    expect(find.text('AquaSense'), findsOneWidget);
    expect(find.text('Fish Freshness Monitoring System'), findsOneWidget);
    expect(
      find.text('Preparing your monitoring environment...'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('login screen validates fields and toggles password visibility', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      find.text('Access is managed by your project administrator.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'researcher@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'not-a-real-password',
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
  });

  testWidgets('login screen adapts from mobile to desktop layouts', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in [
      const Size(360, 780),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();
      expect(find.text('Welcome back'), findsOneWidget, reason: '$size');
      expect(find.text('Sign in securely'), findsOneWidget, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
