import 'package:aqua_sense/core/app_preferences.dart';
import 'package:aqua_sense/core/app_theme.dart';
import 'package:aqua_sense/models/telemetry.dart';
import 'package:aqua_sense/screens/app_shell.dart';
import 'package:aqua_sense/screens/dashboard_screen.dart';
import 'package:aqua_sense/services/demo_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'app navigation, pH, charts and controls fit phone, tablet, desktop and landscape at enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final session = DemoSession()..enable();
      final preferences = AppPreferences();
      addTearDown(session.dispose);
      addTearDown(preferences.dispose);
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(768, 1024),
        const Size(1280, 900),
        const Size(1920, 1080),
        const Size(844, 390),
        const Size(1100, 420),
      ]) {
        for (final scale in [1.0, 1.8]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            DemoScope(
              session: session,
              child: PreferencesScope(
                preferences: preferences,
                child: MaterialApp(
                  theme: AppTheme.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: const AppShell(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (var tab = 0; tab < 4; tab++) {
            if (size.width < 1000) {
              tester
                  .widget<NavigationBar>(find.byType(NavigationBar))
                  .onDestinationSelected!(tab);
            } else {
              final label = [
                'Dashboard',
                'Camera & AI Inspection',
                'History',
                'Settings',
              ][tab];
              final destination = find.text(label).first;
              await tester.ensureVisible(destination);
              await tester.tap(destination);
            }
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$size scale $scale tab $tab',
            );
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets(
    'real received history charts remain responsive with long device names',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final records = List.generate(
        40,
        (i) => Telemetry(
          id: '$i',
          deviceId: 'ESP32-PH-device-with-a-long-descriptive-name',
          ph: 6.2 + i % 5 * .2,
          adcRaw: 2048,
          measuredVoltage: 1.65,
          timestamp: DateTime.now().toUtc().subtract(Duration(minutes: i)),
        ),
      );
      for (final width in [320.0, 360.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: DashboardScreen(
                readings: Stream.value([records.first]),
                historyReadings: Stream.value(records),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 12; i++) {
          await tester.drag(scrollable, const Offset(0, -360));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'dashboard $width at scroll $i',
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
