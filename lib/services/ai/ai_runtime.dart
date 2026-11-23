import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../models/experimental_ai.dart';

abstract interface class AiRuntime {
  Future<AiTensorOutput> run(Float32List input);
  Future<void> dispose();
}

typedef AiRuntimeFactory =
    Future<AiRuntime> Function(ExperimentalFishModel model);

class AiTensorOutput {
  const AiTensorOutput({
    required this.scores,
    required this.shape,
    required this.runtime,
    required this.inferenceMicroseconds,
  });
  final List<double> scores;
  final List<int> shape;
  final String runtime;
  final int inferenceMicroseconds;
}

class AiRuntimeException implements Exception {
  const AiRuntimeException(this.status, this.message);
  final ExperimentalAiStatus status;
  final String message;
  @override
  String toString() => message;
}

Future<Uint8List> loadModelBytes(ExperimentalFishModel model) async {
  try {
    final data = await rootBundle.load(model.assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != model.sha256) {
      throw const AiRuntimeException(
        ExperimentalAiStatus.modelUnavailable,
        'Model identity changed. Re-audit this export before using it.',
      );
    }
    return bytes;
  } on AiRuntimeException {
    rethrow;
  } on Object catch (error) {
    throw AiRuntimeException(
      ExperimentalAiStatus.modelUnavailable,
      'Model asset could not be loaded: $error',
    );
  }
}

bool sameShape(List<int> actual, List<int> expected) =>
    actual.length == expected.length &&
    Iterable<int>.generate(
      actual.length,
    ).every((i) => actual[i] == expected[i]);

void checkTensorContract({
  required List<int> inputShape,
  required List<int> outputShape,
  required bool float32,
}) {
  if (!float32 ||
      !sameShape(inputShape, const [1, 224, 224, 3]) ||
      !sameShape(outputShape, const [1, 3])) {
    throw const AiRuntimeException(
      ExperimentalAiStatus.invalidOutput,
      'Expected FLOAT32 input [1,224,224,3] and output [1,3].',
    );
  }
}

/// Numerical consistency only, never a confidence/acceptance threshold.
/// A small tolerance accommodates float32 summation rounding.
bool isSoftmaxDistribution(List<double> scores, List<int> shape) =>
    sameShape(shape, const [1, 3]) &&
    scores.length == 3 &&
    scores.every((s) => s.isFinite && s >= 0 && s <= 1) &&
    (scores.reduce((a, b) => a + b) - 1).abs() <= 1e-5;
