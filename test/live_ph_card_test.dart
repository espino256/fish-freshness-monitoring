import 'dart:async';

import 'package:aqua_sense/core/app_theme.dart';
import 'package:aqua_sense/models/telemetry.dart';
import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/models/visual_inspection_history.dart';
import 'package:aqua_sense/screens/dashboard_screen.dart';
import 'package:aqua_sense/screens/history_screen.dart';
import 'package:aqua_sense/widgets/live_ph_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Telemetry reading(String id, double ph, {DateTime? at}) => Telemetry(
  id: id,
  deviceId: 'ESP32-$id',
  ph: ph,
  adcRaw: 2048,
  measuredVoltage: 1.65,
  timestamp: at ?? DateTime.now().toUtc(),
);

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

String? phText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('sensor-ph-value'))).data;

void main() {
  testWidgets(
    'waits for actual telemetry, displays it, and clears the value on error',
    (tester) async {
      final feed = StreamController<List<Telemetry>>();
      addTearDown(feed.close);
      await tester.pumpWidget(host(LivePhCard(readings: feed.stream)));
      expect(phText(tester), 'pH N/A');
      expect(find.text('CONNECTING'), findsOneWidget);
      feed.add([reading('a', 6.81)]);
      await tester.pump();
      expect(phText(tester), 'pH 6.81');
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Device: ESP32-a'), findsOneWidget);
      expect(
        find.textContaining('not automatically linked to this fish'),
        findsOneWidget,
      );
      feed.addError(StateError('permission-denied'));
      await tester.pump();
      expect(phText(tester), 'pH N/A');
      expect(find.textContaining('Unable to read telemetry'), findsOneWidget);
      expect(find.text('pH 6.81'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('verification state does not subscribe or fabricate pH', (
    tester,
  ) async {
    var subscriptions = 0;
    final feed = Stream<List<Telemetry>>.multi((sink) {
      subscriptions++;
      sink.add([reading('a', 6.81)]);
      sink.close();
    });
    await tester.pumpWidget(
      host(
        LivePhCard(
          readings: feed,
          unavailableReason:
              'Verify your email using the Verify button above, then refresh the sensor feed.',
        ),
      ),
    );
    expect(subscriptions, 0);
    expect(phText(tester), 'pH N/A');
    expect(find.text('ACCESS REQUIRED'), findsOneWidget);
    expect(find.textContaining('Verify your email'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'multiple sensors require a choice, and a disappearing sensor never switches silently',
    (tester) async {
      final feed = StreamController<List<Telemetry>>();
      addTearDown(feed.close);
      await tester.pumpWidget(host(LivePhCard(readings: feed.stream)));
      feed.add([reading('a', 6.42), reading('b', 7.18)]);
      await tester.pump();
      expect(phText(tester), 'pH N/A');
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged!('b');
      await tester.pump();
      expect(phText(tester), 'pH 7.18');
      feed.add([reading('a', 6.42)]);
      await tester.pump();
      expect(phText(tester), 'pH N/A');
      expect(find.textContaining('no longer publishing'), findsOneWidget);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged!('a');
      await tester.pump();
      expect(phText(tester), 'pH 6.42');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stale reading shows its timestamp and never claims LIVE', (
    tester,
  ) async {
    final stale = reading('old', 7.11, at: DateTime.utc(2020));
    await tester.pumpWidget(host(LivePhCard(readings: Stream.value([stale]))));
    await tester.pump();
    expect(phText(tester), 'pH 7.11');
    expect(find.text('STALE'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(find.byKey(const Key('sensor-ph-timestamp')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'invalid sensor values and empty feeds never become a zero or sample measurement',
    (tester) async {
      for (final records in [
        <Telemetry>[],
        [reading('invalid', double.nan)],
        [reading('invalid', 14.01)],
      ]) {
        await tester.pumpWidget(
          host(LivePhCard(readings: Stream.value(records))),
        );
        await tester.pump();
        expect(phText(tester), 'pH N/A');
        expect(find.textContaining('NaN'), findsNothing);
        expect(find.text('pH 0.00'), findsNothing);
        expect(find.text('pH 6.32'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'empty dashboard and history contain no invented sensor or image records',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DashboardScreen(readings: Stream.value([]))),
        ),
      );
      await tester.pump();
      expect(phText(tester), 'pH N/A');
      expect(find.textContaining('No telemetry yet'), findsOneWidget);
      expect(find.text('ESP32-PH-01'), findsNothing);
      expect(find.text('pH 6.32'), findsNothing);
      expect(find.text('Sensor history summary'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HistoryScreen(readings: Stream.value([]))),
        ),
      );
      await tester.pump();
      expect(find.text('ESP32-PH-01'), findsNothing);
      expect(find.textContaining('BGS-2026-'), findsNothing);
      expect(find.text('6.32'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('history lists every saved fish-part inspection', (tester) async {
    final records = FishPart.values.map(
      (part) => VisualInspectionHistoryRecord(
        id: 'inspection-${part.name}',
        part: part,
        timestamp: DateTime.utc(2026, 9, 21),
        classification: 'Inconclusive',
        imageUsable: true,
        width: 640,
        height: 480,
        experimentalModel: '${part.name}.tflite',
        inferenceStatus: 'completed',
      ),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryScreen(
            readings: Stream.value([]),
            visualInspections: Stream.value(records.toList()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fish-part image inspections'), findsOneWidget);
    expect(find.text('Eyes'), findsOneWidget);
    expect(find.text('Gills'), findsOneWidget);
    expect(find.text('Skin / Scales'), findsOneWidget);
    expect(find.text('INCONCLUSIVE'), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
  });
}
