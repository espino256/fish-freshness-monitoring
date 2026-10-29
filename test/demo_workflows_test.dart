import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aqua_sense/core/app_theme.dart';
import 'package:aqua_sense/core/app_preferences.dart';
import 'package:aqua_sense/main.dart';
import 'package:aqua_sense/screens/app_shell.dart';
import 'package:aqua_sense/screens/camera_screen.dart';
import 'package:aqua_sense/screens/dashboard_screen.dart';
import 'package:aqua_sense/screens/history_screen.dart';
import 'package:aqua_sense/screens/login_screen.dart';
import 'package:aqua_sense/screens/register_screen.dart';
import 'package:aqua_sense/screens/settings_screen.dart';
import 'package:aqua_sense/services/demo_session.dart';
import 'package:aqua_sense/widgets/soft_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> start(WidgetTester tester) async {
  await tester.pumpWidget(const AquaSenseApp());
  await tester.pump(const Duration(milliseconds: 2500));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String label) async {
  final target = find.text(label).first;
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pump();
  for (
    var i = 0;
    i < 100 &&
        find
            .byWidgetPredicate((w) => w is SoftButton && w.busy)
            .evaluate()
            .isNotEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pumpAndSettle();
}

Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('build/qa')..createSync(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

// Component tests can supply synthetic sensor/image data without ever signing
// in a local user. Production AquaSenseApp has no DemoScope or bypass route.
Widget component(Widget child, DemoSession data, AppPreferences preferences) =>
    DemoScope(
      session: data,
      child: PreferencesScope(
        preferences: preferences,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
        ),
      ),
    );
void main() {
  setUpAll(() async {
    await (FontLoader('AquaSans')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'failed Firebase initialization stays at login without a local session',
    (tester) async {
      await tester.pumpWidget(
        AquaSenseApp(
          initializeFirebase: () async =>
              throw StateError('initialization unavailable'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
      expect(find.textContaining('initialization unavailable'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Explore demo'), findsNothing);
      expect(find.byType(DemoScope), findsNothing);
      expect(find.byType(AppShell), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'stalled Firebase startup exits splash and never bypasses real authentication',
    (tester) async {
      final backend = Completer<void>();
      await tester.pumpWidget(
        AquaSenseApp(initializeFirebase: () => backend.future),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('did not respond in time'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.textContaining('DEMO MODE'), findsNothing);
      backend.complete();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'email, Google and password reset cannot simulate success without Firebase',
    (tester) async {
      await start(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'person@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password-123',
      );
      for (final button in [
        'Sign in securely',
        'Continue with Google',
        'Forgot password?',
      ]) {
        await tapText(tester, button);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('auth-message'))).data,
          contains('Firebase authentication requires configuration'),
        );
        expect(find.byType(AppShell), findsNothing);
        expect(find.textContaining('reset link was sent'), findsNothing);
        await tapText(tester, 'Dismiss');
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'live registration has four fields, reports missing Firebase, and keeps navigation active',
    (tester) async {
      await start(tester);
      await tapText(tester, 'Create an account');
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(find.text('Requested role'), findsNothing);
      for (final (label, value) in [
        ('Full name', 'New Person'),
        ('Email address', 'person@example.com'),
        ('Password', 'password-123'),
        ('Confirm password', 'password-123'),
      ]) {
        await reveal(tester, find.widgetWithText(TextFormField, label));
        await tester.enterText(
          find.widgetWithText(TextFormField, label),
          value,
        );
      }
      await tapText(tester, 'Register');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('registration-error'))).data,
        contains('Firebase authentication requires configuration'),
      );
      expect(find.byType(AppShell), findsNothing);
      await tapText(tester, 'Dismiss');
      await tapText(tester, 'Already registered? Sign in');
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dashboard pH and LED controls process injected sensor fixtures without authentication',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = DemoSession()..enable();
      final preferences = AppPreferences();
      addTearDown(data.dispose);
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        component(DashboardScreen(readings: data.live), data, preferences),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Spoiled · 7.4');
      expect(data.ph, 7.4);
      expect(data.leds[26], isTrue);
      if (find.byKey(const Key('led-27')).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.byKey(const Key('led-27')),
          -180,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await reveal(tester, find.byKey(const Key('led-27')));
      await tester.tap(find.byKey(const Key('led-27')));
      await tester.pumpAndSettle();
      expect(data.manualLeds, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'camera processes injected target, flash, resolution, HSV and local fixture history',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = DemoSession()..enable();
      final preferences = AppPreferences();
      addTearDown(data.dispose);
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        component(const CameraScreen(canSave: true), data, preferences),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Connect stream');
      await reveal(tester, find.byKey(const Key('camera-flash')));
      await tester.tap(find.byKey(const Key('camera-flash')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.byKey(const Key('camera-flash'))).value,
        isTrue,
      );
      await tester.tap(find.text('VGA 640 × 480'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QVGA 320 × 240').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Capture & analyze');
      await reveal(tester, find.text('SIMULATED TARGET: Fresh'));
      await tapText(tester, 'Save inspection image & result');
      expect(data.images, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'history exports only filtered fixture records with source attribution',
    (tester) async {
      final data = DemoSession()..enable();
      final preferences = AppPreferences();
      addTearDown(data.dispose);
      addTearDown(preferences.dispose);
      String? exported, filename;
      await tester.pumpWidget(
        component(
          HistoryScreen(
            readings: data.history,
            analyses: data.analyses,
            onExport: (name, csv) async {
              filename = name;
              exported = csv;
            },
          ),
          data,
          preferences,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All results'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('spoiled').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Export filtered CSV');
      expect(filename, 'aquasense-demo-history.csv');
      expect(exported, contains('SIMULATED'));
      expect(exported, contains('spoiled'));
      expect(exported, isNot(contains('moderate')));
      await tapText(tester, 'Preview CSV');
      expect(find.text('CSV preview'), findsOneWidget);
      await tapText(tester, 'Close');
      await tapText(tester, 'Clear filters');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'settings has no simulation session or authentication bypass controls',
    (tester) async {
      final data = DemoSession();
      final preferences = AppPreferences();
      addTearDown(data.dispose);
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        component(
          SettingsScreen(
            onRefresh: () {},
            onRetryCloud: () {},
            role: 'Verified user',
          ),
          data,
          preferences,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Switch to demo'), findsNothing);
      expect(find.text('Automatic demo telemetry'), findsNothing);
      await tester.tap(find.widgetWithText(SwitchListTile, 'High contrast'));
      await tester.pumpAndSettle();
      expect(preferences.highContrast, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'live auth and data component layouts fit phone, tablet and desktop',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final width in [320.0, 768.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: const AquaSenseApp()),
        );
        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(oceanBackgroundAsset),
            tester.element(find.byType(LoginScreen)),
          ),
        );
        await tester.pump();
        await screenshot(tester, boundary, 'live-login-${width.toInt()}');
        expect(tester.takeException(), isNull);
        await tapText(tester, 'Create an account');
        expect(tester.takeException(), isNull);
        await screenshot(tester, boundary, 'live-register-${width.toInt()}');
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
