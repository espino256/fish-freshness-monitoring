import 'dart:convert';

import 'package:aqua_sense/models/experimental_ai.dart';
import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/models/image_region.dart';
import 'package:aqua_sense/models/telemetry.dart';
import 'package:aqua_sense/widgets/live_ph_card.dart';
import 'package:aqua_sense/services/ai/ai_runtime.dart';
import 'package:aqua_sense/services/ai_inference_service.dart';
import 'package:aqua_sense/services/visual_inspection_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqua_sense/core/app_theme.dart';
import 'package:aqua_sense/widgets/experimental_inspection_details.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:aqua_sense/services/ai/ai_runtime_native.dart'
    if (dart.library.js_interop) 'package:aqua_sense/services/ai/ai_runtime_web.dart'
    as platform;

/// No test doubles: all four actual bundled models must load and execute.
void registerAiPlatformChecks() {
  for (final model in ExperimentalFishModel.values) {
    testWidgets(
      'real ${model.filename} inference and disposal',
      (tester) async {
        VisualInspectionResult? completed;
        await tester.runAsync(() async {
          final service = AiInferenceService();
          try {
            final image = img.Image(width: 224, height: 224);
            for (var y = 0; y < image.height; y++) {
              for (var x = 0; x < image.width; x++) {
                image.setPixelRgb(x, y, x % 256, (x + y) % 256, y % 256);
              }
            }
            final request = VisualInspectionRequest(
              img.encodePng(image),
              model.part,
            );
            final result = await service.analyze(request, model: model);
            final ai = result.experimentalAi!;
            expect(
              ai.status,
              ExperimentalAiStatus.completed,
              reason: '${model.filename}: ${ai.status.label}: ${ai.message}',
            );
            expect(result.outcome, VisualFreshness.inconclusive);
            expect(ai.model, model);
            expect(isSoftmaxDistribution(ai.scores, const [1, 3]), isTrue);
            // Original, unmodified files on Python LiteRT 2.4.0, identical
            // synthetic RGB tensor; tools/inspect_tflite.py --check-batch-one.
            const originalCpuScores = {
              ExperimentalFishModel.gills: [
                0.6140145659446716,
                0.05207594111561775,
                0.3339095413684845,
              ],
              ExperimentalFishModel.eyes: [
                0.959062933921814,
                0.02609533816576004,
                0.014841724187135696,
              ],
              ExperimentalFishModel.scales: [
                0.6892409324645996,
                0.10791781544685364,
                0.20284128189086914,
              ],
              ExperimentalFishModel.scalesFinetuned: [
                0.5372974872589111,
                0.2518008053302765,
                0.21090169250965118,
              ],
            };
            for (var i = 0; i < 3; i++) {
              expect(
                ai.scores[i],
                closeTo(originalCpuScores[model]![i], 1e-4),
                reason: 'Numeric parity with original TFLite output $i',
              );
            }
            final repeated = (await service.analyze(
              request,
              model: model,
            )).experimentalAi!;
            expect(repeated.status, ExperimentalAiStatus.completed);
            for (var i = 0; i < 3; i++) {
              // Numeric repeatability tolerance; not a scientific confidence gate.
              expect(repeated.scores[i], closeTo(ai.scores[i], 1e-5));
            }
            completed = result;
            // This machine-readable record is emitted only after real execution.
            debugPrint(
              'AQUASENSE_INFERENCE ${jsonEncode({'model': model.filename, 'sha256': model.sha256, 'platform': kIsWeb ? 'Chrome/web' : defaultTargetPlatform.name, 'runtime': ai.runtime, 'scores': ai.scores, 'inferenceMicroseconds': ai.inferenceMicroseconds, 'scientificallyValidated': false})}',
            );
          } finally {
            await service.dispose();
          }
        });
        if (completed case final result?) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ExperimentalInspectionDetails(result: result),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('INCONCLUSIVE'), findsOneWidget);
          expect(find.text('Model: ${model.filename}'), findsOneWidget);
          for (var i = 0; i < 3; i++) {
            expect(
              tester.widget<Text>(find.byKey(Key('ai-output-$i'))).data,
              'Output $i: ${result.experimentalAi!.scores[i].toStringAsPrecision(7)}',
            );
          }
          expect(find.text('N/A'), findsNWidgets(5));
          await tester.pumpWidget(const SizedBox());
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
  testWidgets(
    'real ROI metrics coexist with model output without changing the RGB input',
    (tester) async {
      VisualInspectionResult? completed;
      await tester.runAsync(() async {
        final service = AiInferenceService();
        try {
          // Keep this synthetic execution input in the integration app's source
          // root so Flutter's web launcher can bundle it independently of test/.
          final image = img.Image(width: 256, height: 256);
          img.fill(image, color: img.ColorRgb8(100, 100, 100));
          for (var y = 64; y < 192; y++) {
            for (var x = 64; x < 192; x++) {
              final red = ((x ~/ 4) + (y ~/ 4)).isEven;
              image.setPixelRgb(x, y, red ? 200 : 20, red ? 20 : 120, 20);
            }
          }
          final bytes = img.encodePng(image);
          final base = await service.analyze(
            VisualInspectionRequest(bytes, FishPart.gills),
          );
          final selected = await service.analyze(
            VisualInspectionRequest(
              bytes,
              FishPart.gills,
              region: const ImageRegion(.25, .25, .75, .75),
            ),
          );
          expect(
            selected.experimentalAi!.status,
            ExperimentalAiStatus.completed,
          );
          expect(selected.experimentalAi!.scores, base.experimentalAi!.scores);
          expect(selected.hue, closeTo(60, 1e-9));
          expect(selected.saturation, closeTo(.8666666666667, 1e-9));
          expect(selected.value, closeTo(160 / 255, 1e-9));
          expect(selected.redFraction, .5);
          expect(selected.usableFraction, 1);
          expect(selected.outcome, VisualFreshness.inconclusive);
          completed = selected;
          debugPrint(
            'AQUASENSE_ROI_INFERENCE ${jsonEncode({'platform': kIsWeb ? 'Chrome/web' : defaultTargetPlatform.name, 'scores': selected.experimentalAi!.scores, 'hue': selected.hue, 'saturation': selected.saturation, 'value': selected.value, 'redFraction': selected.redFraction, 'usableFraction': selected.usableFraction})}',
          );
        } finally {
          await service.dispose();
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LivePhCard(
                    simulated: true,
                    snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                      Telemetry(
                        id: 'ui-fixture',
                        deviceId: 'SYNTHETIC-SENSOR-FIXTURE',
                        ph: 6.81,
                        adcRaw: 2048,
                        measuredVoltage: 1.65,
                        timestamp: DateTime.now().toUtc(),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  ExperimentalInspectionDetails(result: completed!),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('60.0°'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.text('pH 6.81'), findsOneWidget);
      expect(find.text('SIMULATED'), findsOneWidget);
      expect(find.text('INCONCLUSIVE'), findsOneWidget);
      expect(
        find.text('Named output unavailable — class mapping unverified.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  const referenceAsset = String.fromEnvironment('AQUASENSE_AI_REFERENCE_ASSET');
  testWidgets(
    'real-image Keras reference parity (requires exported fixtures)',
    (tester) async {
      await tester.runAsync(() async {
        final reference =
            jsonDecode(await rootBundle.loadString(referenceAsset))
                as Map<String, dynamic>;
        final model = ExperimentalFishModel.values.singleWhere(
          (m) => m.filename == reference['modelFile'],
        );
        expect(reference['modelSha256'], model.sha256);
        final imageData = await rootBundle.load(
          reference['imageAsset'] as String,
        );
        final image = imageData.buffer.asUint8List(
          imageData.offsetInBytes,
          imageData.lengthInBytes,
        );
        expect(sha256.convert(image).toString(), reference['imageSha256']);
        final tensorData = await rootBundle.load(
          reference['tensorAsset'] as String,
        );
        final tensorBytes = tensorData.buffer.asUint8List(
          tensorData.offsetInBytes,
          tensorData.lengthInBytes,
        );
        expect(
          sha256.convert(tensorBytes).toString(),
          reference['tensorSha256'],
        );
        expect(reference['tensorShape'], [1, 224, 224, 3]);
        expect(tensorBytes.length, 224 * 224 * 3 * 4);
        final tensorView = ByteData.sublistView(tensorBytes);
        final tensor = Float32List(224 * 224 * 3);
        for (var i = 0; i < tensor.length; i++) {
          tensor[i] = tensorView.getFloat32(i * 4, Endian.little);
        }
        final prepared = VisualInspectionService.prepare(
          VisualInspectionRequest(image, model.part),
        );
        expect(prepared.inspection.isImageUsable, isTrue);
        for (var i = 0; i < tensor.length; i++) {
          expect(
            prepared.input![i],
            closeTo(tensor[i], 1e-3),
            reason: 'Preprocessing element $i',
          );
        }
        final runtime = await platform.createAiRuntime(model);
        try {
          // Both runtimes receive exactly the same canonical real-image tensor.
          final output = await runtime.run(tensor);
          expect(isSoftmaxDistribution(output.scores, output.shape), isTrue);
          final expected = (reference['kerasScores'] as List).cast<num>();
          expect(expected.length, 3);
          for (var i = 0; i < 3; i++) {
            // Notebook export uses atol=rtol=1e-3 for numerical conversion checks.
            expect(
              output.scores[i],
              closeTo(expected[i].toDouble(), 1e-3 + 1e-3 * expected[i].abs()),
            );
          }
        } finally {
          await runtime.dispose();
        }
      });
    },
    skip: referenceAsset.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
