import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';

import '../../models/experimental_ai.dart';
import 'ai_runtime.dart';

Future<AiRuntime> createAiRuntime(ExperimentalFishModel model) async =>
    _NativeRuntime(await loadModelBytes(model));

class _NativeRuntime implements AiRuntime {
  _NativeRuntime(this._bytes);
  Uint8List? _bytes;

  @override
  Future<AiTensorOutput> run(Float32List input) async {
    final bytes = _bytes;
    if (bytes == null) throw StateError('Runtime disposed.');
    // The worker owns construction, invocation and closure. No native pointer,
    // asset-bundle/plugin call, or interpreter crosses an isolate boundary.
    return Isolate.run(() => _infer(bytes, input));
  }

  @override
  Future<void> dispose() async {
    _bytes = null;
  }
}

AiTensorOutput _infer(Uint8List bytes, Float32List input) {
  InterpreterOptions? options;
  Interpreter? interpreter;
  try {
    options = InterpreterOptions()..threads = 2;
    interpreter = Interpreter.fromBuffer(bytes, options: options);
    if (interpreter.getInputTensors().length != 1 ||
        interpreter.getOutputTensors().length != 1) {
      throw const AiRuntimeException(
        ExperimentalAiStatus.invalidOutput,
        'Expected exactly one input and one output tensor.',
      );
    }
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    checkTensorContract(
      inputShape: inputTensor.shape,
      outputShape: outputTensor.shape,
      float32:
          inputTensor.type == TensorType.float32 &&
          outputTensor.type == TensorType.float32,
    );
    final scores = Float32List(3);
    interpreter.run(input.buffer, scores.buffer);
    return AiTensorOutput(
      scores: scores.toList(),
      shape: interpreter.getOutputTensor(0).shape,
      runtime: 'flutter_litert 4.2.0 / LiteRT ${Interpreter.version} / CPU',
      inferenceMicroseconds: interpreter.lastInferenceDurationMicroseconds,
    );
  } on AiRuntimeException {
    rethrow;
  } on Object catch (error) {
    throw AiRuntimeException(
      error.toString().contains('dynamic library')
          ? ExperimentalAiStatus.runtimeUnavailable
          : ExperimentalAiStatus.failed,
      'Native model loading or inference failed: $error',
    );
  } finally {
    interpreter?.close();
    options?.delete();
  }
}
