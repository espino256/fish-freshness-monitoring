import 'dart:io';
import 'dart:async';

import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/models/experimental_ai.dart';
import 'package:aqua_sense/services/ai_inference_service.dart';
import 'package:aqua_sense/services/ai/ai_runtime.dart';
import 'package:aqua_sense/services/demo_session.dart';
import 'package:aqua_sense/services/visual_inspection_service.dart';
import 'package:aqua_sense/screens/camera_screen.dart';
import 'package:aqua_sense/widgets/fish_region_selector.dart';
import 'package:aqua_sense/models/image_region.dart';
import 'package:aqua_sense/models/telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'support/fake_ai_runtime.dart';
import 'support/region_fixture.dart';

Widget camera({
  bool canSave = false,
  Stream<List<Telemetry>>? phReadings,
  Future<void> Function(VisualInspectionResult, ExperimentalFishModel)?
  onSaveInspection,
}) => MaterialApp(
  home: Scaffold(
    body: CameraScreen(
      canSave: canSave,
      onSaveInspection: onSaveInspection,
      phReadings: phReadings,
      inferenceService: AiInferenceService(
        runtimeFactory: (_) async => FakeAiRuntime(),
      ),
    ),
  ),
);

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 160,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> importImage(WidgetTester tester) async {
  final button = find.text('Analyze gallery image');
  await reveal(tester, button);
  await tester.tap(button);
  await tester.pump();
  await finishAnalysis(tester);
  await reveal(tester, find.byKey(const Key('inspection-reason')));
}

Future<void> finishAnalysis(WidgetTester tester) async {
  // File reads and compute run outside the widget test's fake async clock.
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byKey(const Key('inspection-busy')).evaluate().isEmpty) {
      break;
    }
  }
  expect(find.byKey(const Key('inspection-busy')), findsNothing);
  await tester.pumpAndSettle();
}

void main() {
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  late Directory directory;
  late File imageFile;
  String? selectedPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aquasense-inspection-');
    imageFile = File('${directory.path}/sample.png');
    final image = img.Image(width: 120, height: 120);
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 120; x++) {
        final level = ((x ~/ 10) + (y ~/ 10)).isEven ? 60 : 200;
        image.setPixelRgb(x, y, level, level, level);
      }
    }
    await imageFile.writeAsBytes(img.encodePng(image));
    selectedPath = imageFile.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, (call) async {
          expect(call.method, 'pickImage');
          return selectedPath;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null);
    await directory.delete(recursive: true);
  });

  for (final part in FishPart.values) {
    testWidgets(
      'gallery ${part.label} shows N/A, reason and Inconclusive at 320px',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(camera(canSave: true));
        final selector = find.byKey(const Key('fish-part-selector'));
        await reveal(tester, selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(part.label).last);
        await tester.pumpAndSettle();
        await importImage(tester);
        expect(find.text('INCONCLUSIVE'), findsOneWidget);
        expect(find.text('Selected fish part: ${part.label}'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('inspection-reason'))).data,
          contains('No validated model is available for ${part.label}'),
        );
        expect(find.text('N/A'), findsNWidgets(5));
        expect(
          find.text('Inference status: Inference completed'),
          findsOneWidget,
        );
        expect(
          find.text('Model: ${ExperimentalFishModel.forPart(part).filename}'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('ai-output-0')), findsOneWidget);
        expect(find.byKey(const Key('ai-output-1')), findsOneWidget);
        expect(find.byKey(const Key('ai-output-2')), findsOneWidget);
        expect(find.textContaining('NaN'), findsNothing);
        expect(find.textContaining('Infinity'), findsNothing);
        expect(find.text('Fresh'), findsNothing);
        expect(find.text('Moderate'), findsNothing);
        expect(find.text('Spoiled'), findsNothing);
        expect(tester.takeException(), isNull);

        await reveal(tester, selector, delta: -160);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        final nextPart =
            FishPart.values[(part.index + 1) % FishPart.values.length];
        await tester.tap(find.text(nextPart.label).last);
        await tester.pumpAndSettle();
        await reveal(
          tester,
          find.text(
            'Previous scores and descriptors cleared. Apply a fish-part region to analyze this image again.',
          ),
        );
        expect(find.byKey(const Key('inspection-reason')), findsNothing);
        expect(find.text('INCONCLUSIVE'), findsNothing);
        expect(find.byKey(const Key('ai-output-0')), findsNothing);
        expect(find.byKey(const Key('ai-output-1')), findsNothing);
        expect(find.byKey(const Key('ai-output-2')), findsNothing);
        expect(find.byKey(const Key('ai-model')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('saving a part inspection is explicit and records its type', (
    tester,
  ) async {
    VisualInspectionResult? savedInspection;
    ExperimentalFishModel? savedModel;
    await tester.pumpWidget(
      camera(
        canSave: true,
        onSaveInspection: (inspection, model) async {
          savedInspection = inspection;
          savedModel = model;
        },
      ),
    );
    await reveal(tester, find.byKey(const Key('fish-part-selector')));
    await tester.tap(find.byKey(const Key('fish-part-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eyes').last);
    await tester.pumpAndSettle();
    await importImage(tester);
    final saveButton = find.text('Save inspection to history');
    await reveal(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(savedInspection?.part, FishPart.eyes);
    expect(savedInspection?.classification, 'Inconclusive');
    expect(savedModel, ExperimentalFishModel.eyes);
    expect(find.text('Saved to history'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'corrupt gallery image stays inconclusive without a preview exception',
    (tester) async {
      await tester.runAsync(() => imageFile.writeAsBytes([1, 2, 3]));
      await tester.pumpWidget(camera());
      await importImage(tester);
      expect(find.text('INCONCLUSIVE'), findsOneWidget);
      expect(find.text('N/A'), findsNWidgets(5));
      expect(
        tester.widget<Text>(find.byKey(const Key('inspection-reason'))).data,
        contains('valid JPEG or PNG'),
      );
      expect(find.byKey(const Key('image-roi-panel')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('canceling the gallery does not fabricate a result', (
    tester,
  ) async {
    selectedPath = null;
    await tester.pumpWidget(camera());
    final button = find.text('Analyze gallery image');
    await reveal(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('camera-message')));
    expect(find.text('Image selection canceled.'), findsOneWidget);
    expect(find.text('INCONCLUSIVE'), findsNothing);
    expect(find.byKey(const Key('inspection-reason')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unreadable upload replaces the previous inspection', (
    tester,
  ) async {
    await tester.pumpWidget(camera());
    await importImage(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('inspection-reason'))).data,
      contains('Basic image checks passed'),
    );
    selectedPath = '${directory.path}/missing.png';
    await reveal(tester, find.text('Analyze gallery image'), delta: -160);
    await importImage(tester);
    expect(find.text('INCONCLUSIVE'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('inspection-reason'))).data,
      contains('could not be read'),
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'oversized upload shows an inconclusive reason without decoding',
    (tester) async {
      await tester.runAsync(() async {
        final file = await imageFile.open(mode: FileMode.write);
        await file.truncate(10 * 1024 * 1024 + 1);
        await file.close();
      });
      await tester.pumpWidget(camera());
      await importImage(tester);
      expect(find.text('INCONCLUSIVE'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('inspection-reason'))).data,
        contains('10 MiB'),
      );
      expect(find.text('N/A'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unavailable browser runtime shows no fabricated output scores', (
    tester,
  ) async {
    final service = AiInferenceService(
      runtimeFactory: (_) async => throw const AiRuntimeException(
        ExperimentalAiStatus.runtimeUnavailable,
        'Runtime unavailable for test',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraScreen(canSave: true, inferenceService: service),
        ),
      ),
    );
    await importImage(tester);
    expect(find.text('Inference status: Runtime unavailable'), findsOneWidget);
    expect(find.text('Raw output scores: unavailable'), findsOneWidget);
    expect(find.byKey(const Key('ai-output-0')), findsNothing);
    expect(find.text('INCONCLUSIVE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fine-tuned Scales is explicit and clears original scores', (
    tester,
  ) async {
    await tester.runAsync(
      () => imageFile.writeAsBytes(img.encodePng(regionFixture())),
    );
    final loaded = <ExperimentalFishModel>[];
    final service = AiInferenceService(
      runtimeFactory: (model) async {
        loaded.add(model);
        return FakeAiRuntime();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraScreen(canSave: false, inferenceService: service),
        ),
      ),
    );
    await reveal(tester, find.byKey(const Key('fish-part-selector')));
    await tester.tap(find.byKey(const Key('fish-part-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(FishPart.skinScales.label).last);
    await tester.pumpAndSettle();
    await importImage(tester);
    expect(loaded, [ExperimentalFishModel.scales]);
    await reveal(tester, find.byType(FishRegionSelector), delta: -160);
    tester
        .widget<FishRegionSelector>(find.byType(FishRegionSelector))
        .onApply(const ImageRegion(.25, .25, .75, .75));
    await tester.pump();
    await finishAnalysis(tester);
    await reveal(tester, find.byKey(const Key('inspection-reason')));
    expect(find.text('60.0°'), findsOneWidget);
    final selector = find.byKey(const Key('scales-model-selector'));
    await reveal(tester, selector, delta: -160);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fine-tuned candidate').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-output-0')), findsNothing);
    expect(find.byKey(const Key('image-metric-0')), findsNothing);
    await importImage(tester);
    expect(loaded, [
      ExperimentalFishModel.scales,
      ExperimentalFishModel.scalesFinetuned,
    ]);
    expect(
      find.text('Model: aquasense_scales_finetuned_model.tflite'),
      findsOneWidget,
    );
    expect(find.text('INCONCLUSIVE'), findsOneWidget);
    expect(find.text('N/A'), findsNWidgets(5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a new gallery selection clears previous outputs even when canceled',
    (tester) async {
      await tester.pumpWidget(camera(canSave: true));
      await importImage(tester);
      expect(find.byKey(const Key('ai-output-0')), findsOneWidget);
      selectedPath = null;
      final button = find.text('Analyze gallery image');
      await reveal(tester, button, delta: -160);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Capture or import an image to begin.'));
      expect(find.byKey(const Key('ai-model')), findsNothing);
      expect(find.byKey(const Key('ai-output-0')), findsNothing);
      expect(find.text('INCONCLUSIVE'), findsNothing);
      await reveal(
        tester,
        find.byKey(const Key('camera-message')),
        delta: -160,
      );
      expect(find.text('Image selection canceled.'), findsOneWidget);

      final selector = find.byKey(const Key('fish-part-selector'));
      await reveal(tester, selector, delta: -160);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eyes').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Capture or import an image to begin.'));
      expect(find.text('Image selection canceled.'), findsNothing);
      expect(find.byKey(const Key('ai-output-0')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'applied ROI computes descriptors; edit, rotation, part and image clear them',
    (tester) async {
      await tester.runAsync(
        () => imageFile.writeAsBytes(img.encodePng(regionFixture())),
      );
      await tester.pumpWidget(camera(canSave: true));
      await importImage(tester);
      expect(
        find.text('N/A'),
        findsNWidgets(5),
        reason: 'No draft is auto-applied.',
      );
      await reveal(tester, find.byType(FishRegionSelector), delta: -160);
      tester
          .widget<FishRegionSelector>(find.byType(FishRegionSelector))
          .onApply(const ImageRegion(.25, .25, .75, .75));
      await tester.pump();
      await finishAnalysis(tester);
      await reveal(tester, find.byKey(const Key('inspection-reason')));
      expect(
        tester.widget<Text>(find.byKey(const Key('image-metric-0'))).data,
        '60.0°',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('image-metric-4'))).data,
        '100.0%',
      );
      expect(find.text('INCONCLUSIVE'), findsOneWidget);
      await reveal(tester, find.byType(FishRegionSelector), delta: -160);
      tester
          .widget<FishRegionSelector>(find.byType(FishRegionSelector))
          .onChanged();
      await tester.pump();
      expect(find.byKey(const Key('image-metric-0')), findsNothing);
      expect(find.byKey(const Key('ai-output-0')), findsNothing);
      tester
          .widget<FishRegionSelector>(find.byType(FishRegionSelector))
          .onApply(const ImageRegion(.25, .25, .75, .75));
      await tester.pump();
      await finishAnalysis(tester);
      await reveal(tester, find.text('Rotate image'), delta: -160);
      await tester.tap(find.text('Rotate image'));
      await tester.pump();
      await finishAnalysis(tester);
      await reveal(tester, find.byKey(const Key('inspection-reason')));
      expect(
        find.text('N/A'),
        findsNWidgets(5),
        reason: 'Rotation invalidates ROI.',
      );
      await reveal(
        tester,
        find.byKey(const Key('fish-part-selector')),
        delta: -160,
      );
      await tester.tap(find.byKey(const Key('fish-part-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eyes').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-output-0')), findsNothing);
      await reveal(tester, find.byType(FishRegionSelector));
      expect(
        tester.widget<FishRegionSelector>(find.byType(FishRegionSelector)).part,
        FishPart.eyes,
      );
      tester
          .widget<FishRegionSelector>(find.byType(FishRegionSelector))
          .onApply(const ImageRegion(.25, .25, .75, .75));
      await tester.pump();
      await finishAnalysis(tester);
      await reveal(tester, find.byKey(const Key('inspection-reason')));
      expect(find.text('Model: aquasense_eyes_model.tflite'), findsOneWidget);
      expect(find.text('60.0°'), findsOneWidget);
      selectedPath = null;
      await reveal(tester, find.text('Analyze gallery image'), delta: -160);
      await tester.tap(find.text('Analyze gallery image'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('image-metric-0')), findsNothing);
      expect(find.byKey(const Key('ai-output-0')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('sensor pH stays independent of image outputs and part changes', (
    tester,
  ) async {
    final feed = StreamController<List<Telemetry>>();
    addTearDown(feed.close);
    await tester.pumpWidget(camera(canSave: true, phReadings: feed.stream));
    feed.add([
      Telemetry(
        id: 'real-feed-fixture',
        deviceId: 'ESP32-test',
        ph: 6.81,
        adcRaw: 2048,
        measuredVoltage: 1.65,
        timestamp: DateTime.now().toUtc(),
      ),
    ]);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('sensor-ph-value'))).data,
      'pH 6.81',
    );
    await importImage(tester);
    expect(find.text('INCONCLUSIVE'), findsOneWidget);
    final before = tester
        .widget<Text>(find.byKey(const Key('ai-output-0')))
        .data;
    feed.add([
      Telemetry(
        id: 'real-feed-fixture',
        deviceId: 'ESP32-test',
        ph: 7.11,
        adcRaw: 2050,
        measuredVoltage: 1.66,
        timestamp: DateTime.now().toUtc(),
      ),
    ]);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-output-0'))).data,
      before,
    );
    expect(find.text('INCONCLUSIVE'), findsOneWidget);
    await reveal(tester, find.byKey(const Key('sensor-ph-value')), delta: -160);
    expect(
      tester.widget<Text>(find.byKey(const Key('sensor-ph-value'))).data,
      'pH 7.11',
    );
    await reveal(tester, find.byKey(const Key('fish-part-selector')));
    await tester.tap(find.byKey(const Key('fish-part-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eyes').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-output-0')), findsNothing);
    await reveal(tester, find.byKey(const Key('sensor-ph-value')), delta: -160);
    expect(
      tester.widget<Text>(find.byKey(const Key('sensor-ph-value'))).data,
      'pH 7.11',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late inference completion cannot update a closed camera screen',
    (tester) async {
      final service = _PendingInspectionService();
      final session = DemoSession()..enable();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        DemoScope(
          session: session,
          child: MaterialApp(
            home: Scaffold(
              body: CameraScreen(canSave: true, inferenceService: service),
            ),
          ),
        ),
      );
      final button = find.text('Use demo sample');
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 100 && !service.started.isCompleted;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        service.started.isCompleted,
        isTrue,
        reason: 'The injected inference must be in flight.',
      );
      await tester.pumpWidget(const SizedBox());
      service.pending.complete(
        VisualInspectionResult(
          part: FishPart.gills,
          width: 224,
          height: 224,
          isImageUsable: true,
          reason: 'Image checks passed.',
          experimentalAi: ExperimentalAiResult(
            model: ExperimentalFishModel.gills,
            status: ExperimentalAiStatus.completed,
            message: 'Delayed test output.',
            scores: [0.2, 0.3, 0.5],
          ),
        ),
      );
      await tester.pump();
      expect(service.disposals, 1);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ai-output-0')), findsNothing);
    },
  );
}

/// Controls completion timing only; actual inference is covered independently.
class _PendingInspectionService extends AiInferenceService {
  final started = Completer<void>();
  final pending = Completer<VisualInspectionResult>();
  int disposals = 0;

  @override
  Future<VisualInspectionResult> analyze(
    VisualInspectionRequest request, {
    ExperimentalFishModel? model,
  }) {
    started.complete();
    return pending.future;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}
