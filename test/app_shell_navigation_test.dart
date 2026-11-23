import 'package:aqua_sense/core/app_preferences.dart';
import 'package:aqua_sense/core/app_theme.dart';
import 'package:aqua_sense/screens/app_shell.dart';
import 'package:aqua_sense/screens/camera_screen.dart';
import 'package:aqua_sense/services/demo_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AI inspection label navigates on mobile and desktop without overflow',
    (tester) async {
      await (FontLoader('AquaSans')
            ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
          .load();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final session = DemoSession()..enable();
      final preferences = AppPreferences();
      addTearDown(session.dispose);
      addTearDown(preferences.dispose);
      for (final width in [320.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(
          DemoScope(
            session: session,
            child: PreferencesScope(
              preferences: preferences,
              child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Camera & HSV'), findsNothing);
        final destination = find.text(
          width < 600 ? 'Inspect' : 'Camera & AI Inspection',
        );
        expect(destination, findsOneWidget);
        await tester.tap(destination);
        await tester.pumpAndSettle();
        expect(find.byType(CameraScreen), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Navigation at $width');
        expect(session.images, isEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
