import 'package:aqua_sense/core/app_theme.dart';
import 'package:aqua_sense/models/experimental_ai.dart';
import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/models/image_region.dart';
import 'package:aqua_sense/widgets/experimental_inspection_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget details({
  ExperimentalFishModel model = ExperimentalFishModel.gills,
  ExperimentalAiStatus status = ExperimentalAiStatus.completed,
  VisualFreshness outcome = VisualFreshness.inconclusive,
  List<double> scores = const [0.2, 0.3, 0.5],
  double textScale = 1,
  ImageRegionMeasurements? measurements,
}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: ExperimentalInspectionDetails(
        result: VisualInspectionResult(
          part: model.part,
          width: 224,
          height: 224,
          isImageUsable: true,
          reason: 'Basic image checks passed.',
          outcome: outcome,
          measurements: measurements,
          experimentalAi: ExperimentalAiResult(
            model: model,
            status: status,
            message: 'Experimental diagnostic output.',
            scores: scores,
            runtime: 'Test double',
            inferenceMicroseconds: 12345,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final outcome in VisualFreshness.values) {
    testWidgets(
      'experimental UI stays Inconclusive even if outcome is $outcome',
      (tester) async {
        await tester.pumpWidget(details(outcome: outcome));
        expect(
          find.text(
            'Verified freshness classification is not available for this inspection.',
          ),
          findsOneWidget,
        );
        expect(find.text('INCONCLUSIVE'), findsOneWidget);
        for (final label in ['Fresh', 'Moderate', 'Spoiled']) {
          expect(find.text('Freshness Classification: $label'), findsNothing);
          expect(find.text(label.toUpperCase()), findsNothing);
        }
        expect(
          find.byKey(const Key('freshness-interpretation-reason')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('gills-validation-limit')), findsOneWidget);
        expect(find.text('N/A'), findsNWidgets(5));
        expect(find.textContaining('NaN'), findsNothing);
      },
    );
  }

  testWidgets(
    'unmapped experimental leader stays separate from verified result',
    (tester) async {
      await tester.pumpWidget(details());
      expect(find.text('Class mapping unverified — Output 2'), findsOneWidget);
      expect(find.text('Model score: 50.00%'), findsOneWidget);
      expect(
        find.text('Named output unavailable — class mapping unverified.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Experimental AI prediction only. Not independently validated.',
        ),
        findsOneWidget,
      );
      expect(find.text('INCONCLUSIVE'), findsOneWidget);
      await tester.pumpWidget(details(scores: [.5, .5, 0]));
      expect(
        find.text('Class mapping unverified — Output 0 / Output 1'),
        findsOneWidget,
      );
      expect(
        find.text('Named output unavailable — class mapping unverified.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('ROI descriptors use degrees, 0–1 S/V, and actual fractions', (
    tester,
  ) async {
    await tester.pumpWidget(
      details(
        measurements: const ImageRegionMeasurements(
          reason: 'Synthetic test descriptors only',
          meanHue: 60,
          meanSaturation: .8666666667,
          meanValue: .6274509804,
          redFraction: .5,
          usableFraction: 1,
        ),
      ),
    );
    final expected = ['60.0°', '0.87', '0.63', '50.0%', '100.0%'];
    for (var i = 0; i < expected.length; i++) {
      expect(
        tester.widget<Text>(find.byKey(Key('image-metric-$i'))).data,
        expected[i],
      );
    }
    expect(find.text('INCONCLUSIVE'), findsOneWidget);
    expect(find.text('N/A'), findsNothing);
  });

  testWidgets('raw scores preserve their indices and use neutral numeric bars', (
    tester,
  ) async {
    await tester.pumpWidget(details(model: ExperimentalFishModel.eyes));
    final expected = [0.2, 0.3, 0.5];
    for (var i = 0; i < 3; i++) {
      final label = tester.widget<Text>(find.byKey(Key('ai-output-$i'))).data;
      expect(label, 'Output $i: ${expected[i].toStringAsPrecision(7)}');
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(Key('ai-score-bar-$i')),
      );
      expect(bar.value, expected[i]);
      expect(bar.color, AppColors.teal);
      if (i > 0) {
        expect(
          tester.getTopLeft(find.byKey(Key('ai-output-$i'))).dy,
          greaterThan(
            tester.getTopLeft(find.byKey(Key('ai-output-${i - 1}'))).dy,
          ),
        );
      }
    }
    expect(
      find.text(
        'Index order is preserved. Scores are not calibrated freshness confidence.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('gills-validation-limit')), findsNothing);
  });

  testWidgets(
    'candidate identity is explicit and its full real hash is inspectable',
    (tester) async {
      final model = ExperimentalFishModel.scalesFinetuned;
      await tester.pumpWidget(details(model: model));
      expect(find.text('Model: ${model.filename}'), findsOneWidget);
      expect(find.text('Version: ${model.version}'), findsOneWidget);
      expect(
        find.textContaining('Separate fine-tuned candidate'),
        findsOneWidget,
      );
      final expansion = find.text('Full model identity (SHA-256)');
      await tester.ensureVisible(expansion);
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('ai-full-hash')))
            .data,
        model.sha256,
      );
      expect(find.text('Inference time: 12.3 ms'), findsOneWidget);
    },
  );

  testWidgets(
    'invalid scores show N/A for non-finite data and no probability bars',
    (tester) async {
      await tester.pumpWidget(
        details(
          status: ExperimentalAiStatus.invalidOutput,
          scores: [double.nan, 0.3, 0.7],
        ),
      );
      expect(find.text('Output 0: N/A'), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Softmax distribution check: failed'), findsOneWidget);
      expect(find.text('INCONCLUSIVE'), findsOneWidget);
    },
  );

  testWidgets('missing outputs never render fabricated zero scores', (
    tester,
  ) async {
    await tester.pumpWidget(
      details(status: ExperimentalAiStatus.runtimeUnavailable, scores: []),
    );
    expect(find.text('Raw output scores: unavailable'), findsOneWidget);
    expect(find.byKey(const Key('ai-output-0')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Softmax distribution check: passed'), findsNothing);
  });

  testWidgets(
    'inspection details fit compact and wide layouts with enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(
          details(model: ExperimentalFishModel.scalesFinetuned, textScale: 1.6),
        );
        await tester.pump();
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(ExperimentalInspectionDetails)),
          ).scale(10),
          16,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Inspection details at $width',
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
