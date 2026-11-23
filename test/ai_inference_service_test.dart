import 'dart:async';
import 'dart:typed_data';

import 'package:aqua_sense/models/experimental_ai.dart';
import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/services/ai/ai_runtime.dart';
import 'package:aqua_sense/services/ai_inference_service.dart';
import 'package:aqua_sense/services/visual_inspection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fake_ai_runtime.dart';

Uint8List detailedImage() {
  final image = img.Image(width: 120, height: 120);
  for (var y = 0; y < 120; y++) {
    for (var x = 0; x < 120; x++) {
      final level = ((x ~/ 10) + (y ~/ 10)).isEven ? 50 : 200;
      image.setPixelRgb(x, y, level, level + 20, level + 30);
    }
  }
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'RGB float32 preparation preserves 0-255 values without double normalization',
    () {
      final image = img.Image(width: 224, height: 224);
      img.fill(image, color: img.ColorRgb8(255, 128, 0));
      final input = VisualInspectionService.prepareRgbInput(image);
      expect(input, isA<Float32List>());
      expect(input.length, 1 * 224 * 224 * 3);
      expect(input.sublist(0, 6), [255, 128, 0, 255, 128, 0]);
      expect(input.sublist(input.length - 3), [255, 128, 0]);
    },
  );

  for (final part in FishPart.values) {
    test(
      '${part.label} loads only its assigned model and stays inconclusive',
      () async {
        final loaded = <ExperimentalFishModel>[];
        final runtime = FakeAiRuntime();
        final service = AiInferenceService(
          runtimeFactory: (model) async {
            loaded.add(model);
            return runtime;
          },
        );
        addTearDown(service.dispose);
        final result = await service.analyze(
          VisualInspectionRequest(detailedImage(), part),
        );
        expect(loaded, [ExperimentalFishModel.forPart(part)]);
        expect(result.experimentalAi!.status, ExperimentalAiStatus.completed);
        expect(result.experimentalAi!.scores, [0.2, 0.3, 0.5]);
        expect(result.outcome, VisualFreshness.inconclusive);
        expect(result.hue, isNull);
        expect(runtime.lastInput!.length, 224 * 224 * 3);
        await service.analyze(VisualInspectionRequest(detailedImage(), part));
        expect(loaded.length, 1, reason: 'Reuse the loaded model runtime');
      },
    );
  }

  test(
    'resize uses half-pixel centers and preserves fractional RGB values',
    () {
      final image = img.Image(width: 2, height: 2);
      image.setPixelRgb(0, 0, 0, 20, 40);
      image.setPixelRgb(1, 0, 224, 20, 40);
      image.setPixelRgb(0, 1, 0, 20, 40);
      image.setPixelRgb(1, 1, 224, 20, 40);
      final input = VisualInspectionService.prepareRgbInput(image);
      // At output x=56, TF's source coordinate is (56.5)*2/224-0.5.
      expect(input[56 * 3], closeTo(1, 1e-6));
      expect(input[112 * 3], closeTo(113, 1e-6));
      expect(input[112 * 3 + 1], 20);
      expect(input[112 * 3 + 2], 40);
    },
  );

  test(
    'fine-tuned Scales requires explicit selection; cross-part use is rejected',
    () async {
      final loaded = <ExperimentalFishModel>[];
      final service = AiInferenceService(
        runtimeFactory: (model) async {
          loaded.add(model);
          return FakeAiRuntime();
        },
      );
      addTearDown(service.dispose);
      final candidate = await service.analyze(
        VisualInspectionRequest(detailedImage(), FishPart.skinScales),
        model: ExperimentalFishModel.scalesFinetuned,
      );
      expect(
        candidate.experimentalAi!.model,
        ExperimentalFishModel.scalesFinetuned,
      );
      expect(loaded, [ExperimentalFishModel.scalesFinetuned]);
      final wrong = await service.analyze(
        VisualInspectionRequest(detailedImage(), FishPart.eyes),
        model: ExperimentalFishModel.gills,
      );
      expect(
        wrong.experimentalAi!.status,
        ExperimentalAiStatus.modelUnavailable,
      );
      expect(loaded.length, 1);
    },
  );

  test('corrupt and unsuitable images do not load any model', () async {
    var loads = 0;
    final service = AiInferenceService(
      runtimeFactory: (_) async {
        loads++;
        return FakeAiRuntime();
      },
    );
    addTearDown(service.dispose);
    for (final bytes in [
      Uint8List.fromList([1, 2, 3]),
      img.encodePng(img.Image(width: 120, height: 120)),
    ]) {
      final result = await service.analyze(
        VisualInspectionRequest(bytes, FishPart.gills),
      );
      expect(
        result.experimentalAi!.status,
        ExperimentalAiStatus.qualityRejected,
      );
      expect(result.experimentalAi!.scores, isEmpty);
      expect(result.outcome, VisualFreshness.inconclusive);
    }
    expect(loads, 0);
  });

  for (final (scores, shape) in <(List<double>, List<int>)>[
    ([double.nan, 0.5, 0.5], [1, 3]),
    ([double.infinity, 0, 0], [1, 3]),
    ([-0.1, 0.6, 0.5], [1, 3]),
    ([1.1, 0, 0], [1, 3]),
    ([0.2, 0.2, 0.2], [1, 3]),
    ([0.5, 0.5], [1, 2]),
    ([0.2, 0.3, 0.5], [3]),
  ]) {
    test('rejects invalid distribution $scores / $shape', () async {
      final runtime = FakeAiRuntime()
        ..scores = scores
        ..shape = shape;
      final service = AiInferenceService(runtimeFactory: (_) async => runtime);
      addTearDown(service.dispose);
      final result = await service.analyze(
        VisualInspectionRequest(detailedImage(), FishPart.gills),
      );
      expect(result.experimentalAi!.status, ExperimentalAiStatus.invalidOutput);
      expect(result.experimentalAi!.hasValidDistribution, isFalse);
      expect(result.outcome, VisualFreshness.inconclusive);
      expect(runtime.disposals, 1);
    });
  }

  for (final status in [
    ExperimentalAiStatus.modelUnavailable,
    ExperimentalAiStatus.runtimeUnavailable,
  ]) {
    test('$status is safely reported without fabricated scores', () async {
      final service = AiInferenceService(
        runtimeFactory: (_) async =>
            throw AiRuntimeException(status, 'Unavailable for this test'),
      );
      addTearDown(service.dispose);
      final result = await service.analyze(
        VisualInspectionRequest(detailedImage(), FishPart.gills),
      );
      expect(result.experimentalAi!.status, status);
      expect(result.experimentalAi!.scores, isEmpty);
      expect(result.outcome, VisualFreshness.inconclusive);
    });
  }

  test(
    'failed inference releases the runtime and a later request can recover',
    () async {
      final broken = FakeAiRuntime()
        ..failure = StateError('unsupported operator');
      final working = FakeAiRuntime();
      var loads = 0;
      final service = AiInferenceService(
        runtimeFactory: (_) async => loads++ == 0 ? broken : working,
      );
      addTearDown(service.dispose);
      final request = VisualInspectionRequest(detailedImage(), FishPart.gills);
      expect(
        (await service.analyze(request)).experimentalAi!.status,
        ExperimentalAiStatus.failed,
      );
      expect(broken.disposals, 1);
      expect(
        (await service.analyze(request)).experimentalAi!.status,
        ExperimentalAiStatus.completed,
      );
    },
  );

  test(
    'disposal waits for in-flight work and closes each runtime once',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final runtime = FakeAiRuntime()
        ..onRun = () async {
          started.complete();
          await finish.future;
        };
      final service = AiInferenceService(runtimeFactory: (_) async => runtime);
      final request = VisualInspectionRequest(detailedImage(), FishPart.eyes);
      final pending = service.analyze(request);
      await started.future;
      final disposed = service.dispose();
      expect(runtime.disposals, 0);
      finish.complete();
      await pending;
      await disposed;
      await service.dispose();
      expect(runtime.disposals, 1);
      expect(
        (await service.analyze(request)).experimentalAi!.status,
        ExperimentalAiStatus.disposed,
      );
    },
  );

  test(
    'tensor contract rejects unsupported input/output types and dimensions',
    () {
      expect(
        () => checkTensorContract(
          inputShape: [1, 224, 224, 1],
          outputShape: [1, 3],
          float32: true,
        ),
        throwsA(isA<AiRuntimeException>()),
      );
      expect(
        () => checkTensorContract(
          inputShape: [1, 224, 224, 3],
          outputShape: [1, 3],
          float32: false,
        ),
        throwsA(isA<AiRuntimeException>()),
      );
    },
  );
}
