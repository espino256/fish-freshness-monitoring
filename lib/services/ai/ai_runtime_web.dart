import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';

import '../../models/experimental_ai.dart';
import 'ai_runtime.dart';
import 'batch_one_model.dart';

Future<AiRuntime> createAiRuntime(ExperimentalFishModel model) async {
  final bytes = await loadModelBytes(model);
  LiteRtInterpreter? interpreter;
  try {
    // 4.2.0's async LiteRT.js API auto-loads its pinned JS/WASM runtime.
    // CPU/WASM avoids assuming WebGPU availability or numerical equivalence.
    // The exports have concrete batch-one shapes but dynamic batch signatures.
    // LiteRT.js requires static signatures. Bind only that metadata in a copy;
    // the registered file and every weight/operation remain unchanged.
    final pending = LiteRtInterpreter.fromBytes(
      specializeBatchOne(bytes),
      accelerator: 'wasm',
    );
    interpreter = await pending.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        // If compilation eventually completes, release the abandoned model.
        unawaited(
          pending.then(
            (lateModel) => lateModel.close(),
            onError: (Object _) {},
          ),
        );
        throw const AiRuntimeException(
          ExperimentalAiStatus.runtimeUnavailable,
          'Browser runtime initialization timed out. Check network and WASM support.',
        );
      },
    );
    if (interpreter.getOutputTensors().length != 1) {
      throw const AiRuntimeException(
        ExperimentalAiStatus.invalidOutput,
        'Expected exactly one output tensor.',
      );
    }
    final input = interpreter.getInputTensor(0);
    final output = interpreter.getOutputTensor(0);
    checkTensorContract(
      inputShape: input.shape,
      outputShape: output.shape,
      float32:
          input.type == TensorType.float32 && output.type == TensorType.float32,
    );
    return _WebRuntime(interpreter);
  } on AiRuntimeException {
    interpreter?.close();
    rethrow;
  } on Object catch (error) {
    interpreter?.close();
    throw AiRuntimeException(
      ExperimentalAiStatus.runtimeUnavailable,
      'Browser model/runtime could not load. Check network, WASM support and operators. $error',
    );
  }
}

class _WebRuntime implements AiRuntime {
  _WebRuntime(this._interpreter);
  final LiteRtInterpreter _interpreter;

  @override
  Future<AiTensorOutput> run(Float32List input) async {
    final scores = Float32List(3);
    await _interpreter.runForMultipleInputs([input], {0: scores});
    return AiTensorOutput(
      scores: scores.toList(),
      shape: _interpreter.getOutputTensor(0).shape,
      runtime:
          'flutter_litert 4.2.0 / LiteRT.js 2.6.0 / ${_interpreter.activeAccelerator}',
      inferenceMicroseconds: _interpreter.lastInferenceDurationMicroseconds,
    );
  }

  @override
  Future<void> dispose() async => _interpreter.close();
}
