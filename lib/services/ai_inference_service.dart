import 'package:flutter/foundation.dart';

import '../models/experimental_ai.dart';
import '../models/visual_inspection.dart';
import 'visual_inspection_service.dart';
import 'ai/ai_runtime.dart';
import 'ai/ai_runtime_native.dart'
    if (dart.library.js_interop) 'ai/ai_runtime_web.dart'
    as platform;

/// Runs diagnostics on user-selected anatomy; never verifies freshness or pH.
class AiInferenceService {
  AiInferenceService({AiRuntimeFactory? runtimeFactory})
    : _runtimeFactory = runtimeFactory ?? platform.createAiRuntime;

  final AiRuntimeFactory _runtimeFactory;
  final Map<ExperimentalFishModel, AiRuntime> _runtimes = {};
  Future<void> _queue = Future.value();
  Future<void>? _disposal;
  bool _disposed = false;

  Future<VisualInspectionResult> analyze(
    VisualInspectionRequest request, {
    ExperimentalFishModel? model,
  }) {
    final selected = model ?? ExperimentalFishModel.forPart(request.part);
    if (_disposed) {
      return Future.value(
        _empty(request).withExperimentalAi(
          ExperimentalAiResult(
            model: selected,
            status: ExperimentalAiStatus.disposed,
            message: 'Inspection service has been closed.',
          ),
        ),
      );
    }
    final operation = _queue.then((_) => _analyze(request, selected));
    // Serialize runs and disposal; one failed request cannot poison the queue.
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<VisualInspectionResult> _analyze(
    VisualInspectionRequest request,
    ExperimentalFishModel model,
  ) async {
    var inspection = _empty(request);
    AiTensorOutput? output;
    try {
      if (_disposed) {
        throw const AiRuntimeException(
          ExperimentalAiStatus.disposed,
          'Inspection service has been closed.',
        );
      }
      final prepared = await compute(VisualInspectionService.prepare, request);
      inspection = prepared.inspection;
      if (!inspection.isImageUsable || prepared.input == null) {
        return inspection.withExperimentalAi(
          ExperimentalAiResult(
            model: model,
            status: ExperimentalAiStatus.qualityRejected,
            message: inspection.reason,
          ),
        );
      }
      if (model.part != request.part) {
        throw const AiRuntimeException(
          ExperimentalAiStatus.modelUnavailable,
          'This model is not assigned to the selected fish part.',
        );
      }
      if (_disposed) {
        throw const AiRuntimeException(
          ExperimentalAiStatus.disposed,
          'Inspection service has been closed.',
        );
      }
      final runtime = _runtimes[model] ??= await _runtimeFactory(model);
      output = await runtime.run(prepared.input!);
      if (!isSoftmaxDistribution(output.scores, output.shape)) {
        throw const AiRuntimeException(
          ExperimentalAiStatus.invalidOutput,
          'Output must be a finite [1,3] probability distribution. Scores were not accepted.',
        );
      }
      return inspection.withExperimentalAi(
        ExperimentalAiResult(
          model: model,
          status: ExperimentalAiStatus.completed,
          scores: output.scores,
          runtime: output.runtime,
          inferenceMicroseconds: output.inferenceMicroseconds,
          message:
              'Experimental scores only. Class order is unverified. '
              'Freshness remains Inconclusive; these scores are not saved as verified measurements.',
        ),
      );
    } on Object catch (error) {
      final runtime = _runtimes.remove(model);
      if (runtime != null) {
        try {
          await runtime.dispose();
        } on Object {
          /* Preserve the original failure. */
        }
      }
      return inspection.withExperimentalAi(
        ExperimentalAiResult(
          model: model,
          status: error is AiRuntimeException
              ? error.status
              : ExperimentalAiStatus.failed,
          message: error.toString(),
          scores: output?.scores ?? const [],
          runtime: output?.runtime,
          inferenceMicroseconds: output?.inferenceMicroseconds,
        ),
      );
    }
  }

  static VisualInspectionResult _empty(VisualInspectionRequest request) =>
      VisualInspectionResult(
        part: request.part,
        width: 0,
        height: 0,
        isImageUsable: false,
        reason: 'Image inspection is unavailable. Freshness is inconclusive.',
      );

  /// Let in-flight work finish before freeing its resources. Idempotent.
  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= _closeRuntimes();
  }

  Future<void> _closeRuntimes() async {
    await _queue;
    for (final runtime in _runtimes.values) {
      try {
        await runtime.dispose();
      } on Object {
        /* Continue closing other models. */
      }
    }
    _runtimes.clear();
  }
}
